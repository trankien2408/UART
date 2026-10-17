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

put('<svg xmlns="http://www.w3.org/2000/svg" width="4200" height="1800" viewBox="0 0 4200 1800"><defs>')
for name,col in [('bus',B),('uart',U),('jtag',J),('irq',IRQ),('ctrl',CTRL),('gray',GRAY),('tick',TICK)]:
 put(f'<marker id="{name}" markerWidth="12" markerHeight="10" refX="10" refY="5" orient="auto-start-reverse" markerUnits="userSpaceOnUse"><path d="M0 0 L10 5 L0 10 Z" fill="{col}"/></marker>')
put('</defs><g font-family="Noto Sans, DejaVu Sans, sans-serif">')
rect(0,0,4200,1800,'#fff','#fff',0)
text(35,55,'HỆ THỐNG UART LẬP TRÌNH BAUD VÀ INTERRUPT — KIẾN TRÚC PHẦN CỨNG',34,weight='bold')
text(35,94,'Nios V/m → Avalon-MM interconnect → Avalon–APB Bridge → APB Slave → Register File / FIFO → UART TX, RX',23,color='#52687c')
# Two primary regions mirror the user's reference drawing.
rect(30,130,3080,1480,'#f5f6f8','#818b94',0)
text(55,171,'FPGA CYCLONE IV E (EP4CE115F29C7) — de2_115_uart_top',27,weight='bold')
rect(3170,130,1000,1480,'#f5f6f8','#818b94',0)
text(3195,171,'BOARD ESP32 & MÁY TÍNH',27,weight='bold')
rect(55,205,2750,1260,'#fff','#9daebc',0)
text(80,246,'SoC Platform Designer — uart_soc.qsys / uart_soc',26,weight='bold')
# Bus branches: same logical interconnect, no series peripherals.
rect(480,310,220,950,'#e0eafb','#7d9bbb',0)
text(590,365,'Avalon-MM\ninterconnect',26,anchor='middle',weight='bold')
text(590,483,'Giải mã địa chỉ\nPhân xử\nĐịnh tuyến',21,anchor='middle')
text(590,1120,'Yêu cầu →\n← Phản hồi',21,anchor='middle',color=B)
link([(700,340),(760,340)],B,True)
labelbox(760,285,550,115,'On-chip RAM • 128 KiB','0x0000_0000 • mã C, stack, buffer',fill='#fff1cb',size=25)
link([(700,430),(1370,430),(1370,340),(1430,340)],B,True)
labelbox(1430,285,550,115,'PIO control • 4 bit','0x0002_0010 • loopback / CTS / LED',fill='#fff1cb',size=25)
link([(700,455),(2020,455),(2020,340),(2080,340)],B,True)
labelbox(2080,285,550,115,'System ID','0x0002_0008 • kiểm tra đúng phần cứng',fill='#edf0e8',size=25)
# CPU: actual Avalon interfaces, unlike the example's AXI implementation.
rect(85,550,325,620,'#fff0d8','#c8a45d',0)
text(247,595,'CPU Nios V/m',27,anchor='middle',weight='bold')
text(247,632,'Firmware C: chat / ISR / baud',18,anchor='middle')
labelbox(105,685,285,110,'instruction_manager','Avalon-MM • đọc lệnh',fill='#dce9fc',size=21)
labelbox(105,870,285,110,'data_manager','Avalon-MM • load / store',fill='#dce9fc',size=21)
labelbox(105,1040,285,90,'Timer mtime','CPU timer • 0x0003_0000',fill='#fff8e6',size=21)
link([(390,740),(480,740)],B,True)
link([(390,925),(480,925)],B,True)
text(435,721,'Lệnh',17,anchor='middle',color=B)
text(435,905,'MMIO',17,anchor='middle',color=B)
# UART custom component, containing bridge + APB core.
rect(760,485,2010,790,'#fff0d8','#c8a45d',0)
text(780,524,'uart_avalon — Avalon-MM slave • base 0x0002_1000',25,weight='bold')
rect(1425,550,1320,700,'#fffaf0','#c7b58d',0)
text(1445,586,'UART_core = apb_uart',25,weight='bold')
# Avalon bridge internal functional stages reflect its actual RTL.
rect(790,620,290,590,'#e9e0f2','#a183b1',0)
text(935,660,'Avalon–APB\nBridge',27,anchor='middle',weight='bold')
labelbox(810,730,250,100,'Chốt yêu cầu','addr / data / write / strb',fill='#f8f2fb',size=21)
labelbox(810,860,250,150,'FSM','IDLE → SETUP\n→ ACCESS → RESPONSE\nACCESS chờ PREADY',fill='#f8f2fb',size=22)
labelbox(810,1040,250,100,'Trả phản hồi','rdata / valid / response',fill='#f8f2fb',size=21)
text(935,1180,'avalon_apb_bridge.v',18,anchor='middle',color='#52687c')
link([(700,800),(790,800)],B,True)
text(737,777,'MM',18,anchor='middle',color=B)
# Explicit APB signals, as in the sample; requests and responses distinct.
rect(1450,635,205,575,'#dce9fc','#7d9bbb',0)
text(1552,680,'APB Slave',26,anchor='middle',weight='bold')
text(1552,766,'Nhận pha\nSETUP / ACCESS\nPhát access\nChuyển địa chỉ,\ndữ liệu, strobe\nTrả ready / error',21,anchor='middle')
text(1552,1165,'apb_slave.v',19,anchor='middle',color='#52687c')
text(1260,622,'APB4 • địa chỉ byte',21,anchor='middle',weight='bold')
for i,name in enumerate(['PADDR[11:0]','PSEL','PENABLE','PWRITE','PWDATA[31:0]','PSTRB[3:0]','PRDATA[31:0]','PREADY','PSLVERR']):
 y=690+i*57
 link([(1080,y),(1450,y)] if i<6 else [(1450,y),(1080,y)],B,width=2)
 text(1265,y-12,name,21,anchor='middle')
