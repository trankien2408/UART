# Kết quả kiểm tra firmware — 12/10/2026

Phạm vi: demo UART echo + JTAG log, chương trình self-test độc lập, build C
cho hệ thống Nios V/m hiện có. Chưa có kit để thử phần cứng.

| Kiểm tra | Kết quả | Phạm vi xác nhận |
|---|---|---|
| RISC-V GCC 13.2.0, demo echo | PASS | ELF32 RISC-V và ảnh khởi tạo `ram.hex` |
| RISC-V GCC 13.2.0, self-test | PASS | ELF/HEX riêng, không đưa self-test vào demo |
| Driver C, GCC + UBSan | PASS | 24 cấu hình, tham số sai, RX/TX không chờ, parity, timeout, không gửi lặp, tràn bộ đếm chu kỳ |
| Ứng dụng C thực tế, MMIO mô hình | PASS | 768 byte echo/log chính xác; 1024 byte khi JTAG bị chặn; thứ tự/tràn hàng đợi; parity; timeout qua wrap; SYSID sai; reset |
| Driver C + UART RTL bằng Icarus/VPI | PASS | 192 frame = 24 định dạng × 8 mẫu; 161399 giao dịch, 807000 chu kỳ |
| Demo C + UART RTL bằng Icarus/VPI | PASS | 256 byte đủ mọi giá trị + burst liên tục 256 byte; đúng thứ tự, không dư byte, JTAG bị chặn |
| Mô phỏng toàn hệ thống Nios V bằng Questa | PASS | Lượt run.BxkfDT: boot hai lần, 32 byte echo + 1 byte sau reset, 0 lỗi |
| Nạp FPGA, kết nối USB và hai terminal thật | CHƯA THỬ | Chưa có kit |

Demo: `text=14736`, `data=1848`, `bss=1344` byte; báo cáo Nios V còn khoảng
108.73 KiB cho stack + heap trong hệ thống hiện tại. Self-test:
`text=14344`, `data=1848`, `bss=1052` byte.

Kiểm thử host dùng `-Wall -Wextra -Werror -Wpedantic` và UndefinedBehaviorSanitizer.
Build target có cảnh báo từ mã/header BSP của hãng; không sửa mã BSP sinh tự động.

## Phân biệt mô hình với CPU thật

- Test host gọi trực tiếp `uart_demo_init()`/`uart_demo_poll()` từ **main.c đang
  dùng để build**, cùng console và driver; không viết lại thuật toán demo trong test.
- Co-simulation echo chạy cùng mã C trên CPU máy tính; bridge Avalon/APB, thanh
  ghi và UART TX/RX là RTL thật. SYSID/PIO/JTAG được mô hình hóa; JTAG luôn đầy.
  Dữ liệu UART vào/ra có thời gian bit danh định độc lập 8681 ns, clock RTL 50 MHz.
- Co-simulation không xác nhận tập lệnh, startup, trap hay hiệu năng của CPU Nios V.
  ELF mới đã thực thi thành công trên mô hình Nios V ở lượt run.BxkfDT; chưa thử kit.
- Testbench bộ giải mã TX được sửa để chờ start tiếp theo ngay sau khi lấy mẫu
  giữa stop bit. Chờ hết stop bit danh định có thể bỏ lỡ start của frame sát nhau
  do baud RTL làm tròn nhanh hơn baud danh định. Không thay đổi RTL để xử lý việc này.
- Các kết quả burst có phạm vi 256 byte được thử; không suy ra bảo đảm truyền
  liên tục vô hạn hoặc mất kết nối không mất dữ liệu.

## Log và cách chạy lại

- `build/logs/echo_compile.log`, `echo_size.log`: build demo.
- `build/logs/selftest_compile.log`, `selftest_size.log`: build self-test.
- `build/tests/driver.log`, `demo.log`, `syntax.log`: kiểm thử C.
- `../sim/results/firmware_cosim/run.log`: self-test C/RTL.
- `../sim/results/firmware_echo_cosim/run.log`: demo C/RTL.
- `../sim/results/niosv_firmware/console.log`, `transcript.log`, `status.txt`:
  lần thử mô phỏng CPU. Script hiện báo BLOCKED ngay nếu kiểm tra socket thất bại;
  log compile/elaboration trước đó vẫn được giữ nguyên.

## Chẩn đoán lỗi socket

