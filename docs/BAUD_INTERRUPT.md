# Baud lập trình được và interrupt UART

Bản triển khai ngày 16/10/2026. Giữ nguyên map 0x00–0x14 và FIFO TX/RX 16 byte.
Baud động và ngắt dùng các thanh ghi mới; cần **SOF mới + BSP mới + ELF mới**.
Tài liệu/slide trước ngày này mô tả phiên bản cũ, baud cố định và polling RX.

## Cách dùng trên kit

Hệ thống đã được generate và firmware đã được build trong lần triển khai.
Trong môi trường công cụ, Quartus compile/timing PASS nhưng IP Nios V bị đánh
Simulation-Only. Chạy lại compile trong terminal bình thường có license hợp lệ:

```bash
cd /home/kien/Documents/uart
bash UART/fpga/build.sh compile
# Chỉ tiếp tục nếu không còn REVIEW REQUIRED về license:
bash UART/fpga/program.sh 1 1 echo
```

Từ source mới tải về, cần tạo đủ hệ thống và BSP trước:

```bash
bash UART/fpga/build.sh all
bash UART/firmware/build.sh all echo
bash UART/fpga/program.sh 1 1 echo
```

Mở JTAG bằng `bash UART/firmware/terminal_jtag.sh` và mở UART bằng:

```bash
bash UART/firmware/terminal_uart.sh /dev/ttyUSB0
```

Mặc định sau reset vẫn là 115200 8N1. Gõ văn bản và Enter để chat như trước.
Để đổi baud, **dừng gửi bên picocom**, kết thúc các dòng đang nhập. Tại JTAG gõ:

```text
:baud 9600
```

Lệnh này dành riêng cho JTAG, không được chuyển thành tin nhắn sang UART.
Firmware đợi queue TX và đợt TX hiện tại hoàn tất, đợi RX yên, rồi APPLY.
Nếu thành công JTAG báo:

```text
BAUD: requested 9600; actual 9586; change picocom baud now
```

Đóng picocom bằng Ctrl+A, Ctrl+X; mở lại:

```bash
bash UART/firmware/terminal_uart.sh /dev/ttyUSB0 9600
```

Đổi lại bằng `:baud 115200` trên JTAG rồi mở picocom ở 115200. KEY0 reset CPU và
ngoại vi, đồng thời đưa baud về 115200. Khi đổi, phía PC phải ngừng gửi; UART
không tự thỏa thuận baud với USB-UART, không phải auto-baud. JTAG không phụ
thuộc baud UART nên vẫn là kênh cấu hình trong suốt quá trình.

Nếu một dòng UART chưa kết thúc, lệnh bị từ chối. Nếu có hoạt động RX trong
lúc chuẩn bị đổi, có thể bị hủy. Thời gian đợi RX yên sau khi TX đã thoát queue
là 100 ms; khi hết hạn, baud cũ được giữ. Không tiếp nhận thêm phím JTAG trong
khi lệnh đang chờ; sau đó xử lý tiếp các phím đã được IP JTAG đệm.

## Register map mới

Địa chỉ tuyệt đối = UART_BASE (hiện 0x21000) + offset; đơn vị byte.

| Offset | Register | Quyền / reset | Ý nghĩa |
|---|---|---|---|
| 0x18 | BAUD_DIV_SHADOW | RW / 27 | [15:0] divider dự kiến; byte lane 0/1 cập nhật riêng, bit cao bỏ qua |
| 0x1C | BAUD_DIV_ACTIVE | RO / 27 | [15:0] divider thực sự đang chạy |
| 0x20 | BAUD_CONTROL_STATUS | Mixed | Đọc bit 0 BUSY; bit 1 REJECTED; bit 3 DIRTY. Ghi bit 1 W1C xóa REJECTED, bit 2 APPLY là lệnh một lần |
| 0x24 | INT_ENABLE | RW / 0 | [0] RX không rỗng; [1] TX_DONE; [2] RX overrun; [3] RX framing/break |
| 0x28 | INT_STATUS | RO | Bốn nguồn thô cùng vị trí bit; không bị INT_ENABLE che |

Bổ sung 17/10: FIFO_STATUS (0x14) bit 5 lưu lỗi RX framing/break, ghi 1 để xóa.
Ngắt bit 3 đưa lỗi lên JTAG ngay khi phát hiện, kể cả khi không có byte/Enter.
Xem [UART_ERROR_DISPLAY.md](UART_ERROR_DISPLAY.md) về hiển thị lỗi hai chiều,
giới hạn phát hiện sai baud và thao tác picocom.

Đọc 0x20 bit 2 trả 0. DIRTY = SHADOW khác ACTIVE, không phải “đang có lệnh chờ”.
BUSY = chưa đủ điều kiện idle TX/RX. Sau reset BUSY tạm bằng 1 cho đến khi RX
được xác nhận yên; trạng thái này độc lập với REJECTED và DIRTY. Divider 0 có thể
ghi vào SHADOW nhưng APPLY bị từ chối. Bit reserved đọc 0, ghi bỏ qua. Lệnh
APPLY bị từ chối đặt REJECTED, giao dịch bus vẫn hoàn tất bình thường. APPLY
thành công xóa REJECTED. Một lệnh APPLY mới có ưu tiên so với xóa cờ cùng cạnh.
RO write / địa chỉ không hợp lệ vẫn trả PSLVERR như thiết kế cũ.

