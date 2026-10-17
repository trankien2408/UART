#!/usr/bin/env python3
"""Extract real fitted metrics; retain scope and estimation limitations."""
from pathlib import Path
import re, json, csv, hashlib, shutil
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent
BUILD=REPO/'fpga/build/metrics'
OUT=REPO/'docs/reports'
OUT.mkdir(parents=True,exist_ok=True)
def read(name):return (BUILD/'output_files'/name).read_text(errors='replace')
fit=read('uart_metrics.fit.rpt'); sta=read('uart_metrics.sta.rpt'); power=read('uart_metrics.pow.rpt')
summary=read('uart_metrics.fit.summary'); ps=read('uart_metrics.pow.summary'); ts=read('uart_metrics.sta.summary')
def number(s,pattern):return float(re.search(pattern,s).group(1).replace(',',''))
le=int(number(summary,r'Total logic elements : ([\d,]+)'))
lut=int(number(summary,r'Total combinational functions : ([\d,]+)'))
ff=int(number(summary,r'Total registers : ([\d,]+)'))
fmax=number(read('fmax_detail.rpt'),r';\s*([\d.]+) MHz\s*;')
setup=number(ts,r"Slow 1200mV 85C Model Setup 'clk'\s*Slack : ([\d.-]+)")
holds=[float(x) for x in re.findall(r"Model Hold 'clk'\s*Slack : ([\d.-]+)",ts)]
resources=[]
for line in fit[fit.index('; Fitter Resource Utilization by Entity'):].splitlines():
 if line.startswith('Note:'):break
 if not line.startswith(';'):continue
 f=[v.strip() for v in line.split(';')][1:-1]
 if len(f)<16 or not f[1][:1].isdigit():continue
 def n(i):return int(f[i].split()[0])
 resources.append(dict(name=f[14],entity=f[15],LE=n(1),LUT=n(11)+n(13),FF=n(2),memory_bits=n(4),M9K=n(5)))
selected=[resources[0]]
for suffix in ['avalon_apb_bridge:bridge','apb_uart:uart','apb_slave:u_apb','register_file:u_registers','uart_fifo:tx_fifo','uart_fifo:rx_fifo','baud_rate_gen:u_baud','tx_topmodule:u_tx','rx_topmodule:u_rx']:
 selected.append(next(r for r in resources if r['name'].endswith('|'+suffix)))
labels=['Tổng bridge + UART','Avalon–APB Bridge','UART core (bao gồm các khối dưới)','APB Slave','Register File (bao gồm 2 FIFO)','TX FIFO','RX FIFO','Baud generator','TX core','RX core']
for r,label in zip(selected,labels):r['label']=label
powvals={key:number(ps,pattern) for key,pattern in {
 'core_dynamic_mW':r'Core Dynamic Thermal Power Dissipation : ([\d.]+)',
 'device_core_static_mW':r'Core Static Thermal Power Dissipation : ([\d.]+)',
 'io_mW':r'I/O Thermal Power Dissipation : ([\d.]+)',
 'device_total_mW':r'Total Thermal Power Dissipation : ([\d.]+)'}.items()}
