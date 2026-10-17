#!/usr/bin/env python3
"""Export concise Vietnamese report as vector PDF from extracted Quartus data."""
from pathlib import Path
from html import escape
import json, ctypes as C
from ctypes.util import find_library
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/reports'
d=json.loads((OUT/'UART_Quartus_metrics.json').read_text())
W,H=1600,1100
pages=[];parts=[]
def txt(x,y,s,size=22,bold=False,color='#233b52'):
 for i,line in enumerate(s.split('\n')):
  parts.append(f'<text x="{x}" y="{y+i*size*1.35}" font-size="{size}" fill="{color}" font-weight="{"bold" if bold else "normal"}">{escape(line)}</text>')
def rect(x,y,w,h,color):parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{color}"/>')
def begin(title,subtitle,num):
 global parts
 parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"><g font-family="DejaVu Sans, sans-serif">']
 rect(0,0,W,H,'#fff');rect(0,0,W,12,'#255b80')
 txt(55,68,title,32,True);txt(55,108,subtitle,20,color='#63768a')
 txt(55,1068,'Quartus Prime Lite 25.1std.0 • EP4CE115F29C7 • 17/10/2026',18,color='#63768a');txt(1460,1068,f'{num} / 2',18)
def table(y,widths,rows):
 for j,row in enumerate(rows):
  x=55
  for width,s in zip(widths,row):
   rect(x,y+j*40,width-2,38,'#e3edf6' if j==0 else ('#f2f5f8' if j%2 else '#fff'))
   txt(x+12,y+j*40+27,str(s),19,j==0)
   x+=width
 return y+len(rows)*40
def end():parts.append('</g></svg>');pages.append('\n'.join(parts))
begin('TÀI NGUYÊN VÀ TIMING — BRIDGE + UART','Top uart_avalon: Avalon–APB Bridge + APB Slave + Register File / FIFO + baud + TX/RX + IRQ',1)
metrics=[('Logic elements',f"{d['LE']}  /  114.480"),('LUT 4 đầu vào',str(d['LUT'])),('Flip-flop',str(d['FF'])),('RAM / DSP / PLL','2 M9K  /  0  /  0')]
for i,(k,v) in enumerate(metrics):
 x=55+375*i;rect(x,145,355,105,'#edf3f8');txt(x+18,180,k,21);txt(x+18,224,v,28,True)
rows=[['Khối (hàng cha gồm khối con)','LE','LUT','FF','RAM bit','M9K']]
for r in d['resources']:rows.append([r['label'],r['LE'],r['LUT'],r['FF'],r['memory_bits'],r['M9K']])
table(285,[690,150,150,150,190,165],rows)
txt(55,760,'LE có thể chứa đồng thời LUT và FF. Không cộng các hàng cha/con hoặc cộng LUT + FF để suy ra LE.',20)
txt(55,793,'Hierarchy có thể chia sẻ tài nguyên do tối ưu/packing; dùng hàng tổng để báo cáo toàn thiết kế.',20)
rect(55,825,1490,160,'#eef5ee')
txt(75,860,f"Clock 50 MHz  •  Fmax {d['Fmax_MHz']:.2f} MHz  •  Setup slack +{d['setup_slack_ns']:.3f} ns",27,True)
txt(75,905,f"Slow corner 1,2 V / 85 °C; hold nhỏ nhất qua 3 corner: +{d['worst_hold_slack_ns']:.3f} ns; TNS = 0.",21)
txt(75,945,'Không có đường clock/input/output chưa ràng buộc. Fmax là kết quả fit IP độc lập, khác baud UART.',21)
end()
begin('POWER VÀ ĐIỀU KIỆN ĐÁNH GIÁ','Power Analyzer: VCD RTL loopback 32 frame đã kiểm tra dữ liệu • 50 MHz • 8N1 • junction 25 °C',2)
p=d['power']
rows=[['Chỉ số','Ước tính','Phạm vi / ý nghĩa'],['Core dynamic',f"{p['core_dynamic_mW']:.2f} mW",'IP độc lập, gồm clock / routing / RAM'],['Core static',f"{p['device_core_static_mW']:.2f} mW",'Công suất nền của cả FPGA'],['I/O thermal',f"{p['io_mW']:.2f} mW",'Cấu hình I/O của benchmark'],['Total thermal',f"{p['device_total_mW']:.2f} mW",'Cả chip trong benchmark; không phải riêng UART'],['Confidence','LOW','Chưa đủ hoạt động netlist từ VCD RTL']]
table(155,[360,250,885],rows)
rect(55,430,1490,155,'#fff0d6')
txt(75,467,'Cách dùng số liệu power trong báo cáo',26,True)
txt(75,505,'Core dynamic 4,34 mW là ước tính tham khảo của workload đã mô phỏng.',23)
txt(75,542,'143,18 mW không phải công suất riêng UART, cũng không phải công suất cả board DE2-115.',22)
txt(55,635,'PHƯƠNG PHÁP',24,True)
txt(55,677,'• Tổng hợp và place-and-route top uart_avalon trên Cyclone IV E, seed 1; không gồm Nios V / RAM SoC.',21)
txt(55,716,'• 93 virtual pins cho biên IP, chỉ clk là pin vật lý. Bus Avalon không bị mô hình thành chân I/O ngoài chip.',21)
txt(55,755,'• VCD: TX nối RX; mẫu 00 / FF / 55 / A6; polling Avalon, IRQ enabled; divider 27 (~115.740,74 baud).',21)
txt(55,794,'• VCD cấp hoạt động cho 30,4% tín hiệu, 77,7% tín hiệu thanh ghi; phần còn lại chủ yếu vectorless.',21)
txt(55,833,'• Để tăng độ tin cậy: VCD netlist sau fit với workload xác định, hoặc đo nguồn phần cứng.',21)
txt(55,889,'CHẠY LẠI',24,True)
txt(55,928,'bash UART/fpga/metrics/run.sh',24)
txt(55,970,'Báo cáo chi tiết: docs/reports/UART_Quartus_metrics.md; raw reports: fpga/build/metrics/output_files/.',20)
end()
c=C.CDLL(find_library('cairo'));r=C.CDLL(find_library('rsvg-2'));g=C.CDLL(find_library('gobject-2.0'))
def bind(lib,n,args,ret=None):
 f=getattr(lib,n);f.argtypes=args;f.restype=ret;return f
ptr=C.c_void_p;D=C.c_double;I=C.c_int;S=C.c_char_p
surf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(OUT/'UART_Quartus_metrics.pdf').encode(),W,H)
ctx=bind(c,'cairo_create',[ptr],ptr)(surf)
load=bind(r,'rsvg_handle_new_from_data',[S,C.c_size_t,ptr],ptr)
render=bind(r,'rsvg_handle_render_cairo',[ptr,ptr],I)
for svg in pages:
 raw=svg.encode();handle=load(raw,len(raw),None);assert handle
 assert render(handle,ctx)
 bind(c,'cairo_show_page',[ptr])(ctx)
 bind(g,'g_object_unref',[ptr])(handle)
bind(c,'cairo_surface_finish',[ptr])(surf)
bind(c,'cairo_destroy',[ptr])(ctx);bind(c,'cairo_surface_destroy',[ptr])(surf)
print('Saved PDF:',OUT/'UART_Quartus_metrics.pdf')
