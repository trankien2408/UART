# FIFO TX/RX — bản mở rộng ngày 15/10/2026

## Luồng dữ liệu

```text
CPU → TX staging → ghi START → TX FIFO 16 byte → active byte → TX core → chân TX
chân RX → RX core → RX FIFO 16 byte + parity từng byte → CPU đọc RX
```

`rtl/uart_fifo.v` là FIFO đồng bộ một clock, được dùng hai lần trong
`rtl/register_file.v`. Không đổi chân ngoài, baud, APB state machine hay cách nối
ESP32. Clock CPU/bus/UART dùng cùng miền clock như trước.

TX có tối đa 16 byte chờ cộng 1 byte active (đang phát hoặc chờ CTS).
RX chứa 16 byte, khoảng 1,38 ms dữ liệu 8N1 liên tục ở baud thực hiện tại.
FIFO giúp chịu các khoảng CPU bận ngắn; không thể bù một CPU không đọc dữ liệu
trong thời gian vô hạn. Chat dùng TX/RX/GND, chưa dùng flow control ngoài.

## Thanh ghi và driver

Giữ các offset `TX=0x00`, `CFG=0x04`, `CTRL=0x08`, `STATUS=0x0C`, `RX=0x10`.
Ghi TX cập nhật staging, ghi START enqueue bản sao byte đó. Chỉ đọc RX thành
công mới pop. STATUS bit 0 báo **toàn bộ TX đã phát hết**, bit 1 báo RX còn byte,
bit 2 là parity của byte đầu RX FIFO.

Thêm `FIFO_STATUS=0x14`:

| Bit | Ý nghĩa |
|---|---|
| 0 | TX FIFO đầy |
| 1 | TX FIFO rỗng, không tính byte active |
| 2 | RX FIFO đầy |
| 3 | RX FIFO rỗng |
| 4 | RX overrun, sticky; ghi 1 để xóa |
| 15:8 | Số byte chờ trong TX FIFO, 0–16 |
| 23:16 | Số byte trong RX FIFO, 0–16 |
| Các bit còn lại | Đọc 0, ghi bỏ qua |

Ghi START khi đầy hoặc đọc RX khi rỗng sẽ giữ bus chờ. Driver kiểm tra trạng
thái trước khi truy cập. Ghi CFG phải đợi TX phát hết để tránh đổi format của
các byte đã queue. Chỉ đổi format khi phía gửi RX cũng idle.

- `dti_try_queue()`: enqueue một byte nếu còn chỗ, trả `DTI_AGAIN` khi đầy.
  `DTI_OK` chỉ có nghĩa đã enqueue; dùng `dti_wait_tx()` để đợi phát xong.
- `dti_send()` và `dti_try_send()` giữ hành vi gửi từng byte cũ.
- `dti_fifo_status()` đọc trạng thái; `dti_clear_overrun()` xóa cờ tràn.
  Xóa cờ không khôi phục byte đã mất hoặc xóa dữ liệu còn trong FIFO.
- Driver dành cho một task sở hữu UART; không để ISR/task khác enqueue xen kẽ.

Chat nạp từng đợt tối đa 16 byte, timeout 100 ms tính cho mỗi đợt. Bộ đệm dòng
120 byte, Enter để gửi, chuẩn hóa CRLF và local echo giữ nguyên. Khi RX tràn,
byte mới bị bỏ, byte cũ giữ nguyên; chat bật LED lỗi và báo lỗi qua JTAG, yêu cầu
reset. Không tự tiếp tục với một dòng có thể đã mất ký tự hoặc dấu Enter.

## Cập nhật kit

Bản firmware chat mới đọc 0x14 nên **phải nạp SOF mới trước khi chạy ELF mới**.
Từ `/home/kien/Documents/uart`, nếu bắt đầu lại từ source:

```bash
bash UART/fpga/build.sh all
bash UART/firmware/build.sh all echo
bash UART/fpga/program.sh 1 1 echo
```

Trong lần triển khai này đã generate hệ thống, compile FPGA và build ELF.
Compile đạt timing, nhưng môi trường công cụ bị chặn NIC ID nên kiểm tra
license Nios V không qua. Trên terminal thường của bạn chạy lại:

```bash
cd /home/kien/Documents/uart
bash UART/fpga/build.sh compile
# Chỉ nạp khi compile PASS, không còn REVIEW REQUIRED về license:
bash UART/fpga/program.sh 1 1 echo
```

Không bỏ kiểm tra license và không dùng SOF bị đánh dấu simulation-only.
Chỉ số cable/device ở trên theo cấu hình đang dùng; nếu JTAG thay đổi thì kiểm
tra lại bằng jtagconfig như hướng dẫn chính của project.

Mở hai terminal như trước:

```bash
# Terminal 1
bash UART/firmware/terminal_jtag.sh
```

```bash
# Terminal 2 — thay cổng theo máy thực tế
bash UART/firmware/terminal_uart.sh /dev/ttyUSB0
```

Thử gõ ở hai chiều: ký tự hiện tại bên nhập, bên kia chỉ nhận sau Enter;
thử nhiều dòng liên tiếp, backspace, dòng đủ 120 byte và reset. Đóng picocom
trước khi chạy bài kiểm tra serial tự động:

```bash
python3 UART/firmware/serial_echo_test.py /dev/ttyUSB0 --count 1024
```

## Kiểm thử

```bash
bash UART/sim/run_tests.sh
bash UART/sim/run_soc_tests.sh
bash UART/firmware/test_driver.sh
bash UART/sim/run_firmware_cosim.sh
bash UART/sim/run_firmware_echo_cosim.sh
```

Các bài trên đã PASS: FIFO ngẫu nhiên ở depth 1/3/16; đầy/rỗng, wrap, reset,
push/pop đồng thời; TX chờ CTS và full backpressure; RX giữ đúng thứ tự/parity,
tràn và W1C; các định dạng và baud cũ; firmware chat chạy cùng UART RTL.
Chi tiết kết quả và giới hạn xác nhận xem `../firmware/VALIDATION.md`.