Kiểm tra độc lập bằng Python trên cả IPv4 và IPv6 trong phiên làm việc này
đều thất bại ngay tại `socket()` với `errno=1: Operation not permitted`, trước
cả bước bind/listen. Vì vậy phiên này không có quyền tạo socket cần cho Questa;
chưa có cơ sở kết luận cài đặt Questa trên máy người dùng bị hỏng.

Script `../sim/check_local_socket.py` kiểm tra socket TCP cục bộ trên
`127.0.0.1` với cổng tự cấp phát. `run_niosv_firmware.sh` gọi nó trước khi compile
toàn hệ thống; `--compile-only` không cần bước kiểm tra này. Log chẩn đoán:
`../sim/results/niosv_firmware/socket_check.log`.

Chạy trực tiếp trong terminal VS Code/Linux của người dùng:

```bash
cd /home/kien/Documents/uart
bash UART/sim/run_niosv_firmware.sh
```

Không cần board, cáp USB hoặc quyền sudo để thực hiện mô phỏng này. Việc mở
socket thành công chưa bảo đảm license và mô phỏng CPU sẽ chạy thành công;
cần đọc log mới nếu có lỗi tiếp theo. Không vô hiệu hóa firewall hoặc thay
quyền hệ thống để xử lý riêng lỗi đã quan sát trong phiên bị giới hạn này.

## Lượt chạy trực tiếp và bổ sung chẩn đoán

Lượt người dùng chạy trong terminal thường đã qua kiểm tra socket, compile,
load mô hình Nios V và UART. Log cũ dừng ở các cảnh báo khởi tạo RAM tại thời
điểm 0; chưa có READY/PASS. Điều này chưa đủ để kết luận CPU chạy đúng hoặc
xác định nguyên nhân chờ. Script trước chỉ chuyển đầu ra vào file nên terminal
không hiện tiến độ.

Đã bổ sung thông báo từng giai đoạn ngay trên terminal và heartbeat testbench
mỗi 1 ms mô phỏng: reset, địa chỉ fetch gần nhất, dữ liệu lệnh trả về gần nhất,
số phản hồi fetch, địa chỉ/giao dịch data và số byte echo. Địa chỉ fetch được
ghi nhận trên bus, không phải PC nội bộ CPU và không bảo đảm tương ứng trực
tiếp với dữ liệu trả về trong cùng dòng heartbeat. Boot watchdog là 5 ms,
watchdog toàn bài là 25 ms mô phỏng. Không ép tín hiệu CPU hoặc bỏ qua boot.

Lượt đang chạy đã compile testbench cũ nên phải dừng và chạy lại để dùng các
chẩn đoán mới. Log `--compile-only` được tách ra `niosv_firmware_compile` để
không ghi đè log CPU. Script dùng `console.log` để kiểm tra marker PASS vì
thông báo Tcl `puts` không nhất thiết xuất hiện trong transcript của Questa.

Các lệnh chạy nằm trong [README.md](README.md). Không nạp board trong lượt này.
Vấn đề license IP của lần build FPGA trước vẫn phải được giải quyết trước khi
nạp kit; lượt firmware này không chạy lại fitter hoặc xác nhận license phần cứng.

## Kiểm tra tiếp log và pin FPGA

Log người dùng có `boot watchdog` tại 5 ms, LED=00, chưa có echo. Các địa chỉ
fetch 0x68, 0x78, 0x17c nằm trong trap handler của ELF hiện tại; địa chỉ data
sau đó vượt RAM. Đây là dấu hiệu ngoại lệ lặp và stack hỏng, chưa xác định được
ngoại lệ ban đầu. Phần cuối console có vùng NUL lớn và SIGTERM; có khả năng
nhiều lượt chạy ghi chung file, không dùng đoạn này để khẳng định nguyên nhân.

Testbench mới đọc RVFI do wrapper hart cung cấp, giữ 64 lệnh gần nhất và báo
mcause/mepc/mtval khi HAL đọc ba CSR tương ứng, rồi dừng lỗi đầu tiên. Đây là
chẩn đoán chỉ đọc, không sửa firmware hoặc ép trạng thái CPU. Đã compile bằng
Questa; việc elaboration và chạy chẩn đoán này cần terminal thường do phiên
công cụ vẫn bị chặn socket. Chưa có kết quả của lần CPU chạy với trace mới.