APPLY chỉ thành công khi TX_DONE=1, RX core idle, RX đã đồng bộ đang mức cao,
không có start edge đang được phát hiện, và đã qua 16 tick xác nhận RX idle.
RX core trở lại IDLE ở giữa stop bit cuối, nên cần khoảng xác nhận này trước
khi đổi baud. Khi APPLY thành công, ACTIVE cập nhật và bộ đếm/tick được reset
cùng cạnh; không có yêu cầu APPLY pending tự đổi về sau. Mọi điều kiện được
đánh giá tại cạnh commit. Peer vẫn phải ngừng truyền: một start vật lý đến
sau cửa sổ đồng bộ không thể được phần cứng tiên đoán.

Không tự xóa RX FIFO khi đổi baud. Firmware chat kiểm tra cả RX FIFO phần cứng,
ring buffer ISR và trạng thái dòng, với kiểm tra lại trong critical section.
Các ứng dụng khác dùng driver phải tự điều phối dữ liệu và phía gửi tương tự.

## Bộ chia baud

Clock hệ thống và UART hiện cùng 50 MHz, oversampling x16:

```text
baud_thực = 50.000.000 / (16 × divider)
```

`baud_rate_gen` nhận divider động 16 bit, 1..65535, tạo clock-enable tick; không
sinh một clock mới cho CPU/TX/RX. Ghi SHADOW không làm đổi tick. Giá trị 0 ở
đầu vào generator tự dừng tick để phòng lỗi tích hợp; register_file không cho
APPLY 0. Parameter BAUDRATE ở wrapper vẫn chọn mặc định sau reset, dùng phép
chia nguyên như bản trước; không giới hạn các baud có thể ghi lúc chạy.

Driver `dti_baud_divider()` làm tròn divider gần nhất, dùng tính toán 64 bit,
kiểm tra dải và từ chối sai số lớn hơn 2%. `actual` trả số baud thực làm tròn
để hiển thị, không phải sửa đổi baud đặt trên PC.

| Baud yêu cầu | Divider | Baud thực xấp xỉ | Driver |
|---:|---:|---:|---|
| 2400 | 1302 | 2400,154 | Cho phép |
| 4800 | 651 | 4800,307 | Cho phép |
| 9600 | 326 | 9585,890 | Cho phép |
| 19200 | 163 | 19171,779 | Cho phép |
| 38400 | 81 | 38580,247 | Cho phép |
| 57600 | 54 | 57870,370 | Cho phép |
| 76800 | 41 | 76219,512 | Cho phép |
| 115200 | 27 | 115740,741 | Cho phép |
| 230400 | 14 | 223214,286 | Từ chối, sai số khoảng −3,12% |

Giới hạn 2% là chính sách driver, không phải bảo đảm mọi cặp thiết bị và độ dài
frame đều làm việc ở tổng sai số đó. Phần cứng vẫn có thể dùng các divider
khác bằng truy cập thanh ghi. Kiểm thử 230400 cố định trong regression cũ vẫn
được giữ với divider mặc định cũ; nó không có nghĩa API runtime chấp nhận 230400.
Baud cao hợp lệ về divider cũng không bảo đảm CPU/USB-UART theo kịp mọi luồng.

`dti_set_baud()` là API polling có timeout, hợp với cấu hình khi kênh đã yên.
Chat dùng APPLY không chờ trong critical section để ISR không bị khóa lâu.
Timeout mỗi lô chat được tăng theo baud thấp: tối thiểu 100 ms, cộng biên cho
16 byte 8N1. Các ứng dụng scope/self-test giữ polling và baud mặc định.

## Ngắt và phân chia ISR / main

```text
UART register_file → irq → uart_avalon interrupt sender
                  → cpu.platform_irq_rx, IRQ số 1
                  → HAL → uart_irq_handler()
```

IRQ số 0 vẫn dành cho JTAG UART; console hiện tắt ngắt JTAG và dùng polling.
Không thêm chân IRQ ngoài board. Bridge Avalon–APB và APB slave không đổi FSM.
IRQ là đường báo riêng; ISR vẫn truy cập thanh ghi qua Avalon → APB.
BSP được regenerate và chứa UART_IRQ=1, UART_IRQ_INTERRUPT_CONTROLLER_ID=0.
Firmware đăng ký qua `alt_ic_isr_register()`; không sửa tay system.h và không
âm thầm fallback polling khi BSP thiếu IRQ.

```text
irq = reset_n AND OR(INT_ENABLE AND INT_STATUS)
```