hashes={str(p.relative_to(REPO)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((REPO/'rtl').rglob('*.v'))}
data=dict(device='EP4CE115F29C7',tool='Quartus Prime Lite 25.1std.0',top='uart_avalon',scope='Standalone Avalon–APB bridge + full UART; no CPU/interconnect/system RAM',clock_MHz=50,seed=1,virtual_pins=93,LE=le,LUT=lut,FF=ff,Fmax_MHz=fmax,setup_slack_ns=setup,worst_hold_slack_ns=min(holds),power=powvals,power_confidence='Low: user provided insufficient toggle rate data',resources=selected,rtl_sha256=hashes)
(OUT/'UART_Quartus_metrics.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
with (OUT/'UART_Quartus_resources.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['Block','LE','LUT','FF','Memory bits','M9K'])
 for r in selected:w.writerow([r['label'],r['LE'],r['LUT'],r['FF'],r['memory_bits'],r['M9K']])
rows='\n'.join(f"| {r['label']} | {r['LE']} | {r['LUT']} | {r['FF']} | {r['memory_bits']} | {r['M9K']} |" for r in selected)
md=f'''# Kết quả Quartus: Avalon–APB Bridge + UART

Ngày chạy: 17/10/2026. Công cụ: Quartus Prime Lite 25.1std.0, timing/power models Final.

## Phạm vi và điều kiện

Top tổng hợp: `rtl/uart_avalon.v`, gồm `avalon_apb_bridge` và `apb_uart`: APB Slave, Register File, TX/RX FIFO, baud generator, TX/RX core, IRQ và logic tích hợp. Không bao gồm CPU Nios V, Avalon interconnect, RAM hệ thống, PIO, console hay ESP32.

Target: Cyclone IV E **EP4CE115F29C7**, seed 1, clock **50 MHz** (20 ns). Đây là phép fit độc lập cho IP, không phải số liệu của toàn bộ SoC. 93 tín hiệu biên là virtual pins; chỉ clock là chân vật lý Y2. Cách này tránh gán bus Avalon nội bộ thành hàng chục chân I/O ngoài chip. Không thay RTL và project nạp board chính.

## Tài nguyên sau Fitter

| Chỉ số | Kết quả |
|---|---:|
| Logic elements (LE) | **{le} / 114.480 ({le/114480*100:.3f}%)** |
| LUT / total combinational functions | **{lut}** |
| Flip-flop / dedicated logic registers | **{ff}** |
| Bộ nhớ hữu ích | **272 bit** |
| M9K | **2 / 432** |
| DSP / PLL | **0 / 0** |

Cyclone IV E dùng LE với LUT 4 đầu vào. LUT và FF có thể cùng nằm trong một LE, nên LE không bằng LUT + FF. Các carry/arithmetic resource đã được Quartus tính theo cách ánh xạ của thiết bị.

| Khối | LE | LUT | FF | Memory bit | M9K |
|---|---:|---:|---:|---:|---:|
{rows}

Các hàng cha bao gồm khối con, không cộng tất cả hàng. Số LE/LUT theo hierarchy có thể chia sẻ hoặc bị quy thuộc ở nhiều mức do tối ưu/packing qua ranh giới module; lấy hàng tổng làm kết quả thiết bị. LUT = LUT-only LCs + LUT/Register LCs. FF lấy cột Dedicated Logic Registers, không đếm lại bộ nhớ M9K thành FF.

FIFO TX là 16 × 8 = 128 bit, FIFO RX là 16 × 9 = 144 bit. Mỗi FIFO dùng một M9K; 272 bit là dung lượng hữu ích, còn dung lượng vật lý 2 M9K là 18.432 bit.

## Timing sau place-and-route

| Chỉ số | Kết quả |
|---|---:|
| Clock đang ràng buộc | **50 MHz** |
| Fmax / Restricted Fmax, slow 1,2 V 85 °C | **{fmax:.2f} MHz** |
| Setup slack, slow 1,2 V 85 °C | **+{setup:.3f} ns** |
| Hold slack nhỏ nhất qua 3 corner | **+{min(holds):.3f} ns** |
| Setup/Hold TNS | **0 ns** |
| Unconstrained clocks / input paths / output paths | **0 / 0 / 0** |

Đường setup chậm nhất: `apb_uart:uart|apb_slave:u_apb|paddr_o[6]` → `avalon_apb_bridge:bridge|av_readdata[1]`, data delay 9,771 ns, 8 logic levels. Đường này đi qua logic giải mã/đọc thanh ghi và phản hồi APB về bridge.

Avalon đầu vào/đầu ra được mô hình đồng bộ cùng clock, external delay 0 ns để đặc trưng IP. Reset, RX và CTS là bất đồng bộ nên được loại khỏi timing biên; đầu ra UART không có clock nhận đồng bộ. Các đường đồng bộ bên trong vẫn được kiểm tra. Fmax ở đây là khả năng timing của IP trong lần fit này; không phải baud UART và không phải Fmax toàn SoC. Khi tăng clock phải cập nhật CLK_FREQ/divider và kiểm tra lại hệ thống.

## Power Analyzer — ước tính theo mô phỏng

Điều kiện: clock 50 MHz, junction temperature đặt **25 °C**, điện áp core danh định 1,2 V. VCD RTL chứa **32 frame loopback đã kiểm tra dữ liệu**, 8N1, mẫu 00/FF/55/A6, CPU giả lập polling qua Avalon, ba nguồn IRQ được enable. Divider 27 tương ứng baud thực 115.740,74, cấu hình danh định 115.200. TX nối RX trong testbench; không sử dụng tín hiệu đo thực từ kit.

| Chỉ số Power Analyzer | Ước tính |
|---|---:|
| Core dynamic của thiết kế IP độc lập, gồm clock/routing/RAM | **{powvals['core_dynamic_mW']:.2f} mW** |
| Core static của cả FPGA trong mô hình | **{powvals['device_core_static_mW']:.2f} mW** |
| I/O thermal của cấu hình benchmark | **{powvals['io_mW']:.2f} mW** |
| Total thermal của FPGA trong benchmark | **{powvals['device_total_mW']:.2f} mW** |
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
'''
(OUT/'UART_Quartus_metrics.md').write_text(md)
print(f'Saved report: {OUT}/UART_Quartus_metrics.md')
