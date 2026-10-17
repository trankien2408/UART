#!/usr/bin/env python3
"""Overview checked against FPGA top, Qsys Tcl and current UART RTL/firmware."""
from pathlib import Path
from html import escape
import ctypes as C
from ctypes.util import find_library
ROOT=Path(__file__).resolve().parent
B='#245d85';U='#25805d';J='#8053a0';IRQ='#b74773';CTRL='#b17420';GRAY='#89929c';TICK='#13899a'
parts=[]
def put(s):parts.append(s)
def text(x,y,s,size=21,color='#172b43',anchor='start',weight='normal'):
 put(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">')
 for i,t in enumerate(s.split('\n')):put(f'<tspan x="{x}" dy="{0 if i==0 else size*1.28}">{escape(t)}</tspan>')
 put('</text>')
def rect(x,y,w,h,fill='#fff',stroke='#6f8ba1',r=12):
 put(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
def link(points,col=B,both=False,dash=False,arrow=True,width=3):
 ident={B:'bus',U:'uart',J:'jtag',IRQ:'irq',CTRL:'ctrl',GRAY:'gray',TICK:'tick'}[col]
 attr=f' marker-end="url(#{ident})"' if arrow else ''
 if both:attr+=f' marker-start="url(#{ident})"'
 if dash:attr+=' stroke-dasharray="9 6"'
 put('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="none" stroke="{col}" stroke-width="{width}" stroke-linejoin="round"{attr}/>')
def dot(x,y,col=B):put(f'<circle cx="{x}" cy="{y}" r="4.5" fill="{col}"/>')
def labelbox(x,y,w,h,title,detail='',fill='#fff',stroke='#6f8ba1',size=23):
 rect(x,y,w,h,fill,stroke)
 text(x+w/2,y+34,title,size,anchor='middle',weight='bold')
 if detail:text(x+w/2,y+66,detail,18,anchor='middle',color='#52687c')

put('<svg xmlns="http://www.w3.org/2000/svg" width="3200" height="1540" viewBox="0 0 3200 1540"><defs>')
for name,col in [('bus',B),('uart',U),('jtag',J),('irq',IRQ),('ctrl',CTRL),('gray',GRAY),('tick',TICK)]:
 put(f'<marker id="{name}" markerWidth="12" markerHeight="10" refX="10" refY="5" orient="auto-start-reverse" markerUnits="userSpaceOnUse"><path d="M0 0 L10 5 L0 10 Z" fill="{col}"/></marker>')
put('</defs><g font-family="Noto Sans, DejaVu Sans, sans-serif">')
rect(0,0,3200,1540,'#fff','#fff',0)
text(40,55,'KIẾN TRÚC HỆ THỐNG UART — NIOS V/m • AVALON-MM • APB',34,weight='bold')
text(40,95,'DE2-115 / Cyclone IV E EP4CE115F29C7 — sơ đồ các khối chức năng theo source hiện tại',22,color='#52687c')
rect(30,130,3135,1300,'#f7f8fa','#8c979e',0)
text(55,170,'de2_115_uart_top  /  FPGA',25,weight='bold')
rect(55,200,2850,1110,'#fff','#a0adbc',0)
text(80,240,'uart_soc  /  Platform Designer — uart_soc.qsys',25,weight='bold')
rect(1410,390,1450,775,'#fff2df','#d0a85a',0)
text(1435,425,'uart_avalon  •  base 0x0002_1000',25,weight='bold')
rect(1735,450,1100,690,'#fffaf1','#c6b184',0)
text(1760,486,'UART_core = apb_uart',25,weight='bold')
# CPU and shared bus architecture.
rect(90,470,330,470,'#fff0d8','#c6a76a',0)
text(255,512,'CPU Nios V/m',26,anchor='middle',weight='bold')
text(255,548,'Thực thi firmware C',21,anchor='middle')
labelbox(115,590,280,95,'instruction_manager','Đọc lệnh',fill='#dce9fc',size=21)
labelbox(115,740,280,95,'data_manager','Đọc / ghi MMIO',fill='#dce9fc',size=21)
link([(395,637),(545,637)],B,True)
text(465,617,'Lệnh',19,anchor='middle',color=B)
link([(395,787),(545,787)],B,True)
text(465,768,'Dữ liệu',19,anchor='middle',color=B)
rect(545,340,225,760,'#deebf8','#7e9bb8',0)
text(657,400,'Avalon-MM\ninterconnect',25,anchor='middle',weight='bold')
text(657,535,'Giải mã địa chỉ\nPhân xử truy cập\nĐịnh tuyến\nyêu cầu / phản hồi',20,anchor='middle')
# Parallel memory and peripheral branches.
link([(770,365),(855,365)],B,True)
labelbox(855,300,490,115,'On-chip RAM • 128 KiB','Mã C / stack / buffer  •  base 0x0000_0000',fill='#fff2ca',size=24)
link([(770,1000),(855,1000)],B,True)
labelbox(855,950,490,100,'PIO control • 4 bit','Base 0x0002_0010',fill='#fff2ca',size=24)
link([(770,1090),(815,1090),(815,1175),(855,1175)],B,True)
labelbox(855,1125,490,100,'System ID','Base 0x0002_0008',fill='#eff0e9',size=24)
# Custom bridge: distinct block, not an interconnect APB translator.
link([(770,690),(1440,690)],B,True)
text(1060,660,'Avalon-MM slave',23,anchor='middle',color=B)
text(1060,730,'address[11:0] • read / write\nwritedata[31:0] • byteenable[3:0]\nreaddata[31:0] • waitrequest\nreaddatavalid • writeresponsevalid • response',18,anchor='middle',color='#52687c')
rect(1440,530,255,510,'#e8dff1','#9f85b0',0)
text(1567,578,'Avalon–APB\nBridge',26,anchor='middle',weight='bold')
text(1567,690,'Chốt yêu cầu\nSETUP → ACCESS\nChờ PREADY\nTrả phản hồi',21,anchor='middle')
text(1567,970,'avalon_apb_bridge.v',17,anchor='middle',color='#52687c')
# APB buses simplified, named explicitly (correct widths).
link([(1695,740),(1770,740)],B,True)
text(1730,644,'APB4',20,anchor='middle',color=B)
# APB control endpoint and register file.
rect(1770,545,190,490,'#dce9fc','#7e9bb8',0)
text(1865,600,'APB Slave',25,anchor='middle',weight='bold')
text(1865,730,'Giải mã\ntruy cập\nđọc / ghi\nthanh ghi',21,anchor='middle')
link([(1960,740),(2010,740)],B,True)
rect(2010,545,325,490,'#dce9fc','#7e9bb8',0)
text(2172,580,'Register File',25,anchor='middle',weight='bold')
text(2030,621,'0x00  TX     0x04  CFG\n0x08  CTRL   0x0C  STT\n0x10  RX     0x14  FIFO\n0x18  BAUD_SHADOW\n0x1C  BAUD_ACTIVE\n0x20  BAUD_CTRL\n0x24  INT_EN\n0x28  INT_ST',18)
labelbox(2030,845,285,72,'TX FIFO','16 × 8 bit',fill='#fff1c8',size=21)
labelbox(2030,940,285,72,'RX FIFO','16 × (8 bit + parity)',fill='#fff1c8',size=21)
# Serializer / receiver and baud control.
labelbox(2450,545,340,115,'Baud generator','Divider lập trình được\nTạo tick ×16 cho TX / RX',fill='#ddf0e9',size=24)
link([(2335,590),(2450,590)],CTRL)
text(2392,560,'div / APPLY',16,anchor='middle',color=CTRL)
labelbox(2450,755,340,100,'TX core','Controller + datapath',fill='#ddf0e9',size=24)
labelbox(2450,940,340,100,'RX core','Controller + datapath',fill='#ddf0e9',size=24)
link([(2315,880),(2390,880),(2390,805),(2450,805)],B)
text(2380,862,'TX byte',17,anchor='middle',color=B)
link([(2450,990),(2315,990)],B)
text(2380,1024,'RX byte + parity',15,anchor='middle',color=B)
link([(2570,660),(2570,755)],TICK)
text(2582,713,'tick_tx',18,color=TICK)
link([(2750,660),(2820,660),(2820,905),(2630,905),(2630,940)],TICK)
text(2700,892,'tick_rx',18,color=TICK)
# Only physical UART signals leave the SoC to top routing.
link([(2790,805),(2940,805)],U)
text(2870,786,'TX',19,anchor='middle',color=U)
link([(2940,990),(2790,990)],U)
text(2870,1020,'RX',19,anchor='middle',color=U)
rect(2940,720,180,390,'#fff0d8','#c6a76a',0)
text(3030,763,'Logic top',23,anchor='middle',weight='bold')
text(3030,820,'UART_TX\nUART_RX\nCTS_N / RTS_N',17,anchor='middle')
text(3030,960,'GPIO\nLoopback\nChọn CTS',19,anchor='middle')
# IRQ is not a data path.
link([(2172,1035),(2172,1260),(255,1260),(255,940)],IRQ,dash=True)
text(1770,1242,'UART IRQ → IRQ mapper (IRQ 1) → CPU → ISR',22,anchor='middle',color=IRQ)
# PIO control to the top and LED.
link([(1345,1000),(1380,1000),(1380,1335),(3030,1335),(3030,1110)],CTRL)
text(1750,1363,'control[0]: loopback  •  control[1]: CTS  •  control[3:2]: LEDG[1:0]',21,color=CTRL)
# Clock/reset, broad distribution represented once.
labelbox(90,290,330,115,'Clock / reset','CLOCK_50: 50 MHz\nKEY[0] → reset đồng bộ nhả',fill='#f0f2f5',size=22)
text(430,1140,'Clock và reset phân phối\nđến CPU, RAM, interconnect,\nbridge và toàn bộ UART.',20,color='#52687c')
# APB signal legend separate from crowded wires.
text(1450,1080,'APB: PADDR[11:0], PSEL, PENABLE, PWRITE, PWDATA[31:0], PSTRB[3:0]',17,color=B)
text(1450,1110,'Phản hồi: PRDATA[31:0], PREADY, PSLVERR',17,color=B)
text(55,1473,'Xanh dương: bus / dữ liệu  •  Xanh lá: UART nối tiếp  •  Xanh ngọc: tick  •  Nét đứt hồng: interrupt',21,color='#52687c')
text(55,1510,'Lược phần nạp/debug và console JTAG; lược dây CFG / status / flow-control chi tiết. FIFO nằm trong Register File; các khối ngoại vi là nhánh song song của Avalon.',18,color='#52687c')
put('</g></svg>')
svg=ROOT/'Kien_truc_he_thong_UART_DE2_115.svg';svg.write_text('\n'.join(parts))
# Vector PDF and 2x PNG through system librsvg/Cairo.
c=C.CDLL(find_library('cairo'));r=C.CDLL(find_library('rsvg-2'));g=C.CDLL(find_library('gobject-2.0'))
def bind(lib,n,args,ret=None):
 f=getattr(lib,n);f.argtypes=args;f.restype=ret;return f
ptr=C.c_void_p;D=C.c_double;I=C.c_int;S=C.c_char_p
load=bind(r,'rsvg_handle_new_from_file',[S,ptr],ptr);render=bind(r,'rsvg_handle_render_cairo',[ptr,ptr],I)
ctx_new=bind(c,'cairo_create',[ptr],ptr);finish=bind(c,'cairo_surface_finish',[ptr]);ctx_free=bind(c,'cairo_destroy',[ptr]);surf_free=bind(c,'cairo_surface_destroy',[ptr]);unref=bind(g,'g_object_unref',[ptr])
h=load(str(svg).encode(),None)
if not h:raise RuntimeError('SVG load failed')
surf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(svg.with_suffix('.pdf')).encode(),3200,1540)
ctx=ctx_new(surf);assert render(h,ctx);finish(surf);ctx_free(ctx);surf_free(surf)
surf=bind(c,'cairo_image_surface_create',[I,I,I],ptr)(0,6400,3080);ctx=ctx_new(surf)
bind(c,'cairo_scale',[ptr,D,D])(ctx,2,2);assert render(h,ctx)
assert bind(c,'cairo_surface_write_to_png',[ptr,S],I)(surf,str(svg.with_suffix('.png')).encode())==0
finish(surf);ctx_free(ctx);surf_free(surf);unref(h)
print('Generated system SVG / PDF / PNG:',svg.with_suffix(''))
