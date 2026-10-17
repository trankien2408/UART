# Kết quả Quartus: Avalon–APB Bridge + UART

Ngày chạy: 17/10/2026. Công cụ: Quartus Prime Lite 25.1std.0, timing/power models Final.

## Phạm vi và điều kiện

Top tổng hợp: `rtl/uart_avalon.v`, gồm `avalon_apb_bridge` và `apb_uart`: APB Slave, Register File, TX/RX FIFO, baud generator, TX/RX core, IRQ và logic tích hợp. Không bao gồm CPU Nios V, Avalon interconnect, RAM hệ thống, PIO, console hay ESP32.

Target: Cyclone IV E **EP4CE115F29C7**, seed 1, clock **50 MHz** (20 ns). Đây là phép fit độc lập cho IP, không phải số liệu của toàn bộ SoC. 93 tín hiệu biên là virtual pins; chỉ clock là chân vật lý Y2. Cách này tránh gán bus Avalon nội bộ thành hàng chục chân I/O ngoài chip. Không thay RTL và project nạp board chính.

## Tài nguyên sau Fitter

| Chỉ số | Kết quả |
|---|---:|
| Logic elements (LE) | **541 / 114.480 (0.473%)** |
| LUT / total combinational functions | **461** |
| Flip-flop / dedicated logic registers | **323** |
| Bộ nhớ hữu ích | **272 bit** |
| M9K | **2 / 432** |
| DSP / PLL | **0 / 0** |

Cyclone IV E dùng LE với LUT 4 đầu vào. LUT và FF có thể cùng nằm trong một LE, nên LE không bằng LUT + FF. Các carry/arithmetic resource đã được Quartus tính theo cách ánh xạ của thiết bị.

| Khối | LE | LUT | FF | Memory bit | M9K |
|---|---:|---:|---:|---:|---:|
| Tổng bridge + UART | 541 | 461 | 323 | 272 | 2 |
| Avalon–APB Bridge | 117 | 92 | 57 | 0 | 0 |
| UART core (bao gồm các khối dưới) | 439 | 384 | 266 | 272 | 2 |
| APB Slave | 43 | 22 | 34 | 0 | 0 |
| Register File (bao gồm 2 FIFO) | 232 | 201 | 150 | 272 | 2 |
| TX FIFO | 47 | 30 | 39 | 128 | 1 |
| RX FIFO | 61 | 52 | 41 | 144 | 1 |
| Baud generator | 55 | 55 | 17 | 0 | 0 |
| TX core | 52 | 51 | 27 | 0 | 0 |
| RX core | 69 | 68 | 31 | 0 | 0 |

Các hàng cha bao gồm khối con, không cộng tất cả hàng. Số LE/LUT theo hierarchy có thể chia sẻ hoặc bị quy thuộc ở nhiều mức do tối ưu/packing qua ranh giới module; lấy hàng tổng làm kết quả thiết bị. LUT = LUT-only LCs + LUT/Register LCs. FF lấy cột Dedicated Logic Registers, không đếm lại bộ nhớ M9K thành FF.

FIFO TX là 16 × 8 = 128 bit, FIFO RX là 16 × 9 = 144 bit. Mỗi FIFO dùng một M9K; 272 bit là dung lượng hữu ích, còn dung lượng vật lý 2 M9K là 18.432 bit.

## Timing sau place-and-route

| Chỉ số | Kết quả |
|---|---:|
| Clock đang ràng buộc | **50 MHz** |
| Fmax / Restricted Fmax, slow 1,2 V 85 °C | **101.53 MHz** |
| Setup slack, slow 1,2 V 85 °C | **+10.151 ns** |
| Hold slack nhỏ nhất qua 3 corner | **+0.137 ns** |
| Setup/Hold TNS | **0 ns** |
| Unconstrained clocks / input paths / output paths | **0 / 0 / 0** |

Đường setup chậm nhất: `apb_uart:uart|apb_slave:u_apb|paddr_o[6]` → `avalon_apb_bridge:bridge|av_readdata[1]`, data delay 9,771 ns, 8 logic levels. Đường này đi qua logic giải mã/đọc thanh ghi và phản hồi APB về bridge.

