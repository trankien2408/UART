# Chuẩn bị Quartus và kit DE2-115

Project đã có sẵn: mở **de2_115_uart.qpf** trong Quartus. Không cần tạo project
mới hoặc nhập lại toàn bộ bảng chân của kit. PDF dùng để đối chiếu; các gán
chân thực tế được lưu trong `de2_115_uart.qsf`.

## Chuẩn bị trên máy tính khi chưa có kit

1. File → Open Project → chọn `UART/fpga/de2_115_uart.qpf`.
2. Kiểm tra FPGA **Cyclone IV E / EP4CE115F29C7**, top `de2_115_uart_top`.
3. Assignments → Pin Planner: đối chiếu bảng dưới. Nếu chưa hiện node, chạy
   Analysis & Elaboration rồi mở lại Pin Planner.
4. GPIO dùng 3.3-V LVTTL; KEY0 và LEDG dùng 2.5 V. Clock CLOCK_50 là 50 MHz,
   đã có ràng buộc chu kỳ 20 ns trong `de2_115_uart.sdc`.
5. Sau thay đổi cấu hình/RTL, compile lại để tạo `.sof` mới. Firmware C được
   build riêng thành `.elf`; xem `../firmware/README.md`.

| Tín hiệu top | Chân vật lý FPGA | Tên trong bảng DE2-115 | I/O Standard |
|---|---|---|---|
| CLOCK_50 | PIN_Y2 | CLOCK_50 | 3.3-V LVTTL |
| KEY0 | PIN_M23 | KEY[0] | 2.5 V |
| UART_TX | PIN_AB22 | GPIO[0] | 3.3-V LVTTL |
| UART_RX | PIN_AC15 | GPIO[1] | 3.3-V LVTTL |
| UART_CTS_N | PIN_AB21 | GPIO[2] | 3.3-V LVTTL |
| UART_RTS_N | PIN_Y17 | GPIO[3] | 3.3-V LVTTL |
| LEDG[0] | PIN_E21 | LEDG[0] | 2.5 V |
| LEDG[1] | PIN_E22 | LEDG[1] | 2.5 V |

Các chỉ số GPIO[0..3] là tên tín hiệu trên header, không phải số thứ tự chân
vật lý của đầu nối. Cần xem sơ đồ đầu nối trước khi cắm dây.

Nguồn đối chiếu: `../../DE2-115-Pin-Assignments.pdf` và
[Terasic DE2-115 User Manual](https://www.terasic.com.tw/attachment/archive/502/DE2_115_User_manual.pdf).
Ngày 12/10/2026 đã sửa KEY0 và LEDG từ 3.3 V sang 2.5 V theo bảng chân.
File `.sof` tạo trước thay đổi này phải được compile lại; không tự coi là đã cập nhật.

## Khi có kit

1. Kiểm tra cấu hình jumper với board tắt nguồn: GPIO **JP6 = 3.3 V**;
   **JP7 = 2.5 V** phù hợp cấu hình KEY0 hiện tại. Đối chiếu nhãn/manual của kit.
2. Cấp nguồn board, đặt RUN/PROG ở **RUN**, nối máy tính với cổng USB-Blaster.
3. Quartus → Tools → Programmer, chọn USB-Blaster trong Hardware Setup,
   chế độ JTAG. Driver/quyền truy cập USB trên máy phải cho phép nhận cable.
4. Nạp `.sof` đã compile và kiểm tra: file này tạo CPU Nios V, RAM, bus và UART
   trong FPGA. Pin mapping đã nằm trong `.sof`, không cần gán lại trên board.
5. Nạp firmware `.elf` vào RAM và cho CPU chạy qua công cụ Nios V.
   Script `program.sh` thực hiện cả bước nạp `.sof` và `.elf` khi đủ điều kiện.
   Với một kit ở cable 1 và FPGA đầu tiên, dùng `bash UART/fpga/program.sh 1 1`.
   Tham số thứ hai là vị trí Quartus bắt đầu từ 1; script tự đổi thành device 0
   cho Nios V/OpenOCD. Terminal tương ứng:
   `bash UART/firmware/terminal_jtag.sh -c 1 -d 0`.
   Có thể xem chỉ số debug thực tế bằng `openocd-cfg-gen --print` sau khi nạp
   FPGA. Không truyền nguyên vị trí Quartus 1 vào `niosv-download -d`.
6. Nối GPIO UART với chip USB-UART trên ESP32 và nối chung GND. Kết nối phải là
   FPGA TX → ngõ nhận của chip USB-UART, FPGA RX ← ngõ phát của chip USB-UART.
   Cần xác nhận model ESP32 vì nhãn TX/RX trên board thường đặt theo CPU ESP32.
   CPU ESP32 phải không điều khiển đường UART; cách thường dùng là giữ EN thấp.
7. Mở terminal JTAG để xem log và terminal serial 115200 8N1 để thử echo.
   Demo chỉ cần TX/RX/GND, không cần nối CTS/RTS.

Project dùng UART ở **header GPIO**. Các chân có tên UART_TXD/UART_RXD trong
bảng pin của kit thuộc đường UART RS-232 có sẵn, không phải các chân GPIO đang
được dùng ở đây. Không đấu tín hiệu TTL từ ESP32 vào cổng DB9 RS-232.

## Những điều chưa được xác nhận

- Mô phỏng Nios V đã PASS ở lượt `run.BxkfDT`: firmware boot hai lần,
  echo đúng 33 byte tổng cộng, 0 lỗi. Chưa thử CPU trên kit thật.
- Build trong terminal thường kết thúc 12/10/2026 lúc 16:17:29 đã đạt
  compile, timing (worst slack 0.119 ns) và kiểm tra license; không còn
  Simulation-Only. Đã có `build/HARDWARE_BUILD_READY.txt`; checksum bản FPGA
  và firmware đều khớp. Lịch sử xử lý license ở [LICENSING.md](LICENSING.md).
- Chưa thử USB-Blaster, USB-UART hoặc kit thật.

Cắm dây/cấp nguồn chưa đủ để chạy project này. Với quy trình thử nghiệm hiện
tại, `.sof` cấu hình FPGA và `.elf` trong RAM đều không bảo đảm được giữ sau
khi tắt nguồn; cần nạp lại. Tự khởi động sau cấp nguồn cần một quy trình lưu
cấu hình và firmware vào bộ nhớ không mất điện, chưa triển khai ở bước này.
