# Kết quả kiểm tra RTL UART

Ngày: 2026-10-11. Simulator: **Icarus Verilog 12.0 (stable)**.

**12/12 lượt regression PASS.** Script kết thúc với `ALL TESTS PASSED`.
Đã đối chiếu SHA-256 để xác nhận source/testbench hiện tại đúng phiên bản được chạy.
Sau khi dọn project, RTL, testbench và script vẫn được giữ nguyên từng byte;
log/report sinh tự động đã được xóa. Bảng dưới ghi lại kết quả đã chạy trước đó.

## Kết quả simulation

| Lượt kiểm tra | Kết quả | Số kiểm tra / frame |
|---|---|---|
| Register file | PASS | 27 assertion `check()` |
| Baud-rate | PASS | 9 baud trong spec + divider 1/2; 34 tick mỗi cấu hình |
| Integration 115200, seed 12345 | PASS | 12.315 assertion; 264 TX frame, 274 RX frame |
| Integration 115200, seed 20261011 | PASS | 12.250 assertion; 264 TX frame, 274 RX frame |
| Smoke 2400 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 4800 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 9600 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 19200 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 38400 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 57600 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 76800 | PASS | 182 assertion; 4 TX, 4 RX |
| Smoke 230400 | PASS | 182 assertion; 4 TX, 4 RX |

Tổng: **26.048 assertion `check()`**, chưa tính kiểm tra trực tiếp trong
baud-rate test và protocol guards. Serial model đã kiểm tra 560 frame TX và
phát 580 frame RX vào DUT; số RX bao gồm frame cố tình sai parity/stop và gửi
khi buffer đầy. False-start/break/reset còn được kích thích riêng.

Hai lượt integration mỗi lượt bao phủ:

- 24 cấu hình frame: 5–8 data bit × 1/2 stop bit × không parity/odd/even;
  mỗi cấu hình 8 mẫu dữ liệu, TX/RX hoạt động đồng thời.
- 64 frame ngẫu nhiên, pha đầu vào bất đồng bộ và sai lệch chu kỳ bit RX ±2%.
- Đọc/ghi APB, back-to-back, đủ 16 mẫu PSTRB cho TX/CFG, reserved bits,
  địa chỉ sai/không căn hàng, ghi register RO và hủy SETUP.
- CTS chặn START, giữ lệnh pending, ghi TX/START khi bận, CTS đổi giữa frame;
  kiểm tra không phát lặp và TX done không lên sớm ở giữa stop bit.
- RX done/parity error giữ đến khi đọc RX; RTS phản ánh bận/buffer đầy;
  byte chưa đọc không bị ghi đè, nhận hai frame nối tiếp không có khoảng nghỉ.
- Sai parity, false START, lỗi stop thứ nhất/thứ hai, break và phục hồi.
- Đổi CFG giữa frame, reset bất đồng bộ giữa TX/RX và APB đang chờ.

Unit test register file còn kiểm tra chính xác trường hợp CPU đọc RX cùng cạnh
clock với byte mới hoàn tất: CPU nhận byte cũ, byte mới được giữ lại cùng cờ
trạng thái mới. Test baud-rate kiểm tra chu kỳ, độ rộng tick và reset.

Smoke ở mỗi baud khác 115200 kiểm tra bốn format; ma trận đầy đủ 24 format và
các ca biên được chạy tại 115200. Đây là phạm vi kiểm chứng đã thực hiện,
không phải kiểm tra vét cạn mọi chuỗi dữ liệu và mọi sai lệch clock.

## Điều chỉnh khi chạy Icarus

Không cần sửa thêm RTL. Một phép kiểm tra trong APB testbench dùng
`$isunknown({prdata, pslverr})` báo sai trên Icarus 12.0, dù data và error đều
bằng 0. Đã tái hiện bằng chương trình độc lập và thay bằng
`(^{prdata, pslverr}) !== 1'bx`. Phép kiểm tra mới vẫn phát hiện cả X và Z;
không bỏ hoặc nới lỏng điều kiện kiểm tra bus.

## Compile và synthesis

- Icarus: biên dịch toàn bộ regression không lỗi/cảnh báo.
- Questa Altera Starter 2025.2: lượt compile trước đó có 0 errors, 0 warnings.
  Simulation Questa từng bị chặn bởi license `intelqsimstarter` báo Invalid host;
  kết quả PASS chức năng ở trên được chạy bằng **Icarus**, không phải Questa.
- Quartus Prime Lite 25.1std.0 Analysis & Synthesis, top `dti_uart`, target
  Cyclone IV E EP4CE115F29C7: **Successful, 0 errors**, 250 logic elements,
  116 registers; không có cảnh báo latch. RTL không đổi sau lượt synthesis này.
- 53 warnings Quartus: 24 output `prdata[31:8]` luôn 0, 27 input bit không
  ảnh hưởng logic (`pwdata[31:8]`, `pstrb[3:1]`), cộng 2 cảnh báo tổng hợp nhóm.
  Đây là hệ quả các field nằm trong byte thấp và reserved đọc 0.

Ở giai đoạn RTL được ghi nhận trong tài liệu này chưa chạy fitter, timing
closure hoặc tạo bitstream. Các bước tích hợp SoC đã được thực hiện sau đó;
xem [kết quả firmware và giới hạn kiểm chứng hiện tại](../firmware/VALIDATION.md).
Chưa thử trên board.

## Chạy lại và tạo log

Từ thư mục gốc project:

```bash
bash UART/sim/run_tests.sh --simulator iverilog
```

Các đường dẫn sau được tạo lại khi chạy script tương ứng; chúng không được
giữ trong thư mục sau bước dọn file sinh tự động:

- `../sim/results/iverilog/status.txt`: kết quả toàn bộ regression.
- `../sim/results/iverilog/*.log`: log của từng lượt chạy.
- `../sim/results/iverilog/source_manifest.txt`: thời điểm chạy và SHA-256 source.
- `../sim/results/quartus/uart_check.map.summary`: tóm tắt synthesis.
- `../sim/results/quartus/uart_check.map.rpt`: report chi tiết.
