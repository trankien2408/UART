# Firmware UART trên DE2-115

Bản 16/10/2026: chat đã dùng **ISR UART + baud lập trình được**. Xem
[BAUD_INTERRUPT.md](../docs/BAUD_INTERRUPT.md) để đổi baud qua `:baud 9600`,
hiểu các thanh ghi 0x18–0x28 và cập nhật SOF/BSP/ELF tương ứng.

Ứng dụng mặc định (`echo` trong lệnh build/nạp) là **chat hai chiều theo dòng**
giữa JTAG UART và UART vật lý qua USB-UART trên ESP32.

Bổ sung 17/10: lỗi RX framing/break được báo ngay trên JTAG; terminal UART vẫn
dùng picocom, có lớp hiển thị lỗi driver và byte không in được. Xem
[UART_ERROR_DISPLAY.md](../docs/UART_ERROR_DISPLAY.md). Cần SOF + ELF mới.

## 1. Hai terminal làm gì?

- **Terminal 1 — juart-terminal:** gõ dòng, nhấn Enter để gửi qua UART ra terminal 2.
- **Terminal 2 — picocom:** gõ dòng, nhấn Enter để chuyển qua FPGA sang terminal 1.
- Ký tự đang nhập được firmware echo về đúng terminal người gõ; terminal kia
  chỉ nhận sau Enter. Picocom phải tắt local echo để không bị lặp ký tự.
- CR, LF hoặc CR+LF đều được nhận là một Enter; đầu ra luôn CR+LF đúng một lần.
- Backspace/DEL xóa byte cuối dòng đang nhập (phù hợp ASCII; chưa có editor Unicode).
- Picocom vẫn gửi từng phím qua dây để CPU xử lý và echo tại chỗ. Điều kiện
  Enter áp dụng cho việc chuyển nội dung sang terminal đối diện.
- Không gửi log hex RX/TX cho từng ký tự; READY và thông báo lỗi xuất qua JTAG.

## 2. Nên đọc code theo thứ tự nào?

1. **`main.c`:** `uart_demo_init()` cấu hình một lần; `uart_demo_poll()` kiểm tra
   thông báo TX hoàn tất → lấy RX từ ring ISR → nạp tối đa 16 byte vào TX FIFO. `main()` gọi lặp lại hàm poll.
2. **`uart_irq.c/.h`:** ISR UART, ring RX 511 byte dùng được và thông báo TX hoàn tất.
3. **`dti_uart.h` và `dti_uart.c`:** địa chỉ thanh ghi và các thao tác gửi/nhận.
4. **`console.c`:** đọc phím JTAG và xuất dữ liệu qua hàng đợi không chặn.
5. **`uart_platform.h`:** đọc/ghi MMIO và đọc bộ đếm chu kỳ CPU. Nhánh
   `UART_HOST_TEST` chỉ phục vụ kiểm thử trên PC.

`tests/` chứa kiểm thử riêng. `build/bsp/` là mã nền do công cụ Nios V sinh;
không cần sửa các file này để thay đổi nội dung demo. Không dùng `printf()`
trong demo: BSP giữ STDIN/STDOUT/STDERR là `none`, console truy cập JTAG trực tiếp.

## 3. Cấu hình và thanh ghi

Demo dùng **115200 baud, 8 data bits, no parity, 1 stop bit (8N1)**.
Baud mặc định sau reset là 115200; có thể đổi qua SHADOW/APPLY. CFG chỉ đổi định dạng frame.
Địa chỉ nền lấy từ `UART_BASE` trong `build/bsp/system.h`, hiện là `0x21000`.

| Offset theo byte | Thanh ghi | Cách dùng |
|---|---|---|
| `0x00` | TX | Ghi byte cần gửi |
| `0x04` | CFG | `0x03` chọn 8N1 |
| `0x08` | CTRL | Ghi bit START = 1 một lần |
| `0x0C` | STATUS | Bit 0 TX_DONE, bit 1 RX_DONE, bit 2 PARITY_ERROR |
| `0x10` | RX | Pop một byte; status chuyển sang byte tiếp theo |
| `0x14` | FIFO_STATUS | Full/empty TX/RX, overrun và số byte trong FIFO |
| `0x18 / 0x1C` | BAUD_SHADOW / ACTIVE | Divider dự kiến / đang chạy |
| `0x20` | BAUD_CONTROL_STATUS | APPLY, BUSY, REJECTED, DIRTY |
| `0x24 / 0x28` | INT_ENABLE / STATUS | Enable và nguồn ngắt RX/TX/overrun/framing |

Driver luôn kiểm tra RX_DONE trước khi đọc RX, vì đọc RX rỗng sẽ giữ giao dịch
APB chờ. `dti_try_queue()` kiểm tra TX_FULL rồi ghi TX/START để enqueue.
Chat nạp tối đa 16 byte mỗi đợt và chờ TX_DONE để xác nhận cả đợt hoàn tất.
`dti_send()`/`dti_try_send()` giữ cách gửi từng byte cũ cho scope và self-test.

## 4. Bộ đệm và xử lý lỗi

