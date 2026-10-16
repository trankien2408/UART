# UART APB: thiết kế RTL và cách kiểm thử

**Cập nhật 16/10/2026:** thêm baud runtime SHADOW/ACTIVE/APPLY tại 0x18–0x20
và interrupt UART tại 0x24–0x28. IRQ nối nội bộ về Nios V, không thêm chân board.
Xem [BAUD_INTERRUPT.md](BAUD_INTERRUPT.md). Các mô tả baud chỉ bằng parameter
bên dưới là thiết kế gốc; hiện parameter chọn baud reset, runtime dùng divider.


Kết quả regression: **15/15 lượt PASS với Icarus Verilog**.
Phạm vi và số liệu cụ thể nằm trong [VALIDATION.md](VALIDATION.md).

Nguồn yêu cầu: `../../dti_uart.pdf`, Revision 0.0.1; map địa chỉ lấy từ
`../../7up_uart.drawio.pdf` vì bảng register trong spec không ghi offset.
Các chỗ spec thiếu chi tiết được quy định rõ bên dưới; đây là quyết định của
bản triển khai này, không phải nội dung bổ sung có sẵn trong spec.

## Source chính và top

Source chính là `UART/rtl/`. File list chính xác nằm trong `UART/sim/rtl.f`.
Thư mục đã được dọn để chỉ giữ bộ source và testbench đang dùng.

```
dti_uart
  +-- apb_slave          : SETUP capture / ACCESS handshake
  +-- register_file      : TX, CFG, CTRL, STATUS, RX, FIFO_STATUS
  |   +-- uart_fifo x2   : TX 16 byte, RX 16 byte + parity
  +-- baud_rate_gen      : tick x16
  +-- tx_topmodule       : controller + datapath
  +-- rx_topmodule       : controller + datapath
```

Top `dti_uart` có các cổng ngoài đúng nhóm giao diện spec: `clk`, `reset_n`,
`pclk`, `presetn`, `psel`, `penable`, `pwrite`, `pstrb[3:0]`, `paddr[11:0]`,
`pwdata[31:0]`, `pready`, `pslverr`, `prdata[31:0]`, `rx`, `tx`, `cts_n`, `rts_n`.

**Bắt buộc nối `clk` và `pclk` vào cùng một net clock.** Cùng tần số nhưng khác
pha/khác nguồn clock không được hỗ trợ; thiết kế này không có bridge CDC.
Thông thường nối `reset_n` và `presetn` vào cùng reset. Kéo thấp một trong hai
sẽ reset toàn bộ UART. Reset active-low, assert bất đồng bộ; hệ thống bên ngoài
cần nhả reset đồng bộ với clock khi dùng trên FPGA.

Mặc định `CLK_FREQ=50000000`, `BAUDRATE=115200`. Baud cấu hình bằng parameter,
không có thanh ghi baud. Divider dùng phần nguyên `CLK_FREQ/(16*BAUDRATE)`;
baud thực bằng `CLK_FREQ/(16*divider)`. TX/RX đều cần tick x16; không đổi hệ số
này riêng lẻ. Giá trị divider phải >= 1. Với 50 MHz, cả 9 baud trong spec hợp lệ.

## Register map (byte addressing)

| Offset | Register | Quyền | Reset | Các bit có nghĩa |
|---|---|---|---|---|
| 0x00 | TX data | RW | 0 | [7:0] dữ liệu gửi |
| 0x04 | CFG | RW | 0 | [1:0] data bits, [2] stop, [3] parity enable, [4] parity type |
| 0x08 | CTRL | RW / tự xóa | 0 | [0] START |
| 0x0C | STATUS | RO | 1 | [0] TX done, [1] RX done, [2] parity error |
| 0x10 | RX data | RO | 0 | [7:0] byte đầu RX FIFO, đọc thành công pop một byte |
| 0x14 | FIFO_STATUS | RO / W1C bit 4 | 0x0A | [0] TX full, [1] TX empty, [2] RX full, [3] RX empty, [4] RX overrun, [15:8] TX count, [23:16] RX count |

CFG: data bits `00/01/10/11` tương ứng `5/6/7/8`; stop `0/1` tương ứng `1/2`;
parity enable `0/1` tương ứng tắt/bật; parity type **1 = EVEN, 0 = ODD**.
Ví dụ: 8N1 = `0x03`, 8E1 = `0x1B`, 8O1 = `0x0B`, 8E2 = `0x1F`.
Các bit reserved đọc 0, ghi bị bỏ qua. Bảng spec có lỗi đánh máy phần reserved
của STATUS chồng lên bit parity_error; implementation giữ bit 2 parity và
reserved ở [31:3].

