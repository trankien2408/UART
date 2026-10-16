#!/usr/bin/env python3
"""Generate Vietnamese vector PDF slides with speaker notes using system Cairo/Pango libraries through ctypes."""
from pathlib import Path
import json, html
import ctypes as ct
from ctypes.util import find_library
C=ct.CDLL(find_library('cairo'))
P=ct.CDLL(find_library('pango-1.0'))
PC=ct.CDLL(find_library('pangocairo-1.0'))
G=ct.CDLL(find_library('gobject-2.0'))
def bind(lib,name,args,rest= None):
 f=getattr(lib,name);f.argtypes=args;f.restype=rest;return f
ptr=ct.c_void_p; D=ct.c_double; I=ct.c_int; S=ct.c_char_p
pdf_create=bind(C,'cairo_pdf_surface_create',[S,D,D],ptr)
create=bind(C,'cairo_create',[ptr],ptr)
color=bind(C,'cairo_set_source_rgb',[ptr,D,D,D])
rectangle=bind(C,'cairo_rectangle',[ptr,D,D,D,D])
fill=bind(C,'cairo_fill',[ptr]);move=bind(C,'cairo_move_to',[ptr,D,D])
line=bind(C,'cairo_line_to',[ptr,D,D]);stroke=bind(C,'cairo_stroke',[ptr]);lw=bind(C,'cairo_set_line_width',[ptr,D])
show_page=bind(C,'cairo_show_page',[ptr]);finish=bind(C,'cairo_surface_finish',[ptr])
metadata=bind(C,'cairo_pdf_surface_set_metadata',[ptr,I,S])
layout_new=bind(PC,'pango_cairo_create_layout',[ptr],ptr)
show_layout=bind(PC,'pango_cairo_show_layout',[ptr,ptr])
font_new=bind(P,'pango_font_description_from_string',[S],ptr)
font_size=bind(P,'pango_font_description_set_absolute_size',[ptr,D])
set_font=bind(P,'pango_layout_set_font_description',[ptr,ptr])
set_width=bind(P,'pango_layout_set_width',[ptr,I]);set_wrap=bind(P,'pango_layout_set_wrap',[ptr,I])
set_spacing=bind(P,'pango_layout_set_spacing',[ptr,I]);set_text=bind(P,'pango_layout_set_text',[ptr,S,I])
get_size=bind(P,'pango_layout_get_pixel_size',[ptr,ct.POINTER(I),ct.POINTER(I)])
unref=bind(G,'g_object_unref',[ptr]);font_free=bind(P,'pango_font_description_free',[ptr])
ROOT=Path(__file__).resolve().parent
slides=[]
def add(title, subtitle, bullets, note, source, code=None, rows=None, flow=None):
    slides.append(dict(title=title,subtitle=subtitle,bullets=bullets,note=note,source=source,code=code,rows=rows,flow=flow))