- Hai bộ đệm nhập độc lập, mỗi dòng tối đa 120 byte chưa tính CR/LF.
- Hàng đợi TX UART và JTAG đều 512 byte; chuyển một dòng sang đầu ra theo
  nguyên tắc đủ chỗ cho cả dòng hoặc bỏ cả dòng, không chuyển nửa dòng.
- Dòng quá dài hoặc RX parity lỗi: bỏ dòng đang nhập đến Enter, bật LED lỗi;
  dòng tiếp theo vẫn được nhận. Không gửi tiền tố của dòng lỗi sang bên kia.
- Hàng đợi đầy: báo lỗi, giữ dữ liệu đã có; không cam kết truyền vô hạn khi
  terminal đích không đọc. Terminal JTAG bị chặn không làm CPU ngừng phục vụ UART.
- Mỗi poll xuất tối đa 16 byte JTAG. TX có timeout tối thiểu 100 ms, tăng theo
  thời gian phát 16 byte khi baud thấp; lỗi timeout dừng chat, yêu cầu reset.
- LEDG[0] sáng khi khởi tạo thành công; LEDG[1] giữ sáng sau lỗi đến khi reset.
- Thiết kế dành cho nhập văn bản từng dòng. Nếu hai người cùng gõ và nhận
  trong lúc dòng cục bộ chưa xong, không có cơ chế vẽ lại dòng như ứng dụng chat GUI.
- FIFO phần cứng: TX 16 byte chờ + một byte active; RX 16 byte kèm parity.
  Tràn RX bật LED lỗi, báo `RX FIFO overrun; reset required` và dừng ứng dụng.
  Demo không dùng CTS, chỉ cần TX/RX/GND; FIFO hữu hạn không bảo đảm nhận vô hạn
  nếu CPU không đọc kịp.

## 5. Build và kiểm thử khi chưa có kit

Chạy từ `/home/kien/Documents/uart`:

```bash
# Tạo BSP và biên dịch ứng dụng mặc định bằng RISC-V GCC
bash UART/firmware/build.sh all echo

# Kiểm thử C trên máy tính
bash UART/firmware/test_driver.sh

# Driver C + RTL: 768 frame, gồm đổi baud 9600/57600/115200
bash UART/sim/run_firmware_cosim.sh

# Ứng dụng C + RTL: dòng văn bản, chuẩn hóa LF thành CRLF, burst, JTAG mô hình
bash UART/sim/run_firmware_echo_cosim.sh

# Build chương trình self-test độc lập; không thay thế ELF demo
bash UART/firmware/build.sh all selftest
```

Sau khi chỉ sửa C, dùng `bash UART/firmware/build.sh compile echo` để build lại.
Sau khi thay đổi hệ thống phần cứng/BSP hoặc danh sách source, dùng `all echo`.

Sản phẩm:

- Demo: `build/app/build/uart_firmware.elf` và `ram.hex` cùng thư mục.
- Self-test: `build/selftest/build/uart_selftest.elf` và `ram.hex` cùng thư mục.
- Log build: `build/logs/`; log kiểm thử C: `build/tests/`.
- Self-test bật loopback nội bộ, thử 192 frame rồi dừng ở kết quả PASS/FAIL;
  không chuyển sang echo và không phát mẫu thử ra chân TX ngoài.

Hai bài C + RTL chạy mã C native trên PC, mô phỏng UART bằng Icarus;
bài chat dùng IRQ RTL và mô hình host phân phối ISR C; chúng
**không thực thi ELF trên CPU Nios V**. Muốn mô phỏng CPU thật dùng:

```bash
bash UART/sim/run_niosv_firmware.sh
```

Chạy lệnh này trực tiếp trong terminal VS Code/Linux của bạn. Questa cần quyền
tạo socket TCP cục bộ; môi trường chạy lệnh bị giới hạn có thể báo
`couldn't open socket: not owner` dù không có vấn đề trong RTL. Script kiểm tra
quyền này trước khi compile. Mô phỏng không cần board; xem chẩn đoán trong
`VALIDATION.md` nếu script báo BLOCKED.

Script hiện các dòng `UART_SIM:` ngay trên terminal: compile → nạp mô hình →
chạy CPU → tiến độ UART. Mỗi 1 ms thời gian mô phỏng có thông tin bus/LED;
5 ms chưa thấy READY thì báo boot watchdog. Các thời gian này là thời gian
trong mô phỏng, không phải thời gian chờ thực tế. Log đầy đủ vẫn nằm trong
`../sim/results/niosv_firmware/console.log`. `--compile-only` dùng thư mục log
riêng `niosv_firmware_compile`, không ghi đè log đang chạy CPU.

Tình trạng bản FIFO xem [VALIDATION.md](VALIDATION.md). Bản FIFO mới cần nạp
và kiểm thử lại trên kit; kết quả bản trước không thay thế bước này.

## Đo UART TX bằng oscilloscope: gửi hello liên tục