`PSTRB` áp dụng từng byte lane. Các field đều nằm trong byte thấp nên chỉ
`PSTRB[0]` làm thay đổi register. Ghi với strobe = 0 hoặc chỉ các byte cao là
no-op tại register RW hợp lệ. Ghi RO vẫn là lỗi bất kể strobe. Read dùng PSTRB=0.
Ngoài 6 offset cơ bản trên, 5 offset mới được mô tả trong BAUD_INTERRUPT.md.
Địa chỉ không thuộc các offset hợp lệ, kể cả địa chỉ không căn hàng 4 byte, trả lỗi;
không decode bỏ qua các bit cao nên không tạo alias.

## APB và ranh giới hai module mới

APB slave có 3 state IDLE, SETUP, ACCESS. Nó chốt địa chỉ, hướng, strobe và data
ở cạnh clock của SETUP. Có **1 wait cycle cố định** trước phản hồi ACCESS;
register file có thể kéo dài thêm. Hỗ trợ back-to-back với PSEL giữ 1 và một
SETUP cycle (`PENABLE=0`) giữa hai transfer.

Register file trả `read_en_o`/`write_en_o` theo ý nghĩa **sẵn sàng hoàn tất**,
không phải xung ghi. Thêm `access_i` để side effect chỉ xảy ra khi transfer
thực sự hoàn tất; thêm `error_o` để chuyển lỗi decode/RO về APB slave.
Top nối `tx_busy_i` để xác nhận TX đã nhận lệnh và `rx_full_o` để điều khiển
RTS theo trạng thái buffer. Các cổng nội bộ bổ sung này khắc phục chỗ chưa đầy đủ
trong bảng giao diện spec; không thêm cổng ngoài APB.