base=json.loads((ROOT/'slide_content_10.json').read_text())
slides=[]
add('Sơ đồ Nios V → bridge → UART_core', 'Bridge ở ngoài UART_core; các khối cùng dùng clock hệ thống 50 MHz',[],
'UART_core là tên nhóm để trình bày, tương ứng module dti_uart. Trong RTL, uart_avalon chứa bridge và dti_uart. Register_file chứa hai FIFO; baud_rate_gen cấp tick cho TX/RX. Mũi tên bus hai chiều gồm yêu cầu và phản hồi, không phải hai giao dịch đồng thời.',
'rtl/uart_avalon.v; rtl/dti_uart.v; rtl/register_file.v; fpga/scripts/create_system.tcl')
slides[-1]['system_diagram']=True
add('Vì sao cần Avalon–APB bridge?', 'Hai đầu dùng giao thức khác nhau, cần chuyển cách bắt tay giao dịch',
['Phía Nios V: yêu cầu đọc/ghi Avalon-MM đi qua interconnect đến UART.',
 'Phía UART_core: APB slave nhận SETUP/ACCESS và trả PREADY, PRDATA, PSLVERR.',
 'Bridge chốt yêu cầu Avalon, tạo giao dịch APB rồi chuyển phản hồi về CPU.',
 'Bridge là RTL phần cứng; không xử lý Enter, chuỗi ký tự hay waveform UART.'],
'Interconnect chọn ngoại vi theo địa chỉ; bridge chuyển giao thức; APB slave tiếp nhận giao dịch; register_file thực hiện tác động đọc/ghi. Nếu UART có giao diện Avalon trực tiếp thì không cần bridge APB này. Bản hiện tại giữ giao diện APB của UART theo thiết kế đề tài.',
'rtl/avalon_apb_bridge.v; rtl/apb_slave.v; rtl/uart_avalon.v')
add('Bridge ánh xạ tín hiệu như thế nào?', 'Dữ liệu được chốt; tín hiệu điều khiển được sinh theo FSM',[],
'Address ở cổng bridge là offset cục bộ 12 bit, không phải toàn bộ địa chỉ CPU. Khi đọc, bridge đặt PSTRB bằng 0. PREADY báo APB hoàn tất; nó không được nối thẳng vào waitrequest. Bridge nhận tối đa một yêu cầu đang xử lý, không hỗ trợ burst trong bản RTL này.',
'rtl/avalon_apb_bridge.v; fpga/ip/uart_avalon_hw.tcl',
rows=[['Phía Avalon-MM','Phía APB','Cách xử lý'],['av_address / av_writedata','PADDR / PWDATA','Chốt offset và dữ liệu ghi'],['av_write / av_byteenable','PWRITE / PSTRB','Chốt hướng và byte lane ghi'],['Yêu cầu được chấp nhận','PSEL / PENABLE','FSM sinh pha SETUP và ACCESS'],['av_readdata / av_response','PRDATA / PSLVERR','Trả dữ liệu đọc hoặc báo lỗi'],['waitrequest / response valid','PREADY','Chặn yêu cầu mới; trả phản hồi sau hoàn tất']])
add('FSM bridge: một yêu cầu đi qua 4 trạng thái', 'IDLE → SETUP → ACCESS → RESPONSE → IDLE',
['IDLE: sẵn sàng nhận Avalon; chốt địa chỉ, hướng, dữ liệu và byteenable.',
 'SETUP: PSEL = 1, PENABLE = 0; trình bày yêu cầu cho APB slave.',
 'ACCESS: PSEL = 1, PENABLE = 1; giữ yêu cầu đến khi PREADY = 1.',
 'RESPONSE: trả dữ liệu/trạng thái và bật response valid tương ứng đọc hoặc ghi.'],
'Khi bridge khác IDLE, waitrequest chặn yêu cầu Avalon mới. ACCESS có thể kéo dài; APB slave của project có một wait cycle cố định và có thể chờ thêm. Chỉ commit thanh ghi khi giao dịch hoàn tất. Reset đưa bridge về IDLE và hệ thống cũng reset APB slave.',
'rtl/avalon_apb_bridge.v: state; rtl/apb_slave.v: pready, access_o')
add('Ví dụ bridge khi CPU gửi hoặc nhận một byte', 'Hoàn tất giao dịch bus khác với hoàn tất frame UART',
['Gửi h: ghi 0x68 tại 0x21000 → offset TX 0x00; sau đó ghi START tại 0x21008.',
 'Mỗi lần ghi là một giao dịch Avalon → APB riêng; START thành công mới enqueue.',
 'Nhận: kiểm tra RX_DONE tại 0x2100C, rồi đọc 0x21010 để pop RX FIFO.',
 'PRDATA quay về CPU qua bridge; nếu PSLVERR = 1 thì phản hồi Avalon báo lỗi.'],
'Ghi START lúc FIFO đầy hoặc đọc RX lúc rỗng sẽ làm APB chờ, vì vậy driver kiểm tra trạng thái trước. Bridge không có timeout riêng; timeout C không thể giải cứu một truy cập bus đã bị giữ chờ. CPU chỉ kết luận TX phát hết khi đọc thấy TX_DONE, không dựa vào phản hồi ghi START.',
'firmware/dti_uart.c; rtl/register_file.v; rtl/avalon_apb_bridge.v')
bridge=slides
slides=base[:5]+bridge+base[5:]
assert len(slides)==15
slides[-1]['note']='Câu kết: “Firmware chạy trên Nios V, truy cập ngoại vi bằng MMIO qua Avalon; bridge chuyển sang APB; UART_core thực hiện truyền nhận.” Demo: gõ hello rồi Enter để chuyển dòng. UART_core trong hình tương ứng dti_uart. Bản 15 slide tổng hợp từ tài liệu trước và đối chiếu RTL bridge hiện tại.'

