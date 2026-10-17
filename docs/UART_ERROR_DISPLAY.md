# Hiển thị lỗi UART khi hai phía khác baud

Phiên bản 17/10/2026. Terminal 1 là JTAG; terminal 2 vẫn dùng giao diện picocom,
được bọc bởi `firmware/serial_diagnostics.py` để hiển thị lỗi bộ thu và byte không
in được. Đổi baud riêng từng bên vẫn dùng `:baud N` và Ctrl+A → Ctrl+B → N → Enter.

## Phạm vi phát hiện

Sai baud có thể tạo frame sai stop bit, byte điều khiển không nhìn thấy, hoặc
một byte ASCII trông hoàn toàn hợp lệ. Với giao tiếp 8N1 không có CRC/chuỗi tham
chiếu, không thể xác định mọi byte sai hay vị trí/số lượng bit lỗi. Ký hiệu ở
đây là chẩn đoán lỗi nhận hoặc biểu diễn byte đã nhận, không phải số đo BER.
Nếu chip/driver USB-UART loại bỏ dữ liệu mà không báo lỗi, phần mềm PC cũng
không thể tạo thông báo dựa trên một sự kiện không quan sát được.

## Terminal 1: FPGA RX nhận từ ESP32

Trước đây `frame_error_o` của RX core không nối lên thanh ghi. Frame có stop
không hợp lệ bị bỏ, không có RX_DONE và không có Enter để firmware hoàn tất dòng.

Hiện tại đường lỗi là:

```text
RX frame_error_o → FIFO_STATUS[5] (sticky) → INT_STATUS[3]
→ irq → ISR lưu sự kiện và W1C cờ phần cứng
→ main in thông báo ngay trên JTAG, không chờ Enter
```

Ví dụ thông báo:

```text
[UART RX ERROR: FRAME/BREAK; check baud]
[UART RX ERROR: PARITY; line discarded until Enter]
[UART RX NON-TEXT 0x00; check baud]
```

NON-TEXT chỉ báo một byte không thuộc văn bản ASCII của ứng dụng, không khẳng
định phần cứng đã phát hiện lỗi. Các byte điều khiển không được đưa nguyên xi
lên terminal JTAG. Nhiều sự kiện lỗi của một dòng được gộp để tránh tràn console.
Dòng hỏng bị bỏ đến Enter. Sau khi khớp lại baud, nhấn Enter một lần rồi nhập
một dòng mới. Lệnh JTAG `:baud N` vẫn dùng được khi dòng hỏng đã mất ký tự Enter.
Lỗi framing là lỗi có thể phục hồi; RX overrun vẫn là lỗi nghiêm trọng cần reset.

Các bit mở rộng, không thay đổi offset và không thay đổi dung lượng FIFO:

| Thanh ghi | Bit | Ý nghĩa |
|---|---:|---|
| FIFO_STATUS, 0x14 | 5 | RX_FRAME_ERROR sticky; ghi 1 để xóa |
| INT_ENABLE, 0x24 | 3 | Cho phép ngắt RX framing/break |
| INT_STATUS, 0x28 | 3 | Trạng thái framing/break chưa được xóa |

Lỗi mới thắng nếu đồng thời xuất hiện với thao tác W1C. Frame lỗi vẫn không
được đưa vào RX FIFO. Khởi tạo chat bật ngắt RX, overrun và framing: mask 0x0D;
TX_DONE chỉ được bật trong lúc cần theo dõi hoàn tất truyền.

## Terminal 2: USB-UART RX nhận từ FPGA

Giữ nguyên lệnh mở:

```bash
bash UART/firmware/terminal_uart.sh /dev/ttyUSB0 115200
```

Luồng PC:

```text
Cổng USB-UART thật → PARMRK parser / hiển thị → PTY → picocom → màn hình
Phím từ picocom → PTY → cổng USB-UART thật → FPGA
```

Lớp Python giữ quyền sở hữu cổng serial thật. Nó chuyển mọi byte phím nguyên
vẹn từ picocom, chỉ định dạng dữ liệu nhận để hiển thị. Các chuỗi `[UART ...]`
được tạo cục bộ trên PC, không gửi ngược xuống FPGA. Picocom vẫn tắt local echo,
Enter vẫn gửi CR+LF, và Ctrl+A → Ctrl+X vẫn thoát.

Baud và định dạng picocom đặt trên PTY được chuyển sang cổng thật. Đã kiểm tra
thao tác Ctrl+A → Ctrl+B với 9600, 62500 và 115200 trên liên kết PTY.

Ví dụ đầu ra:

```text
[UART RX ERROR: FRAME/PARITY; byte=0xA6]
[UART RX ERROR: BREAK/FRAME/PARITY]
[UART RX ERROR: FRAME; events=+1]
[0x00][0x1B][0xFF]
```

