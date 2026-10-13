# Firmware UART trên DE2-115

Ứng dụng mặc định: **CPU nhận byte qua UART tự thiết kế, gửi lại đúng byte đó,
và ghi log qua JTAG**. Không cần firmware trên ESP32: chỉ dùng chip USB-UART
có sẵn trên board ESP32.

## 1. Hai terminal làm gì?

Mở hai terminal tích hợp trong VS Code:

```text
Terminal UART ⇄ USB-UART của ESP32 ⇄ UART RX/TX trên FPGA
                                          ⇅
                                  thanh ghi APB ⇄ Nios V
                                                     ↓
Terminal JTAG ← USB-Blaster ← JTAG UART ← log của firmware
```

- **Terminal UART:** bạn gõ `A`, CPU nhận `0x41` rồi gửi `0x41` trở lại; màn hình
  hiện `A`. Tắt local echo để không nhầm ký tự máy tính tự hiện với phản hồi FPGA.
- **Terminal JTAG:** hiện `RX=0x41 TX=0x41` sau khi UART phát xong byte.
- Terminal JTAG chỉ xem log, không nhận lệnh bàn phím và không chuyển chữ gõ
  sang terminal UART. Đây là demo echo + log, giống hướng triển khai tham khảo.
- Firmware không gửi lời chào ra UART để giữ đường dữ liệu sạch, kể cả khi thử
  byte `0x00`, `0xFF`, CR hoặc LF. Thông báo READY chỉ đi qua JTAG.

## 2. Nên đọc code theo thứ tự nào?

1. **`main.c`:** `uart_demo_init()` cấu hình một lần; `uart_demo_poll()` kiểm tra
   TX hoàn tất → nhận RX → phát byte đang chờ. `main()` gọi lặp lại hàm poll.
2. **`dti_uart.h` và `dti_uart.c`:** địa chỉ thanh ghi và các thao tác gửi/nhận.
3. **`console.c`:** xuất log JTAG mà không đứng chờ terminal.
4. **`uart_platform.h`:** đọc/ghi MMIO và đọc bộ đếm chu kỳ CPU. Nhánh
   `UART_HOST_TEST` chỉ phục vụ kiểm thử trên PC.

`tests/` chứa kiểm thử riêng. `build/bsp/` là mã nền do công cụ Nios V sinh;
không cần sửa các file này để thay đổi nội dung demo. Không dùng `printf()`
trong demo: BSP giữ STDIN/STDOUT/STDERR là `none`, console truy cập JTAG trực tiếp.

## 3. Cấu hình và thanh ghi

Demo dùng **115200 baud, 8 data bits, no parity, 1 stop bit (8N1)**.
Baud rate được chọn trong RTL; ghi CFG chỉ thay đổi định dạng frame.
Địa chỉ nền lấy từ `UART_BASE` trong `build/bsp/system.h`, hiện là `0x21000`.

| Offset theo byte | Thanh ghi | Cách dùng |
|---|---|---|
| `0x00` | TX | Ghi byte cần gửi |
| `0x04` | CFG | `0x03` chọn 8N1 |
| `0x08` | CTRL | Ghi bit START = 1 một lần |
| `0x0C` | STATUS | Bit 0 TX_DONE, bit 1 RX_DONE, bit 2 PARITY_ERROR |
| `0x10` | RX | Đọc byte và xóa RX_DONE/PARITY_ERROR |

Driver luôn kiểm tra RX_DONE trước khi đọc RX, vì đọc RX rỗng sẽ giữ giao dịch
APB chờ. Khi gửi, driver kiểm tra TX_DONE, ghi TX rồi ghi START; phần cứng tự
xóa START. Firmware chỉ báo TX thành công sau khi TX_DONE trở lại 1.

## 4. Bộ đệm, log và xử lý lỗi

- Hàng đợi echo chứa tối đa 256 byte, bao gồm byte đang phát. Các byte được
  giữ đúng thứ tự. Polling giúp CPU tiếp tục nhận trong khi TX đang phát.
- RX lỗi parity: đọc để giải phóng thanh ghi, bỏ byte lỗi, bật LED lỗi và tiếp
  tục phục vụ byte tiếp theo. Ca này được kiểm thử bằng mô hình; demo mặc định
  tắt parity nên muốn thử trên dây phải cấu hình cả hai phía cùng chế độ parity.
- Hàng đợi đầy: bỏ byte mới, giữ dữ liệu cũ, bật LED lỗi.
- TX chưa hoàn tất sau 100 ms: bật LED lỗi và dừng xử lý echo đến khi reset.
  Không tự phát lại vì byte cũ có thể vẫn đang nằm trong phần cứng.
- SYSID sai hoặc khởi tạo thất bại: dừng echo và bật LED lỗi.
- LEDG[0] báo khởi tạo thành công; LEDG[1] giữ sáng khi đã gặp lỗi, xóa khi reset.
- Mỗi vòng poll gửi tối đa 8 ký tự log. JTAG đầy/chưa được đọc thì quay lại
  phục vụ UART ngay. Nếu dòng log trước còn chờ, dòng log mới bị bỏ qua; log
  không phải bản ghi đầy đủ mọi byte/lỗi. LED lỗi vẫn hoạt động độc lập.

RX phần cứng chỉ giữ một byte chưa đọc. Hàng đợi phần mềm không thay thế được
FIFO phần cứng hoặc flow control: không cam kết nhận vô hạn khi bên kia gửi
nhanh hơn khả năng phục vụ. Demo bỏ qua CTS và chỉ cần TX/RX/GND; kiểm thử
chấp nhận trên kit dùng gửi một byte, chờ echo rồi mới gửi byte tiếp theo.

## 5. Build và kiểm thử khi chưa có kit

Chạy từ `/home/kien/Documents/uart`:

```bash
# Tạo BSP và biên dịch ứng dụng mặc định bằng RISC-V GCC
bash UART/firmware/build.sh all echo

# Kiểm thử C trên máy tính
bash UART/firmware/test_driver.sh

# Driver C + RTL: 24 định dạng × 8 mẫu = 192 frame
bash UART/sim/run_firmware_cosim.sh

# Ứng dụng echo C + RTL: dữ liệu trên dây RX/TX, có burst, JTAG bị chặn
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

Hai bài C + RTL chạy mã C native trên PC, mô phỏng UART bằng Icarus; chúng
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

Tình trạng hiện tại xem [VALIDATION.md](VALIDATION.md). Chưa có kit nên chưa
xác nhận đường USB-Blaster/USB-UART hoặc hoạt động vật lý trên board.

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
Không cần compile lại FPGA. Firmware scope không in log JTAG và không echo RX.
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

Terminal 1 — log JTAG:

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