# Layout: 16:9, vector text, embedded font subsets, overflow checks.
W,H=960,540
BG=(0.96,0.97,0.99); INK=(0.09,0.15,0.24); MUTED=(0.35,0.42,0.51); TEAL=(0.0,0.43,0.46)
surface=pdf_create(str(ROOT/'Firmware_NiosV_Avalon_Bridge_15_slide.pdf').encode(),W,H)
metadata(surface,0,'Firmware C — Nios V, Avalon-MM và UART trên DE2-115'.encode())
metadata(surface,1,'Tài liệu kỹ thuật project UART'.encode())
ctx=create(surface)
def box(x,y,w,h,col):
 color(ctx,*col);rectangle(ctx,x,y,w,h);fill(ctx)
def txt(s,x,y,w,size=18,color=INK,bold=False,font='Noto Sans',limit=None):
 layout=layout_new(ctx)
 desc=font_new(f'{font} {"Bold " if bold else ""}{size}'.encode())
 font_size(desc,size*1024);set_font(layout,desc)
 set_width(layout,int(w*1024));set_wrap(layout,2)
 set_spacing(layout,3*1024);set_text(layout,s.encode(),-1)
 ww,hh=I(),I();get_size(layout,ct.byref(ww),ct.byref(hh));h=hh.value
 if limit is not None and h>limit: raise RuntimeError(f'Overflow {h}>{limit}: {s[:65]}')
 globals()['color'](ctx,*color);move(ctx,x,y);show_layout(ctx,layout)
 unref(layout);font_free(desc)
 return h
def arrow(x1,y1,x2,y2,both=False):
 import math
 color(ctx,*TEAL);lw(ctx,1.5);move(ctx,x1,y1);line(ctx,x2,y2);stroke(ctx)
 def head(x,y,a):
  move(ctx,x-6*math.cos(a-0.5),y-6*math.sin(a-0.5));line(ctx,x,y)
  line(ctx,x-6*math.cos(a+0.5),y-6*math.sin(a+0.5));stroke(ctx)
 a=math.atan2(y2-y1,x2-x1);head(x2,y2,a)
 if both:head(x1,y1,a+math.pi)
def node(label,x,y,w,h,sz=15):
 box(x,y,w,h,(1,1,1));box(x,y,3,h,TEAL)
 txt(label,x+10,y+10,w-18,sz,bold=True,limit=h-13)
def draw_system():
 # Main MMIO path; nested core boundary reflects actual RTL hierarchy.
 node('CPU\nNios V/m',38,200,110,72)
 node('Avalon-MM\ninterconnect',176,200,130,72,14)
 node('Avalon → APB\nbridge',334,200,145,72,14)
 arrow(148,236,176,236,True);arrow(306,236,334,236,True)
 txt('Avalon-MM',333,177,150,12,TEAL,True)
 box(510,142,412,253,(0.88,0.93,0.94))
 txt('UART_core  (= dti_uart)',526,151,380,18,TEAL,True)
 node('apb_slave',526,205,112,52,14)
 node('register_file\nCFG / STATUS + TX, RX FIFO',660,193,245,69,14)
 arrow(479,236,526,236,True);txt('APB',483,211,40,11,TEAL,True)
 arrow(638,236,660,236,True)
 node('baud_rate_gen',526,306,145,55,13)
 node('TX core\nRX core',796,294,109,79,15)
 arrow(671,322,796,322);txt('tick ×16',687,299,100,12,TEAL)
 arrow(843,262,843,294)
 txt('data / ctrl',847,271,70,10,MUTED)
 # RX data/status returns into registers/FIFO.
 color(ctx,*TEAL);lw(ctx,1.5);move(ctx,796,350);line(ctx,731,350);line(ctx,731,274);stroke(ctx)
 arrow(731,274,731,262)
 txt('RX data',681,367,100,11,MUTED)
 arrow(905,309,946,309);txt('TX',926,287,29,11,TEAL,True)
 arrow(946,352,905,352);txt('RX',926,360,29,11,TEAL,True)
 txt('Firmware C\nđang thực thi',38,285,125,13,MUTED)
 txt('Chọn đích\ntheo địa chỉ',176,285,130,13,MUTED)
 txt('Chuyển giao thức\nvà phản hồi',334,285,150,13,MUTED)
 txt('Bus hai chiều: yêu cầu + phản hồi. Hình lược bỏ dây clock/reset, CTS/RTS và các dây trạng thái chi tiết.',38,403,890,11,MUTED,limit=18)

