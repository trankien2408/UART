# Đề xuất microarchitecture baud: TX và RX tách riêng

Sơ đồ theo yêu cầu có hai nhánh cấu trúc riêng, mỗi nhánh gồm:

| Khối | Nhánh TX | Nhánh RX |
|---|---|---|
| Counter register 16 bit | cnt_tx | cnt_rx |
| Bộ cộng 1 và MUX chọn 0 | Riêng | Riêng |
| Comparator unsigned >= divider_i−1 | term_tx | term_rx |
| Cổng OR reset counter | clear_tx | clear_rx |
| Cổng AND có input flush đảo | tick_tx_D | tick_rx_D |
| Flip-flop output 1 bit | tick_tx | tick_rx |

Cùng dùng input clk, rst_n, divider_i[15:0], reload_i. Logic flush dùng chung:

```text
flush = reload_i OR (divider_i == 0)
clear_tx = flush OR term_tx
clear_rx = flush OR term_rx
cnt_tx_D = clear_tx ? 0 : cnt_tx+1
cnt_rx_D = clear_rx ? 0 : cnt_rx+1
tick_tx_D = term_tx AND NOT flush
tick_rx_D = term_rx AND NOT flush
```

Các cổng OR và AND được vẽ bằng ký hiệu logic ANSI. Chấm tròn nhỏ ở input AND
là phép đảo flush. Chấm nối dây là điểm kết nối; giao cắt không chấm không nối.
Counter và flip-flop output đều chốt ở cạnh lên clk, có clear bất đồng bộ rst_n=0.
Vì hai nhánh có chung divider/reset/reload nên dạng sóng vẫn cùng tần số và pha.
Sơ đồ này chưa bổ sung divider hoặc điều khiển pha riêng cho từng chiều.

**Trạng thái:** đây là thiết kế đề xuất để thay cấu trúc một counter/flip-flop
hiện tại. Bước tạo sơ đồ không sửa RTL, không build hay xác nhận triển khai hai
counter trên FPGA. Sơ đồ hiện tại bám code vẫn được giữ ở bộ file
Baud_rate_programmable_microarchitecture.* để phân biệt hai phương án.
