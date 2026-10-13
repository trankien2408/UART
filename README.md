# UART trên FPGA DE2-115 với CPU Nios V

Project triển khai UART bằng Verilog trên kit **DE2-115 (Cyclone IV E)**,
điều khiển bằng firmware C chạy trên **Nios V/m**. Máy tính sử dụng chip
USB-UART có sẵn trên board ESP32 để giao tiếp với UART của FPGA.

Có hai chương trình C:

- **Echo:** nhận byte từ UART rồi phát lại chính byte đó; ghi log RX/TX qua JTAG UART.
- **Scope:** tự phát chuỗi `hello`, chờ khoảng 100 ms sau mỗi chuỗi rồi lặp lại,
  dùng để quan sát tín hiệu bằng oscilloscope. Không thêm CR/LF hoặc byte NUL.

UART mặc định: **115200 baud, 8 data bits, no parity, 1 stop bit (8N1)**.

## Kiến trúc hệ thống

```mermaid
flowchart LR
    PC[Terminal serial: picocom] <-->|USB| USB[Chip USB-UART trên ESP32]
    USB <-->|TX / RX qua GPIO| UART[UART RTL: baud rate, TX, RX]
    CPU[Nios V/m chạy firmware C] <-->|Avalon-MM| BR[Bridge Avalon sang APB]
    BR <-->|APB| REG[APB slave và register file]
    REG <--> UART
    CPU --> JU[JTAG UART]
    JU --> BL[USB-Blaster]
    BL --> LOG[Terminal log: juart-terminal]
```

ESP32 được dùng làm bộ chuyển USB-UART; CPU ESP32 được giữ reset và không
chạy firmware chuyển tiếp. Hai terminal trong VS Code có vai trò khác nhau:
picocom gửi/nhận dữ liệu UART, còn juart-terminal hiển thị log của CPU Nios V.

## Cấu trúc thư mục

| Thư mục / file | Nội dung |
|---|---|
| `rtl/` | Các khối UART, APB và bridge |
| `fpga/` | Project Quartus, top-level, pin mapping và script tạo/nạp hệ thống |
| `firmware/main.c` | Chương trình echo và log RX/TX |
| `firmware/dti_uart.c` | Driver truy cập thanh ghi UART |
| `firmware/examples/scope_main.c` | Chương trình phát `hello` để đo sóng |
| `tb/`, `sim/` | Testbench và script mô phỏng |

## Điều kiện chạy

Hướng dẫn giả định FPGA, ESP32, dây TX/RX/GND, jumper và driver USB đã được
thiết lập đúng; kit bật nguồn và công tắc RUN/PROG ở **RUN**.
Máy đã có Quartus 25.1std, Nios V tools, RiscFree RISC-V GCC, license Nios V/m,
picocom và Python/pyserial. Questa chỉ cần khi chạy mô phỏng CPU.

**Tất cả lệnh dưới đây chạy tại thư mục chứa README này** — thư mục `UART/`
có các thư mục con `fpga/`, `firmware/`, `rtl/`.

Đường dẫn bộ công cụ được cấu hình trong `fpga/scripts/env.sh`. Khi dùng máy
khác, đặt `UART_QUARTUS_ROOT`, `UART_RISCFREE_ROOT` và `UART_NIOSV_LICENSE_FILE`
theo cài đặt của máy trước khi chạy script. Dùng license cấp cho máy của bạn.

## 1. Compile FPGA và firmware echo

Lần đầu, hoặc sau khi clone repository:

```bash
# Tạo hệ thống Platform Designer và compile FPGA thành file .sof.
bash fpga/build.sh all

# Tạo BSP, project C và build firmware echo thành file .elf.
bash firmware/build.sh all echo
```

Khi hệ thống đã được generate và chỉ cần compile lại:

```bash
bash fpga/build.sh compile
bash firmware/build.sh compile echo
```

Nếu đổi cấu trúc hệ thống Platform Designer, dùng lại các lệnh `all`.
Nếu chỉ sửa C, chỉ cần build firmware; không cần compile Quartus.

File đầu ra:

- FPGA: `fpga/build/output_files/de2_115_uart.sof`.
- Firmware echo: `firmware/build/app/build/uart_firmware.elf`.

Build FPGA phải vượt kiểm tra timing và license, tạo
`fpga/build/HARDWARE_BUILD_READY.txt`. Script nạp còn kiểm tra checksum để
tránh dùng bản build không khớp source hiện tại.

## 2. Nạp kit

Không cần mở giao diện Quartus hoặc file `.qpf` trước khi chạy script.

```bash
source fpga/scripts/env.sh
jtagconfig

# Cable 1, FPGA ở vị trí 1 trong chuỗi Quartus, firmware echo.
bash fpga/program.sh 1 1 echo
```

Script nạp `.sof`, sau đó tải `.elf` vào RAM và chạy CPU. 

## 3. Mở hai terminal trong VS Code

**Terminal 1 — xem log CPU qua USB-Blaster:**

```bash
bash firmware/terminal_jtag.sh -c 1 -d 0
```

**Terminal 2 — giao tiếp UART qua ESP32:**

```bash
python3 -m serial.tools.list_ports -v
bash firmware/terminal_uart.sh /dev/ttyUSB0
```

Thay `/dev/ttyUSB0` bằng cổng USB-UART thực tế. Script picocom đặt 115200 8N1,
tắt flow control và local echo; Enter gửi CR+LF.


## 4. Phát hello để đo oscilloscope

```bash
bash firmware/build.sh all scope
bash fpga/program.sh 1 1 scope
```

Firmware tự phát 5 byte `68 65 6C 6C 6F` rồi chờ khoảng 100 ms. Picocom nhận
`hellohello...`; chế độ này không echo RX và không in log JTAG.

Đo tại **GPIO[0] / UART_TX**, mass nối GND kit. Chọn trigger cạnh xuống,
khoảng 1,5 V; timebase 100 µs/div để xem cả chuỗi hoặc 10 µs/div để xem từng
frame. Dữ liệu UART truyền bit thấp trước, idle/stop ở mức cao.

Để quay lại echo:

```bash
bash firmware/build.sh compile echo
bash fpga/program.sh 1 1 echo
```

Chi tiết thêm: [firmware](firmware/README.md), [cấu hình kit và chân FPGA](fpga/README.md),
[kết quả kiểm thử](firmware/VALIDATION.md).