Avalon đầu vào/đầu ra được mô hình đồng bộ cùng clock, external delay 0 ns để đặc trưng IP. Reset, RX và CTS là bất đồng bộ nên được loại khỏi timing biên; đầu ra UART không có clock nhận đồng bộ. Các đường đồng bộ bên trong vẫn được kiểm tra. Fmax ở đây là khả năng timing của IP trong lần fit này; không phải baud UART và không phải Fmax toàn SoC. Khi tăng clock phải cập nhật CLK_FREQ/divider và kiểm tra lại hệ thống.

## Power Analyzer — ước tính theo mô phỏng

Điều kiện: clock 50 MHz, junction temperature đặt **25 °C**, điện áp core danh định 1,2 V. VCD RTL chứa **32 frame loopback đã kiểm tra dữ liệu**, 8N1, mẫu 00/FF/55/A6, CPU giả lập polling qua Avalon, ba nguồn IRQ được enable. Divider 27 tương ứng baud thực 115.740,74, cấu hình danh định 115.200. TX nối RX trong testbench; không sử dụng tín hiệu đo thực từ kit.

| Chỉ số Power Analyzer | Ước tính |
|---|---:|
| Core dynamic của thiết kế IP độc lập, gồm clock/routing/RAM | **4.34 mW** |
| Core static của cả FPGA trong mô hình | **98.12 mW** |
| I/O thermal của cấu hình benchmark | **40.73 mW** |
| Total thermal của FPGA trong benchmark | **143.18 mW** |
| Power Estimation Confidence | **Low** |

**143,18 mW không phải công suất riêng của module UART và cũng không phải công suất cả board DE2-115.** Core static là chi phí nền của cả chip; I/O phụ thuộc cấu hình chân/nguồn của project benchmark. Virtual pins không mô hình đủ các chân UART vật lý của SoC thực tế.

Quartus lấy trực tiếp hoạt động từ mô phỏng cho 292/960 tín hiệu (30,4%), trong đó 251/323 tín hiệu thanh ghi (77,7%); 665 tín hiệu (69,3%) dùng vectorless estimation. Unknown trong VCD là 0%. Vì dữ liệu RTL không phủ đủ net sau tổng hợp, công cụ báo Low. **4,34 mW chỉ là ước tính tham khảo cho workload này**, chưa phải số đo phần cứng hoặc mức tiêu thụ lớn nhất. Để báo cáo power tin cậy hơn cần hoạt động netlist sau fit hoặc đo nguồn trên kit theo workload xác định.

## Cách chạy lại và báo cáo gốc

```bash
cd /home/kien/Documents/uart
bash UART/fpga/metrics/run.sh
```

Script chạy synthesis → fitter → timing → assembler → mô phỏng VCD → Power Analyzer → trích xuất báo cáo. Assembler chỉ phục vụ dữ liệu power của benchmark; không dùng SOF benchmark để nạp board.

Báo cáo gốc nằm tại `UART/fpga/build/metrics/output_files/`:

- `uart_metrics.fit.summary`, `uart_metrics.fit.rpt`: tổng tài nguyên và hierarchy.
- `uart_metrics.sta.summary`, `uart_metrics.sta.rpt`: timing đa corner.
- `critical_setup.rpt`, `critical_hold.rpt`, `fmax_detail.rpt`: đường tới hạn và Fmax.
- `uart_metrics.pow.summary`, `uart_metrics.pow.rpt`: power, điều kiện và confidence.

Log từng bước ở `UART/fpga/build/metrics/logs/`; `activity.vcd` và `activity_mapped.vcd` ở thư mục build. JSON đi kèm lưu SHA-256 các file RTL để đối chiếu phiên bản đã đo. Các kết quả trên là sau fitting, không lấy từ simulation đếm biến RTL.

Tài liệu tham khảo cách đưa VCD vào Power Analyzer: [Altera — Specifying Start and End Time / VCD input assignments](https://docs.altera.com/r/docs/683506/18.1/quartus-prime-standard-edition-user-guide-power-analysis-and-optimization/specifying-start-and-end-time-when-performing-signal-activity-calculations-using-the-limit-vcd-period-option?contentId=qRicMU8mFo5w2n8L1CaP0w).