# Register file includes both FIFO instances.
rect(1750,635,545,575,'#dce9fc','#7d9bbb',0)
text(2022,677,'Register File',27,anchor='middle',weight='bold')
text(1770,720,'Offset byte\n0x00  TX\n0x04  CFG\n0x08  CTRL\n0x0C  STT\n0x10  RX\n0x14  FIFO\n0x18  BAUD_SHADOW\n0x1C  BAUD_ACTIVE\n0x20  BAUD_CTRL\n0x24  INT_EN\n0x28  INT_ST',20)
labelbox(2050,740,220,110,'TX FIFO','16 × 8 bit',fill='#fff2cd',size=24)
labelbox(2050,970,220,110,'RX FIFO','16 × 9 bit\n8 data + parity',fill='#fff2cd',size=24)
text(2022,1177,'register_file.v + uart_fifo.v',19,anchor='middle',color='#52687c')
link([(1655,820),(1750,820)],B)
text(1702,752,'access\nwr / addr\ndata / strb',15,anchor='middle',color=B)
link([(1750,1040),(1655,1040)],B)
text(1702,1075,'rdata\nready\nerror',15,anchor='middle',color=B)
# Baud generator and TX/RX. All clocks are still the same 50 MHz clock.
labelbox(2350,625,360,105,'Baud generator','Divider runtime • ticks ×16',fill='#dcefe6',size=25)
link([(1950,635),(1950,605),(2515,605),(2515,625)],CTRL)
text(2160,595,'baud_div[15:0] / baud_apply',17,anchor='middle',color=CTRL)
labelbox(2350,800,360,120,'TX core','tx_topmodule\nController + datapath',fill='#dcefe6',size=26)
labelbox(2350,1030,360,120,'RX core','rx_topmodule\nController + datapath',fill='#dcefe6',size=26)
link([(2270,795),(2320,795),(2320,860),(2350,860)],B)
link([(2350,1090),(2315,1090),(2315,1025),(2270,1025)],B)
link([(2460,730),(2460,800)],TICK)
text(2472,770,'tick_tx',17,color=TICK)
link([(2680,730),(2730,730),(2730,990),(2550,990),(2550,1030)],TICK)
text(2570,979,'tick_rx',17,color=TICK)
text(2530,951,'TX: data / start → ; busy / done ←',16,anchor='middle',color=B)
text(2530,1195,'RX: data / done / parity_error → FIFO',16,anchor='middle',color=B)
# Top-level routing is outside the Qsys boundary.
rect(2840,690,235,555,'#fff1cf','#c9aa6a',0)
text(2957,731,'Logic top',25,anchor='middle',weight='bold')
text(2957,781,'GPIO routing\nLoopback / CTS',20,anchor='middle')
text(2957,932,'UART_TX\nGPIO[0] / AB22',21,anchor='middle',weight='bold')
text(2957,1150,'UART_RX\nGPIO[1] / AC15',21,anchor='middle',weight='bold')
link([(2710,860),(2840,860)],U)
text(2774,843,'tx',20,anchor='middle',color=U)
link([(2840,1090),(2710,1090)],U)
text(2774,1074,'rx',20,anchor='middle',color=U)
# External ESP32 board: chip pins are named from USB-UART perspective.
rect(3200,570,940,700,'#fff0d8','#c8a45d',0)
text(3225,613,'BOARD ESP32 — DÙNG CHIP USB-UART CÓ SẴN',25,weight='bold')
text(3225,651,'CPU ESP32 giữ reset (EN nối GND); không chạy firmware chuyển tiếp',19,color='#52687c')
labelbox(3235,815,215,90,'RXD','Đầu vào chip',fill='#dcefe6',size=25)
labelbox(3235,1045,215,90,'TXD','Đầu ra chip',fill='#dcefe6',size=25)
rect(3540,750,550,440,'#dcefe6','#84a78a',0)
text(3815,796,'CHIP USB-UART',28,anchor='middle',weight='bold')
labelbox(3570,830,490,85,'UART RX','Nhận dữ liệu nối tiếp từ FPGA',fill='#f3faf4',size=23)
labelbox(3570,1060,490,85,'UART TX','Phát dữ liệu nối tiếp đến FPGA',fill='#f3faf4',size=23)
text(3815,990,'USB ↔ bộ đệm ↔ UART',25,anchor='middle')
link([(3075,860),(3235,860)],U)
text(3155,835,'TX → RXD',17,anchor='middle',color=U)
link([(3450,860),(3570,860)],U)
link([(3570,1090),(3450,1090)],U)
link([(3235,1090),(3075,1090)],U)
text(3155,1065,'RX ← TXD',17,anchor='middle',color=U)
# Serial host and USB cable; no fake UART TX/RX pins on the PC.
labelbox(3540,1370,550,165,'PC • Serial terminal','picocom trong terminal VS Code\n/dev/ttyUSB* hoặc /dev/ttyACM*\nBaud / data / parity / stop khớp FPGA',fill='#fff2cd',size=26)
link([(3815,1190),(3815,1370)],J,True)
text(3837,1330,'USB',23,color=J)
text(3225,1228,'Tín hiệu UART 3,3 V • FPGA và ESP32 nối chung GND',20,color=U)
text(3210,1435,'PC gửi / nhận byte\nqua USB; chip tạo /\ngiải mã TXD, RXD.',21,color='#52687c')
# IRQ path across bottom of the SoC with a real mapper block.
labelbox(480,1330,300,100,'IRQ mapper','UART IRQ số 1',fill='#f7e0eb',stroke='#b9849e',size=25)
link([(2022,1210),(2022,1380),(780,1380)],IRQ,dash=True)
text(1420,1360,'irq: RX có dữ liệu / TX_DONE / RX overrun',22,anchor='middle',color=IRQ)
link([(480,1380),(247,1380),(247,1170)],IRQ,dash=True)
text(260,1325,'platform_irq_rx → ISR',19,color=IRQ)
# Exported PIO conduit to top-level routing.
link([(1705,285),(1705,265),(2957,265),(2957,690)],CTRL)
text(2650,293,'control[3:0] → logic top / LED',19,anchor='middle',color=CTRL)
# Top controls/clock; buses abstracted to prevent spaghetti.
labelbox(85,1490,480,95,'CLOCK_50 / KEY[0]','50 MHz • reset nhả sau 16 chu kỳ',fill='#f0f2f5',size=23)
text(620,1525,'Clock / reset chung: CPU, interconnect, RAM, bridge và UART.',22,color='#52687c')
text(620,1565,'PIO → logic top: [0] loopback; [1] bật CTS; [3:2] LEDG[1:0].',22,color=CTRL)
text(3240,450,'Chiều truyền qua UART\nFPGA TX → USB-UART RXD → PC\nPC → USB-UART TXD → FPGA RX',25,color=U)
# Compact footer documents abstraction choices and avoids copied incorrect assumptions.
text(40,1660,'AVALON-MM: address[11:0], read/write, writedata[31:0], byteenable[3:0] → bridge; readdata[31:0], waitrequest, valid, response[1:0] → interconnect.',20,color=B)
text(40,1703,'Sơ đồ chức năng: lược console JTAG / debug và dây CFG, trạng thái, clock/reset chi tiết; CTS/RTS có trong RTL, chế độ chat hiện tại không dùng bắt tay ngoài.',20,color='#52687c')
text(40,1746,'Baud mặc định 115200, có thể đổi bằng firmware. Nhãn RXD/TXD ở đây thuộc CHIP USB-UART; nhãn TX/RX in trên board ESP32 có thể thuộc CPU ESP32.',20,color='#52687c')
put('</g></svg>')
svg=ROOT/'Kien_truc_UART_SoC_APB_ESP32.svg';svg.write_text('\n'.join(parts))
# Vector PDF and 2x PNG through system librsvg/Cairo.
c=C.CDLL(find_library('cairo'));r=C.CDLL(find_library('rsvg-2'));g=C.CDLL(find_library('gobject-2.0'))
def bind(lib,n,args,ret=None):
 f=getattr(lib,n);f.argtypes=args;f.restype=ret;return f