for idx,s in enumerate(slides,1):
 box(0,0,W,H,BG);box(0,0,12,H,TEAL)
 txt('UART / DE2-115     •     FIRMWARE & BUS',38,19,820,11,TEAL,True)
 txt(s['title'],38,44,890,28,bold=True,limit=45)
 txt(s['subtitle'],38,91,884,15,MUTED,limit=45)
 y=143
 if s.get('system_diagram'):
  draw_system()
 elif s['rows']:
  rows=s['rows']; widths=[180,245,459] if len(rows[0])==3 else [280,604]
  rh=min(54,272/len(rows))
  for r,row in enumerate(rows):
   box(38,y,884,rh-2, TEAL if r==0 else ((1,1,1) if r%2 else (0.90,0.94,0.96)))
   x=38
   for val,ww in zip(row,widths):
    txt(val,x+10,y+3,ww-20,13 if r else 13,(1,1,1) if r==0 else INK,r==0,limit=rh-6)
    x+=ww
   y+=rh
 elif s['flow']:
  for r,row in enumerate(s['flow']):
   yy=146+r*83
   for j,label in enumerate(row):
    xx=38+j*304
    box(xx,yy,276,61,(1,1,1));box(xx,yy,5,61,TEAL)
    txt(label,xx+17,yy+15,248,17,bold=True,limit=45)
    if j<2: txt('→',xx+280,yy+16,24,22,TEAL,True)
   if r<2:
    color(ctx,*TEAL);lw(ctx,1.2)
    move(ctx,922,yy+30);line(ctx,932,yy+30);line(ctx,932,yy+72)
    line(ctx,26,yy+72);line(ctx,26,yy+113);line(ctx,36,yy+113);stroke(ctx)
    move(ctx,31,yy+109);line(ctx,36,yy+113);line(ctx,31,yy+117);stroke(ctx)
 else:
  bw=410 if s['code'] else 852
  for b in s['bullets']:
   txt('•',38,y,20,21,TEAL,True)
   hh=txt(b,64,y,bw,18 if s['code'] else 20,limit=79)
   y+=hh+18
  if y>417: raise RuntimeError(f'Body overflow slide {idx}: {y}')
  if s['code']:
   box(494,143,428,251,(0.09,0.15,0.24))
   txt('TRÍCH CODE C',510,156,394,11,(0.43,0.86,0.82),True)
   txt(s['code'],510,184,397,13.1,(0.94,0.97,0.99),font='Noto Sans Mono',limit=204)
 box(38,423,884,78,(0.88,0.93,0.94))
 txt('GỢI Ý THUYẾT TRÌNH',50,431,860,10,TEAL,True)
 txt(s['note'],50,448,856,12.0,limit=49)
 txt('Nguồn: '+s['source'],38,511,837,9,MUTED,limit=25)
 txt(f'{idx:02d} / {len(slides):02d}',877,512,60,10,MUTED)
 show_page(ctx)
finish(surface)
(ROOT/'slide_content_15.json').write_text(json.dumps(slides,ensure_ascii=False,indent=2))
md=['# Firmware C — nội dung và lời dẫn cho slide\n','Bản đối chiếu source ngày 15/10/2026.\n']
for i,s in enumerate(slides,1):
 md += [f'\n## Slide {i:02d}. {s["title"]}\n',s['subtitle']+'\n']
 md += ['- '+b for b in s['bullets']]
 if s.get('system_diagram'): md += ['\nCPU Nios V ↔ Avalon interconnect ↔ Avalon–APB bridge ↔ UART_core (dti_uart). UART_core gồm apb_slave, register_file chứa TX/RX FIFO, baud_rate_gen và TX/RX core.']
 if s['flow']: md += ['\n```text']+[' → '.join(r) for r in s['flow']]+['```']
 if s['rows']:
  md += ['\n|'+'|'.join(s['rows'][0])+'|','|'+'|'.join(['---']*len(s['rows'][0]))+'|']
  md += ['|'+'|'.join(r)+'|' for r in s['rows'][1:]]
 if s['code']: md+=['\n```c',s['code'],'```']
 md += ['\n**Gợi ý thuyết trình:** '+s['note'],'\n**Nguồn source:** '+s['source']]
(ROOT/'Loi_thuyet_trinh_15_slide.md').write_text('\n'.join(md)+'\n')
print(f'Generated {len(slides)} slides: {ROOT / "Firmware_NiosV_Avalon_Bridge_15_slide.pdf"}')