Script dùng flock để chặn chạy trùng; mỗi lượt có thư mục run riêng. Các tên
console.log/transcript.log/status.txt tại thư mục kết quả trỏ đến lượt mới nhất.
Log cũ dạng file thường được giữ dưới tên previous_* trong thư mục run đầu
sau cập nhật. Cần Ctrl+C lượt script cũ đang chạy trước khi khởi chạy bản mới,
vì script cũ chưa có khóa.

Đã sửa IO standard KEY0 và LEDG thành 2.5 V theo bảng chân DE2-115; clock và
GPIO UART giữ 3.3-V LVTTL. Quartus compile và timing sau sửa đạt (worst slack
0.119 ns), nhưng checker không đánh dấu sẵn sàng nạp do cảnh báo license
Nios V `Could not get NIC ID` / simulation-only. Chưa xác nhận phần cứng.

## Ngoại lệ đầu tiên đã xác định và sửa firmware

Lượt `../sim/results/niosv_firmware/run.lUaLhe/console.log` dừng tại 164370 ns:
`mcause=00000002 mepc=00000590 mtval=b0002873`. Đối chiếu ELF của lượt đó:
0x590 là `csrr a6,mcycle` trong dti_configure (inline dti_wait_tx).
CPU đã vào main và qua kiểm tra SYSID; lỗi là đọc CSR mcycle không hợp lệ
trên core hiện tại, trước khi cấu hình UART xong và bật READY.

Đã sửa uart_platform.h: đọc 32 bit thấp của mtime qua MMIO bằng địa chỉ
ALT_CPU_MTIME_OFFSET do BSP cung cấp (0x30000). mtime tăng mỗi chu kỳ clock;
timeout vẫn dùng phép trừ uint32_t qua wrap, không cần ngắt timer hay ghi
mtime/mtimecmp. Đối chiếu HAL intel_niosv.h/mtimer.c và
[tài liệu Intel](https://cdrdv2-public.intel.com/794788/ug-683632-794788.pdf),
phần Timer and Software Interrupt Module.

Build lại echo và selftest đều PASS; disassembly cả hai không còn lệnh mcycle
và bản echo đọc MMIO 0x30000. Test host driver/demo PASS, gồm timeout qua wrap.
Test host dùng đồng hồ giả, chưa xác nhận đọc timer trên mô hình Nios V.
Cần chạy lại run_niosv_firmware.sh trong terminal thường để xác nhận ELF mới
boot, echo và reset; log FAILED ở trên thuộc ELF trước bản sửa này.

## Xác nhận mô phỏng CPU PASS sau sửa mtime

Log: `../sim/results/niosv_firmware/run.BxkfDT/console.log`, kết thúc
12/10/2026 lúc 15:47:53. Marker:
`PASS tb_niosv_firmware: real Nios V CPU, C boot twice, external echoes=33`.
Status: `PASS full Nios V firmware simulation`; Errors: 0, Warnings: 24.
Questa báo elapsed 4 phút 49 giây cho khoảng 6.018 ms mô phỏng; thời gian
chờ dài trong lượt này không phải firmware bị treo. READY đầu tiên tại
164010 ns; READY sau reset tại 5843850 ns.

Kết quả xác nhận đường CPU/firmware/bus/UART và reset trong phạm vi testbench.
Các chẩn đoán FAILED phía trên là lịch sử trước bản sửa mtime. Chưa xác nhận
USB-Blaster, đấu dây, UART vật lý hoặc nạp kit. Build FPGA gần nhất vẫn báo
NIC ID/license IP-NIOSVM và Simulation-Only; cần compile lại trong terminal
thường, kiểm tra license nếu vẫn lỗi, trước khi chạy program.sh.

## Xác nhận chuẩn bị nạp phần cứng

Build Quartus từ terminal người dùng kết thúc 12/10/2026 lúc 16:17:29:
0 errors, worst slack 0.119 ns, không còn Failed to acquire license hoặc
Simulation-Only. `HARDWARE_BUILD_READY.txt` đã được tạo; kiểm tra cả manifest
FPGA và firmware đều thành công. Đã hoàn tất phần build/mô phỏng trên máy cho
quy trình nạp JTAG thử nghiệm. Chưa xác nhận cable/driver USB-Blaster, đấu dây,
điện áp jumper và truyền UART trên kit thật; chưa triển khai boot từ flash.