ptr=C.c_void_p;D=C.c_double;I=C.c_int;S=C.c_char_p
load=bind(r,'rsvg_handle_new_from_file',[S,ptr],ptr);render=bind(r,'rsvg_handle_render_cairo',[ptr,ptr],I)
ctx_new=bind(c,'cairo_create',[ptr],ptr);finish=bind(c,'cairo_surface_finish',[ptr]);ctx_free=bind(c,'cairo_destroy',[ptr]);surf_free=bind(c,'cairo_surface_destroy',[ptr]);unref=bind(g,'g_object_unref',[ptr])
h=load(str(svg).encode(),None)
if not h:raise RuntimeError('SVG load failed')
surf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(svg.with_suffix('.pdf')).encode(),4200,1800)
ctx=ctx_new(surf);assert render(h,ctx);finish(surf);ctx_free(ctx);surf_free(surf)
surf=bind(c,'cairo_image_surface_create',[I,I,I],ptr)(0,8400,3600);ctx=ctx_new(surf)
bind(c,'cairo_scale',[ptr,D,D])(ctx,2,2);assert render(h,ctx)
assert bind(c,'cairo_surface_write_to_png',[ptr,S],I)(surf,str(svg.with_suffix('.png')).encode())==0
finish(surf);ctx_free(ctx);surf_free(surf);unref(h)
print('Generated system SVG / PDF / PNG:',svg.with_suffix(''))
