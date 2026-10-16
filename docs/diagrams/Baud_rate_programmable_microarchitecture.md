# Microarchitecture baud_rate_gen hiện tại

Đối chiếu `UART/rtl/baud_rate_gen.v` và kết nối trong `UART/rtl/dti_uart.v`.
Đây là sơ đồ logic tương đương RTL, không phải sơ đồ placement/netlist sau tổng hợp.

## Các cổng

| Cổng | Hướng | Độ rộng | Vai trò |
|---|---|---|---|
| clk | Input | 1 | Clock hệ thống 50 MHz trong project |
| rst_n | Input | 1 | Reset bất đồng bộ, active-low |
| divider_i | Input | 16 | Số clock giữa hai tick; nối BAUD_DIV_ACTIVE |
| reload_i | Input | 1 | Xóa pha đếm/tick; nối baud_apply |
| baud_tick | Output | 1 | Clock-enable ×16, dùng chung cho TX và RX |

## Các khối và phương trình tương đương

```text
invalid     = (divider_i == 0)
flush       = reload_i OR invalid
threshold   = divider_i - 16'd1
terminal    = (counter >= threshold)   // so sánh unsigned
clear_count = flush OR terminal
counter_D   = clear_count ? 16'd0 : (counter + 16'd1)
tick_D      = terminal AND NOT flush
```

- `counter` là một register 16 bit, chốt `counter_D` tại cạnh lên `clk`.
- `baud_tick` là một flip-flop, chốt `tick_D` cùng cạnh lên `clk`.
- Cả hai có reset bất đồng bộ `rst_n=0`, đưa Q về 0.
- Nhánh MUX 0: `counter + 1`; nhánh MUX 1: số 0; S = `clear_count`.
- Trong SVG, dây có chấm tròn mới là điểm nối; giao cắt không chấm không nối.

Ưu tiên đúng code: reset → reload/invalid → terminal → tăng counter.
Nếu counter đạt divider−1 và flush=0, cạnh clock tiếp theo đưa counter về 0
và baud_tick lên 1. Divider>1: tick rộng một clock. Divider=1: tick bằng 1 ở
mọi chu kỳ sau khi hết reset/reload, tương ứng enable ở mọi clock. Divider=0:
counter/tick bị giữ 0, không sử dụng phép trừ tràn để tạo tick.

## Khác sơ đồ cũ

Sơ đồ hiện tại có **một counter và một tick chung**, không có cnt_tx/cnt_rx hay
div_tx/div_rx riêng. TX/RX vẫn có các bộ đếm lấy mẫu/bit bên trong core của mình,
nhưng chúng nằm ngoài module baud_rate_gen đang được vẽ.

Divider không còn là hằng số trong bộ đếm. register_file giữ ACTIVE và chỉ cho
APPLY khi TX/RX an toàn. Điều kiện an toàn, SHADOW/ACTIVE, thanh ghi APB và IRQ
đều nằm ngoài ranh giới module trong hình. Ba parameter cũ đã được bỏ khỏi
baud_rate_gen; module chỉ nhận divider_i và reload_i. CLK_FREQ/BAUDRATE ở tầng
dti_uart vẫn dùng để tính divider mặc định sau reset.

File đi kèm: SVG chỉnh sửa/phóng to được, PDF vector và PNG 3600×2300.