IRQ active-high theo mức. RX không rỗng giữ mức đến khi được pop hoặc mask.
TX_DONE giữ mức khi TX đã rỗng cả FIFO lẫn active, nên mặc định ngắt TX tắt.
Main enqueue xong mới arm TX_DONE; ISR ghi nhận rồi mask nguồn TX, tránh ngắt
liên tục khi idle. Điều kiện theo mức giữ được thông báo dù TX kết thúc trước
khi main kịp arm. Lỗi RX overrun được lưu trong phần mềm trước khi W1C phần cứng.

`uart_irq.c` có ring 512 entry, dung lượng sử dụng 511; mỗi entry gồm byte và
bit parity. ISR là nơi duy nhất pop RX phần cứng, lấy tối đa 16 byte mỗi lần.
Nếu FIFO còn dữ liệu, IRQ tiếp tục có hiệu lực. Main đọc ring, không tranh đọc
RX với ISR; chỉ main enqueue TX. ISR không in JTAG, xử lý dòng hoặc đợi frame.
Các thao tác dùng chung có critical section ngắn lưu/khôi phục trạng thái IRQ.

Parity làm loại dòng đến Enter như trước. Tràn FIFO phần cứng hoặc ring ISR
đặt lỗi fatal, mask IRQ UART; main bật LED lỗi và yêu cầu reset. Sau fatal,
console_poll vẫn cố xuất thông báo JTAG nhưng chat ngừng xử lý. Dữ liệu/byte TX
đã được phần cứng nhận trước fatal không bị cưỡng bức hủy hoặc tự gửi lại.

## Kiểm thử có thể chạy lại

```bash
bash UART/firmware/test_driver.sh
bash UART/sim/run_tests.sh
bash UART/sim/run_soc_tests.sh
bash UART/sim/run_firmware_cosim.sh
bash UART/sim/run_firmware_echo_cosim.sh
bash UART/sim/run_niosv_firmware.sh --compile-only
```

- `test_driver`: tham số baud, làm tròn, sai số, dải, busy/rejected và timeout/wrap.
- `test_irq`: ISR thật trong model host, parity, budget 16, wrap/overflow ring,
  TX_DONE mask, overrun phần cứng và lỗi đăng ký ISR.
- `test_demo`: chat cũ, lệnh baud hợp lệ/không hợp lệ, busy và dòng RX chưa xong.
- `tb_baud_dynamic`: tick ở divider 1/2/65535, reload, đổi divider, fail-closed 0.
- `tb_baud_irq`: serial thực trong RTL ở nhiều divider, busy CTS/RX, start edge
  trùng giao dịch APPLY, byte strobe, mask IRQ, parity/overrun và reset.
- C driver + RTL: 768 frame, gồm các lần đổi baud bằng API C thực sự.
- C chat + RTL: 538 byte output, IRQ lấy từ RTL và ISR C được host mô hình gọi;
  lệnh JTAG đổi 9600, trở lại 115200 và từ chối 230400.

Co-simulation C dùng mã native trên PC và mô hình phân phối ISR, không thực thi
ELF trên CPU Nios V. Compile-only kiểm tra model SoC và testbench bằng Questa,
không chứng minh CPU chạy ISR. Full CPU simulation cần quyền socket và hiện
bị môi trường công cụ chặn; chạy ở terminal thường nếu muốn kiểm tra:

```bash
bash UART/sim/run_niosv_firmware.sh
```

Trên kit, sau khi compile license hợp lệ và nạp đúng SOF/ELF, thử hai terminal,
đổi baud theo quy trình trên và đo bit bằng oscilloscope. Có thể đóng picocom
rồi kiểm tra serial tự động ở baud hiện tại (giữ JTAG kết nối để console thoát):

```bash
python3 UART/firmware/serial_echo_test.py /dev/ttyUSB0 --baud 9600 --count 1024
```

Chưa nạp/đo bản baud+IRQ trên kit trong lần triển khai này. Kết quả mô phỏng,
cross-compile và timing không thay thế bước xác nhận vật lý.

## Dọn code sau triển khai

Đã bỏ ba parameter không dùng trong baud_rate_gen; module này chỉ nhận
clk/rst_n/divider_i/reload_i. Giữ CLK_FREQ và BAUDRATE trong wrapper để chọn
baud reset. Bỏ rx_pending_o cũ; RTS vẫn dựa trên FIFO full. Firmware bỏ hàm
console_echo log hex cũ, gộp helper gửi một byte vào console_text và chỉ giữ
uart_irq_stop ở phạm vi nội bộ ISR. Không thay đổi register map hoặc thuật toán
baud/IRQ; polling API vẫn cần cho scope/self-test. Xem đầu VALIDATION.md cho
kết quả kiểm tra sau dọn code.

## Giao diện output generator

Generator hiện xuất hai cổng `tick_tx` và `tick_rx`; dti_uart nối tương ứng
trực tiếp đến TX core và RX core. Không còn cổng `baud_tick` chung ở giao diện.
Hai cổng dùng cùng divider và pha (`assign tick_rx = tick_tx`), nên vẫn chỉ cần
một counter và một flip-flop tick. Bộ đếm RX idle dùng tick_rx. Chưa có divider
hoặc yêu cầu reload riêng cho từng chiều; điều kiện APPLY vẫn kiểm tra cả TX/RX.