Giao dịch lỗi hoàn tất với PREADY=1 và PSLVERR=1, không làm thay đổi register.
PSLVERR chỉ lên trong chu kỳ hoàn tất. Ghi/đọc không có side effect ở SETUP,
khi PSEL=0, hoặc trong các wait cycle. PRDATA trả 0 khi không đọc/đang báo lỗi.
Quy tắc giao thức được đối chiếu với
[Arm AMBA APB, IHI0024D](https://documentation-service.arm.com/static/60d5b505677cf7536a55c245).

## TX, RX và các quyết định ở trường hợp biên

- TX FIFO chứa 16 byte chờ, ngoài ra có một thanh ghi byte đang phát/chờ CTS.
  RX FIFO chứa 16 byte; mỗi byte đi kèm một bit lỗi parity.
- Ghi TX chỉ cập nhật staging register. Ghi CTRL[0]=1 chụp byte staging vào FIFO;
  mỗi giao dịch START thành công tạo đúng một frame. Ghi TX không làm đổi byte
  đang phát. START khi FIFO đầy sẽ wait đến lúc có chỗ; byte lane thấp bị mask
  thì không enqueue và không wait.
- STATUS.TX_DONE = 1 khi FIFO và bộ phát đều đã rỗng, kể cả stop bit hoàn tất.
  FIFO_STATUS.TX_EMPTY chỉ nói hàng đợi rỗng: vẫn có thể có một byte đang phát.
  TX count không gồm byte đang phát/chờ CTS. CTRL[0] phản ánh yêu cầu của bộ
  nạp TX đang chờ core nhận, không phải số byte đang chờ.
- CTS active-low được đồng bộ 2 FF, chặn bắt đầu frame mới, không cắt frame
  đang chạy. Nếu CTS giữ 1, FIFO cuối cùng sẽ đầy. Phần mềm dùng TX_FULL trước
  khi enqueue để tránh giữ bus chờ; giao diện driver dành cho một CPU/task sở hữu.
- Ghi CFG có byte lane thấp hợp lệ phải chờ TX_DONE, để các byte đã queue không
  bị đổi format. RX chốt format ở START; chỉ đổi CFG khi phía gửi RX đang idle.
- RX lấy mẫu x16, kiểm tra START ở giữa bit, lấy từng bit LSB-first. Ký tự 5–7
  bit được zero-extend đúng vào các bit thấp. Chỉ START được chấp nhận ở IDLE
  mới reset bộ đếm lấy mẫu; cạnh xuống của data không được reset timing.
- RX_DONE = !RX_EMPTY, PARITY_ERROR thuộc byte đầu FIFO. Đọc STATUS không pop.
  Đọc RX thành công pop đúng một byte; nếu còn dữ liệu, RX_DONE vẫn bằng 1 và
  parity chuyển sang byte tiếp theo. Khi rỗng, giá trị preview giữ byte đọc cuối.
- Đọc RX rỗng wait đến khi có byte. Driver phải kiểm tra RX_DONE trước.
- RTS active-low lên 1 trong khi core đang nhận hoặc RX FIFO đầy; một byte chưa
  đọc không còn chặn nhận byte kế tiếp. Flow control cần phía gửi thực sự tuân
  thủ RTS; demo ESP32 chỉ dùng TX/RX/GND nên không tự ngăn được mọi trường hợp tràn.
- Nếu FIFO đầy, byte mới bị bỏ và RX_OVERRUN giữ 1. Ghi 1 vào bit 4 của 0x14
  xóa cờ; bit khác chỉ đọc, ghi bị bỏ qua. Tràn mới cùng cạnh xóa thắng lệnh xóa.
- Pop và push cùng cạnh khi đầy: CPU nhận byte cũ, byte mới được giữ, count
  không đổi và không báo overrun. Khi rỗng, byte vừa đến không bị pop trước
  khi CPU thấy READY. Reset xóa cả FIFO, active TX và overrun.
- Sai parity: vẫn nhận byte, set parity_error. Stop bit không hợp lệ: bỏ cả
  frame, không set RX done. Core có frame_error nội bộ; không mở rộng STATUS
  vì spec chỉ quy định ba bit trạng thái. Kiểm tra cả stop bit thứ hai nếu dùng.
- RX báo hoàn tất tại điểm lấy mẫu giữa stop bit cuối, sau đó sẵn sàng bắt cạnh
  START tiếp theo. Cách này tránh bỏ lỡ frame nối tiếp khi bên gửi nhanh hơn.
- Reset hủy frame TX/RX, lệnh pending và APB đang chờ; khôi phục các reset value.

## Chạy kiểm thử

Từ thư mục gốc project:

```bash
bash UART/sim/run_tests.sh
```

Script ưu tiên Icarus Verilog nếu đã cài (`iverilog` và `vvp`), nếu không sẽ
chọn Questa. Có thể chỉ định:

```bash
bash UART/sim/run_tests.sh --simulator iverilog
bash UART/sim/run_tests.sh --simulator questa
bash UART/sim/run_tests.sh --simulator questa --compile-only
```

Nếu Questa nằm ở đường dẫn khác, đặt `QUESTA_BIN=/duong/dan/questa/bin` trước
lệnh. Build riêng trong `/tmp/uart-regression.*`; log trong
`UART/sim/results/<simulator>/`. Các thư mục build/log được tạo khi chạy;
file sinh tự động từ các lượt trước đã được dọn khỏi project.
Compile-only không phải simulation PASS. Mỗi test bắt buộc có PASS marker và
không có assertion failure; watchdog và timeout ngăn test treo vô hạn.

Kiểm tra khả năng tổng hợp bằng Quartus (chỉ Analysis & Synthesis, không fitter):

```bash
bash UART/sim/check_synthesis.sh
```

Log/report nằm trong `UART/sim/results/quartus/`. `QUARTUS_BIN` cho phép thay
đường dẫn cài đặt. Compile và synthesis thành công không thay thế simulation.

- `tb_uart_fifo.sv`: 30.000 chu kỳ ngẫu nhiên, depth 1/3/16, wrap, reset, push/pop đồng thời.
- `tb_register_file.sv`: TX snapshot, full/backpressure, RX ordering/parity, overrun/W1C, simultaneous replacement và reset.
- `tb_baud_rate_check.sv`: 9 baud yêu cầu + biên divider 1/2, khoảng tick,
  số tick, độ rộng và reset.
- `tb_dti_uart.sv`: APB BFM và serial TX/RX model độc lập với counters của DUT;
  kiểm tra 24 frame format × 8 payload pattern, full-duplex, hai seed mỗi seed
  64 frame ngẫu nhiên có baud skew ±2%, CTS/RTS, blocking access, back-to-back,
  byte strobe, reserved bits, lỗi địa chỉ/RO, parity/frame error, break,
  false START, đổi cấu hình khi đang chạy, reset giữa frame/transfer.
- Smoke test top tích hợp tại 8 baud còn lại, mỗi baud 4 format.

Bản mở rộng FIFO giữ nguyên 5 offset cũ và 3 bit STATUS cũ; 0x14 là phần
mở rộng của project, không phải thanh ghi đã có trong spec ban đầu.
Sau khi đổi RTL phải generate/compile FPGA và nạp SOF mới, không chỉ nạp ELF.
Xem [FIFO.md](FIFO.md) và README gốc để build/nạp toàn hệ thống.
