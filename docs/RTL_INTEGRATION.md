# UART APB: thiết kế RTL và cách kiểm thử

Kết quả regression: **12/12 lượt PASS với Icarus Verilog 12.0**.
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
  +-- register_file      : TX, CFG, CTRL, STATUS, RX
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
| 0x10 | RX data | RO | 0 | [7:0] dữ liệu nhận, đọc thành công xác nhận đã nhận |

CFG: data bits `00/01/10/11` tương ứng `5/6/7/8`; stop `0/1` tương ứng `1/2`;
parity enable `0/1` tương ứng tắt/bật; parity type **1 = EVEN, 0 = ODD**.
Ví dụ: 8N1 = `0x03`, 8E1 = `0x1B`, 8O1 = `0x0B`, 8E2 = `0x1F`.
Các bit reserved đọc 0, ghi bị bỏ qua. Bảng spec có lỗi đánh máy phần reserved
của STATUS chồng lên bit parity_error; implementation giữ bit 2 parity và
reserved ở [31:3].

`PSTRB` áp dụng từng byte lane. Các field đều nằm trong byte thấp nên chỉ
`PSTRB[0]` làm thay đổi register. Ghi với strobe = 0 hoặc chỉ các byte cao là
no-op tại register RW hợp lệ. Ghi RO vẫn là lỗi bất kể strobe. Read dùng PSTRB=0.
Địa chỉ không thuộc 5 offset trên, kể cả địa chỉ không căn hàng 4 byte, trả lỗi;
không decode bỏ qua các bit cao nên không tạo alias.

## APB và ranh giới hai module mới

APB slave có 3 state IDLE, SETUP, ACCESS. Nó chốt địa chỉ, hướng, strobe và data
ở cạnh clock của SETUP. Có **1 wait cycle cố định** trước phản hồi ACCESS;
register file có thể kéo dài thêm. Hỗ trợ back-to-back với PSEL giữ 1 và một
SETUP cycle (`PENABLE=0`) giữa hai transfer.

Register file trả `read_en_o`/`write_en_o` theo ý nghĩa **sẵn sàng hoàn tất**,
không phải xung ghi. Thêm `access_i` để side effect chỉ xảy ra khi transfer
thực sự hoàn tất; thêm `error_o` để chuyển lỗi decode/RO về APB slave.
Top nối `tx_busy_i` để xác nhận TX đã nhận lệnh và `rx_pending_o` để điều khiển
RTS theo trạng thái buffer. Các cổng nội bộ bổ sung này khắc phục chỗ chưa đầy đủ
trong bảng giao diện spec; không thêm cổng ngoài APB.

Giao dịch lỗi hoàn tất với PREADY=1 và PSLVERR=1, không làm thay đổi register.
PSLVERR chỉ lên trong chu kỳ hoàn tất. Ghi/đọc không có side effect ở SETUP,
khi PSEL=0, hoặc trong các wait cycle. PRDATA trả 0 khi không đọc/đang báo lỗi.
Quy tắc giao thức được đối chiếu với
[Arm AMBA APB, IHI0024D](https://documentation-service.arm.com/static/60d5b505677cf7536a55c245).

## TX, RX và các quyết định ở trường hợp biên

- TX done là trạng thái sticky: reset = 1, xuống 0 khi lệnh START được nhận,
  lên 1 khi frame truyền xong. Không nối trực tiếp xung done của core vào bit
  trạng thái mà CPU cần polling.
- Ghi CTRL[0]=1 tạo một yêu cầu. START giữ pending khi CTS chưa cho phép, tự
  xóa khi TX nhận lệnh. Đọc CTRL thấy pending; ghi 0 không hủy yêu cầu đã nhận.
  Không cần phần mềm ghi 1 rồi ghi 0. Mỗi lần ghi 1 được chấp nhận gửi một frame.
- Ghi TX data khi TX done=0 sẽ **wait** đến lúc frame trước xong; ghi START=1
  khi bận cũng wait. Ghi không đụng byte thấp không wait. Không có TX FIFO.
- CTS active-low và được đồng bộ 2 FF ở top. CTS chặn bắt đầu frame mới;
  đổi CTS giữa frame không cắt frame đang gửi. Nếu CTS giữ 1 vô hạn, lệnh đang
  pending vẫn chờ; CPU nên polling STATUS thay vì cố ghi tiếp.
- TX chốt format và parity lúc thực sự bắt đầu frame (sau khi CTS cho phép).
  RX chốt format lúc phát hiện START. Ghi CFG giữa frame chỉ ảnh hưởng frame
  tiếp theo. Nếu còn chờ CTS thì format chưa được chốt.
- RX lấy mẫu x16, kiểm tra START ở giữa bit, lấy từng bit LSB-first. Ký tự 5–7
  bit được zero-extend đúng vào các bit thấp. Chỉ START được chấp nhận ở IDLE
  mới reset bộ đếm lấy mẫu; cạnh xuống của data không được reset timing.
- Sau byte RX hợp lệ, RX done giữ 1 và parity_error gắn với byte đó. Đọc STATUS
  không xóa chúng. Một lần đọc RX hoàn tất sẽ xóa RX done và parity_error;
  dữ liệu RX vẫn giữ giá trị cuối cho tới byte mới.
- Đọc RX khi rỗng **wait cho đến khi có byte**. Muốn không blocking, CPU cần đọc
  STATUS trước. Không có timeout phần cứng; reset có thể hủy giao dịch đang chờ.
- RX buffer chỉ có 1 byte. RTS active-low: bằng 1 trong khi đang nhận hoặc còn
  byte chưa đọc, về 0 khi sẵn sàng. Nếu bên gửi bỏ qua RTS, byte mới khi buffer
  đầy bị bỏ; byte cũ không bị ghi đè. Không có overrun flag trong spec.
- Nếu CPU đọc RX và core hoàn tất byte mới cùng cạnh clock: CPU nhận byte cũ;
  byte mới cùng parity_error mới được giữ lại và RX done vẫn là 1.
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

- `tb_register_file.sv`: sticky status, command pending/accept, strobe, RO,
  không side effect khi thiếu access, buffer đầy, đọc đồng thời RX completion.
- `tb_baud_rate_check.sv`: 9 baud yêu cầu + biên divider 1/2, khoảng tick,
  số tick, độ rộng và reset.
- `tb_dti_uart.sv`: APB BFM và serial TX/RX model độc lập với counters của DUT;
  kiểm tra 24 frame format × 8 payload pattern, full-duplex, hai seed mỗi seed
  64 frame ngẫu nhiên có baud skew ±2%, CTS/RTS, blocking access, back-to-back,
  byte strobe, reserved bits, lỗi địa chỉ/RO, parity/frame error, break,
  false START, đổi cấu hình khi đang chạy, reset giữa frame/transfer.
- Smoke test top tích hợp tại 8 baud còn lại, mỗi baud 4 format.

Ba testbench liệt kê ở trên là bộ regression đang dùng. Các testbench cũ,
source trùng, bản backup cũ và cache của công cụ đã được xóa khi dọn project.

Phạm vi công việc hiện tại: RTL và simulation. Chưa tạo hệ thống Nios, driver C,
Avalon-to-APB bridge, pin assignment, timing constraint cho board hay nạp FPGA.