Chương trình riêng: `examples/scope_main.c`. Cấu hình 8N1, baud 115200 của
RTL hiện tại; gửi chuỗi ASCII `hello` (5 byte: `68 65 6C 6C 6F`), chờ khoảng
100 ms sau khi TX hoàn tất cả chuỗi rồi lặp lại. Không gửi byte NUL kết thúc
chuỗi hay CR/LF. Sửa `DELAY_MS` để đổi khoảng nghỉ.
Delay dùng timer mtime, không dùng CSR mcycle. LEDG[0] sáng khi sẵn sàng;
LEDG[1] sáng và chương trình dừng nếu lỗi khởi tạo hoặc timeout TX.

Build:

```bash
bash UART/firmware/build.sh all scope
```

Cách nạp đầy đủ, dùng cả khi kit vừa bật nguồn (nạp SOF rồi ELF scope):

```bash
cd /home/kien/Documents/uart
bash UART/fpga/program.sh 1 1 scope
```

Nếu kit vẫn đang chứa đúng thiết kế FPGA đang chạy được, có thể chỉ nạp ELF mới:

```bash
cd /home/kien/Documents/uart
source UART/fpga/scripts/env.sh
niosv-download -c 1 -d 0 -r -g UART/firmware/build/scope/build/uart_scope.elf
```

Nếu lệnh tải ELF báo `Please specify a device with Nios V instance(s)`,
chạy lệnh nạp đầy đủ `program.sh 1 1 scope` ở trên và kiểm tra log JTAG sau nạp.
Tải ELF không tự cấu hình CPU trong FPGA. Script lưu log tại
`../fpga/build/logs/program.*`, đường dẫn lượt mới nhất nằm trong
`../fpga/build/logs/latest_program_directory.txt`.
Nếu FPGA đã chứa bản FIFO mới thì không cần compile lại khi chỉ sửa chuỗi C. Firmware scope không in log JTAG và không echo RX.
Picocom sẽ nhận `hellohello...` nếu đường TX tới USB-UART đã được nối.

Đầu dò oscilloscope nối GPIO[0] (UART_TX / pin FPGA AB22), dây mass nối GND
DE2-115. Chọn trigger cạnh xuống ở khoảng 1.5 V, khoảng 10 us/div để xem frame.
Muốn xem cả chuỗi, chọn khoảng 100 us/div. Mỗi chuỗi có 5 frame UART;
idle ở mức cao, mỗi frame có start=0, 8 bit dữ liệu LSB trước và stop=1.
Bit danh định khoảng 8.68 us; bộ chia nguyên RTL hiện tại cho khoảng 8.64 us.
Khoảng cách giữa hai chuỗi gồm thời gian phát và khoảng nghỉ 100 ms cùng
overhead phần mềm, không phải bộ phát chu kỳ chính xác tuyệt đối 100 ms.

Trở lại demo echo bằng cách nạp `build/app/build/uart_firmware.elf` thay cho
ELF scope. Bản echo vẫn được giữ riêng.

## 6. Mở hai terminal khi đã có kit và đã nạp demo

Terminal 1 — nhập/nhận dòng JTAG:

```bash
cd /home/kien/Documents/uart
bash UART/firmware/terminal_jtag.sh
```

Terminal 2 — UART qua ESP32 bằng picocom. Cài một lần trên Ubuntu:

```bash
sudo apt install picocom
```

Sau đó mở cổng:

```bash
cd /home/kien/Documents/uart
python3 -m serial.tools.list_ports
bash UART/firmware/terminal_uart.sh /dev/ttyUSB0
```

Thay `/dev/ttyUSB0` bằng cổng thực tế. Script đặt 115200 8N1, tắt local echo và
flow control; Enter gửi CR+LF. Gõ `Hello` để xem phản hồi; dùng ASCII trước để
dễ đối chiếu log hex. Thoát picocom bằng **Ctrl+A rồi Ctrl+X**, terminal JTAG bằng
**Ctrl+C**. Chỉ một chương trình mở cổng serial tại một thời điểm.

Script hạ DTR/RTS khi mở cổng và dùng `--omap crcrlf` để Enter gửi CR+LF;
không bật `--echo` để tránh nhầm ký tự tự hiển thị với phản hồi từ FPGA.
Các tùy chọn và phím thoát theo [hướng dẫn picocom](https://github.com/npat-efault/picocom/blob/master/picocom.1.md).
Python/pyserial vẫn dùng cho lệnh liệt kê cổng và bài kiểm thử tự động bên dưới.

ESP32 phải được giữ ở trạng thái không điều khiển đường UART (thường giữ EN
ở mức thấp). Trước khi đấu dây cần đối chiếu đúng model board: nhãn TX/RX trên
ESP32 thường đặt theo CPU ESP32, không phải theo chip USB-UART. Chưa có kit nên
chưa chốt hay kiểm chứng sơ đồ dây cho board thực tế.

Kiểm thử tự động sau khi đóng terminal UART (có thể giữ terminal JTAG mở):

```bash
python3 UART/firmware/serial_echo_test.py /dev/ttyUSB0 --count 1024
```

Lệnh nạp kit là bước sau. Script `UART/fpga/program.sh` chỉ nạp khi bản build
FPGA vượt kiểm tra license/timing và manifest hợp lệ; build firmware thành
công không tự xác nhận các điều kiện phần cứng này.