- PARMRK đưa lỗi mà driver cung cấp thành marker; parser hỗ trợ marker bị chia
  giữa các lần đọc. Byte FF hợp lệ được phân biệt với tiền tố lỗi.
- Nếu driver hỗ trợ TIOCGICOUNT, thay đổi các bộ đếm framing/parity/break/overrun
  cũng được báo. Bộ đếm không được hỗ trợ thì bỏ qua, không giả lập số lỗi.
- `[0xNN]` là cách hiển thị byte không in được. Nó không tự chứng minh byte sai.
- Byte ASCII có vẻ hợp lệ vẫn hiện như văn bản; không tự suy ra nó là lỗi bit.

Để dùng giao diện picocom trực tiếp như trước, không qua bộ hiển thị:

```bash
UART_TERMINAL_PLAIN=1 bash UART/firmware/terminal_uart.sh /dev/ttyUSB0 115200
```

Phụ thuộc trên PC: `picocom`, Python 3 và `pyserial` (`python3-serial` trên Ubuntu).
Cơ chế đánh dấu lỗi dựa trên [Linux termios/PARMRK](https://man7.org/linux/man-pages/man3/termios.3.html).

## Build và kiểm tra

Bắt buộc dùng **SOF mới và ELF chat mới**, vì có thêm cờ framing trong RTL và ISR.
Generate lại hệ thống hiện có để bản RTL được copy vào Qsys khớp source:

```bash
cd /home/kien/Documents/uart
source UART/fpga/scripts/env.sh
cd UART/fpga
qsys-generate uart_soc.qsys --synthesis=VERILOG --simulation=VERILOG \
  --output-directory=build/uart_soc '--search-path=ip/**/*,$'
cd ../..
bash UART/fpga/build.sh compile
bash UART/firmware/build.sh compile echo
# Khi compile và kiểm tra license đạt, nạp trên kit:
bash UART/fpga/program.sh 1 1 echo
```

Không dùng bước `qsys-script create_system.tcl` ở đây để giữ cấu hình Qsys đang có.
Nếu build trong phiên công cụ báo Simulation-Only của Nios V thì phải compile
lại trong terminal người dùng và đạt HARDWARE_BUILD_READY trước khi nạp.

Kiểm thử tự động:

```bash
bash UART/firmware/test_driver.sh
bash UART/sim/run_tests.sh --simulator iverilog
bash UART/sim/run_soc_tests.sh
bash UART/sim/run_firmware_echo_cosim.sh
bash UART/sim/run_niosv_firmware.sh --compile-only
```

Các kiểm thử gồm W1C/mask/reset của cờ mới; hai chiều sai baud trong mô hình
UART; C ISR/main thật báo framing lên JTAG khi không có Enter rồi phục hồi bằng
lệnh baud; parser PARMRK và relay thực qua picocom/PTY. PTY và mô phỏng RTL không
thay thế việc xác nhận tín hiệu lỗi do chip USB-UART và driver của kit thực cung cấp.

## Kết quả xác nhận của lần triển khai

| Kiểm tra | Kết quả |
|---|---|
| Driver / ISR / ứng dụng C trên host | PASS, gồm sự kiện framing không có RX byte, gộp lỗi, W1C, phục hồi baud khi mất Enter, hiện NUL/ESC |
| Terminal diagnostic | 5/5 PASS; parser marker chia nhỏ, FF hợp lệ, picocom/PTY hai chiều, đổi 9600 → 62500 → 115200 |
| RTL regression | 16/16 PASS, gồm test lỗi RX mới 48 checks |
| Bridge + UART Avalon | 2/2 PASS |
| C + RTL chat | PASS, 541 byte output; IRQ thật đưa lỗi framing lên JTAG không chờ Enter, sau đó phục hồi |
| Model SoC Nios V | Questa compile-only PASS; không chạy CPU trong phép kiểm này |
| Firmware RISC-V chat | Build ELF/HEX PASS; ELF text 23.928, data 1.848, bss 3.368 byte |
| Quartus sau generate lại RTL | Full compile PASS; constrained STA worst slack +0,136 ns |
| Điều kiện nạp kit | Chưa đạt trong phiên công cụ: Nios V Simulation-Only, không tạo HARDWARE_BUILD_READY |
| Board / chip USB-UART vật lý | Chưa kiểm tra trong lần triển khai này |

Log chính: `sim/results/iverilog/`, `sim/results/firmware_echo_cosim/run.log`,
`firmware/build/tests/serial_diagnostics.log`, `fpga/build/logs/compile.log`.
Bản copy UART trong Qsys synthesis/simulation đã được đối chiếu trùng source RTL
trước lần compile cuối. File SOF benchmark/Simulation-Only không được dùng để
bỏ qua kiểm tra license của `program.sh`.
