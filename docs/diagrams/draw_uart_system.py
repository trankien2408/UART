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
put('<svg xmlns="http://www.w3.org/2000/svg" width="3050" height="1580" viewBox="0 0 3050 1580"><defs>')
for name,col in [('bus',B),('uart',U),('jtag',J),('irq',IRQ),('ctrl',CTRL),('gray',GRAY),('tick',TICK)]:
 put(f'<marker id="{name}" markerWidth="12" markerHeight="10" refX="10" refY="5" orient="auto-start-reverse" markerUnits="userSpaceOnUse"><path d="M0 0 L10 5 L0 10 Z" fill="{col}"/></marker>')
put('</defs><g font-family="Noto Sans, DejaVu Sans, sans-serif">')
rect(0,0,3050,1580,'#fff','#fff',0)
text(45,55,'HỆ THỐNG UART TRÊN DE2-115 — DATAFLOW VÀ ĐƯỜNG ĐIỀU KHIỂN',35,weight='bold')
text(45,98,'Bám source hiện tại: Nios V/m + Avalon-MM + Avalon–APB bridge + UART FIFO, baud runtime và interrupt',23,color='#52687c')
# Architectural hierarchy, not a serial data chain.
rect(650,170,1950,1250,'#f7faff','#6688a5',24)
text(680,208,'FPGA CYCLONE IV E  •  EP4CE115  •  DE2-115',26,weight='bold')
rect(680,225,1890,1150,'#fff','#9aaec0',18)
text(705,263,'de2_115_uart_top  —  bao hệ thống, reset và logic chọn đường UART',24,weight='bold')
rect(730,290,1700,940,'#f5f8fc','#a7b9c9',16)
text(755,326,'uart_soc / Platform Designer (Qsys)',25,weight='bold')
# UART component and nested APB core.
rect(1740,340,650,830,'#fff8f7','#c78880',15)
text(1760,371,'Component uart_avalon  •  base 0x21000',23,weight='bold')
rect(1760,510,610,640,'#f9fcff','#8cabc1',12)
text(1780,538,'UART_core = apb_uart',23,weight='bold')
# Draw interconnect and transport wiring before nodes.
# Host USB and JTAG hardware transport.
link([(310,405),(325,405),(325,450),(340,450)],J,True)
text(265,373,'USB',19,color=J)
link([(600,450),(710,450),(710,385),(790,385)],J,True)
text(626,432,'JTAG',20,color=J)
link([(1060,385),(1090,385),(1090,320),(1700,320),(1700,520),(1530,520),(1530,540)],J,True)
text(1430,307,'JTAG',18,color=J)
# Download/debug path to CPU is separate from console MMIO.
link([(930,430),(930,530)],J,True,True,width=2.5)
text(946,472,'ELF / debug',17,color=J)
# CPU instruction/data and each Avalon slave branch.
link([(1060,600),(1160,600)],B,True)
text(1080,580,'MMIO',17,color=B)
for cy in [420,590,760,930]:link([(1290,cy),(1380,cy)],B,True)
# UART MMIO travels around other slave blocks, never through them.
link([(1290,1060),(1690,1060),(1690,432),(1800,432)],B,True)
text(1698,495,'Avalon-MM',17,color=B)
# Bridge, APB and register interface.
link([(2075,475),(2075,500),(2085,500),(2085,550)],B,True)
text(2104,504,'APB4',20,color=B)
link([(2085,615),(2085,630)],B,True)
# Register control of baud and FIFO serial data paths.
link([(1840,697),(1780,697),(1780,930),(1820,930)],CTRL)
text(1786,861,'div / APPLY',17,color=CTRL)
link([(1955,810),(1955,845),(2215,845),(2215,880)],B)
text(2030,831,'TX byte',17,color=B)
link([(2100,1060),(2070,1060),(2070,830),(2215,830),(2215,810)],B)
text(2080,1002,'RX byte + parity',16,color=B)
# Separate generator ports with the same active divider.
link([(2020,910),(2050,910),(2100,910)],TICK)
text(2028,893,'tick_tx',16,color=TICK)
link([(2020,945),(2040,945),(2040,1080),(2100,1080)],TICK)
text(1970,1109,'tick_rx',17,color=TICK)
# Serial pins through board top routing (green = UART serial path).
link([(2330,925),(2450,925)],U)
text(2353,910,'TX',19,color=U)
link([(2450,1065),(2330,1065)],U)
text(2353,1050,'RX',19,color=U)
link([(2550,930),(2620,930),(2620,980),(2700,980)],U)
text(2604,910,'UART_TX',18,color=U)
link([(2700,1030),(2640,1030),(2640,1040),(2550,1040)],U)
text(2608,1075,'UART_RX',18,color=U)
link([(2850,770),(2850,950)],J,True)
text(2870,865,'USB',22,color=J)
# Top PIO bundle; split is explicitly labelled by bit lanes.
link([(1680,760),(1710,760),(1710,1200),(2500,1200),(2500,1100)],CTRL)
dot(2500,1200,CTRL)
text(1740,1187,'PIO control[3:0] → top',19,color=CTRL)
text(2350,1174,'[1:0]: loopback / CTS',17,color=CTRL)
link([(2500,1200),(2580,1200),(2580,1275),(2700,1275)],CTRL)
text(2600,1254,'[3:2]',18,color=CTRL)
# IRQ mapper and active UART interrupt. No data bytes travel on this line.
link([(1820,724),(1725,724),(1725,1160),(945,1160),(945,1070)],IRQ,False,True)
text(1130,1144,'UART IRQ = 1  •  RX / TX_DONE / overrun',21,color=IRQ)
link([(945,970),(945,690)],IRQ,False,True)
text(959,808,'Ngắt CPU',19,color=IRQ)
# JTAG IRQ remains connected but console disables it in current firmware.
link([(1530,640),(1530,662),(1340,662),(1340,1100),(1030,1100),(1030,1070)],GRAY,False,True,width=2)
text(1080,1123,'JTAG IRQ = 0: đã nối, console đang tắt',17,color=GRAY)
# All modules share top clock/reset; distribution abstracted at Qsys boundary.
link([(2330,275),(2330,290)],GRAY,arrow=True,width=2)
# Overlay blocks on wires.
labelbox(35,340,275,130,'PC • Terminal 1','juart-terminal\nUSB/JTAG',fill='#f8e0df')
labelbox(340,400,260,110,'USB-Blaster','Trên board DE2-115',fill='#ece1f6',stroke='#9479ad')
labelbox(790,340,270,90,'JTAG FPGA','Hub / truy cập debug',fill='#ece1f6',stroke='#9479ad',size=22)
rect(800,530,260,160,'#e1eafb','#7997bb')
text(930,567,'CPU Nios V/m',25,anchor='middle',weight='bold')
text(930,599,'Thực thi firmware C',20,anchor='middle')
text(930,625,'Chat • ISR • :baud',17,anchor='middle',color='#52687c')
rect(820,645,220,31,'#f7f1dd','#c3ad69',5);text(930,667,'Timer mtime của CPU',16,anchor='middle')
rect(1160,380,130,710,'#e3eff8','#7498b2')
text(1225,470,'Avalon-MM\ninterconnect',19,anchor='middle',weight='bold')
text(1225,814,'Giải mã\nđịa chỉ\nvà định\ntuyến',18,anchor='middle',color='#52687c')
labelbox(1380,370,300,100,'RAM on-chip 128 KiB','Mã C, stack, buffer\nbase 0x00000',fill='#fff1c8',stroke='#bfab62')
labelbox(1380,540,300,100,'IP JTAG UART','Console polling\nbase 0x20000',fill='#e1f0de',stroke='#81a77c')
labelbox(1380,710,300,100,'PIO control 4 bit','Loopback / CTS / LED\nbase 0x20010',fill='#fff0d4',stroke='#c7a367')
labelbox(1380,880,300,100,'System ID','Kiểm tra phần cứng\nbase 0x20008',fill='#f2f0e6',stroke='#a7a08a')
labelbox(1800,390,550,85,'Avalon–APB Bridge','Chốt yêu cầu → APB → trả phản hồi',fill='#ecdff2',stroke='#a282af')
labelbox(1820,550,530,65,'APB Slave','',fill='#e4ecfa',stroke='#829dbc')
rect(1820,630,530,210,'#e4ecfa','#829dbc')
text(2085,662,'Register File',25,anchor='middle',weight='bold')
rect(1840,675,490,45,'#f9fbff','#a7b7ca',6)
text(2085,705,'CFG • BAUD • IRQ • STATUS',20,anchor='middle')
labelbox(1840,740,230,70,'TX FIFO','16 byte',fill='#fff0ce',stroke='#b49d62',size=21)
labelbox(2100,740,230,70,'RX FIFO','16 byte + parity',fill='#fff0ce',stroke='#b49d62',size=21)
labelbox(1820,880,200,95,'Baud generator','Divider runtime\ntick ×16',fill='#dff1ee',stroke='#7aa9a1',size=20)
labelbox(2100,880,230,85,'TX core','Controller + datapath',fill='#f1f3f5',stroke='#8b9aa4',size=23)
labelbox(2100,1020,230,85,'RX core','Controller + datapath',fill='#f1f3f5',stroke='#8b9aa4',size=23)
rect(2450,820,100,280,'#fff0d4','#c7a367',8)
text(2500,858,'Logic\ntop',19,anchor='middle',weight='bold')
text(2500,980,'GPIO\nrouting\nloopback\nCTS',15,anchor='middle')
labelbox(2700,650,300,120,'PC • Terminal 2','picocom\nBaud khớp UART FPGA',fill='#fff1c8',stroke='#bfab62')
labelbox(2700,950,300,110,'Chip USB-UART','Trên board ESP32\nCPU ESP32 không chuyển tiếp',fill='#e1f0de',stroke='#81a77c',size=24)
labelbox(2700,1230,300,90,'LEDG[1:0]','Ready / error',fill='#fff0d4',stroke='#c7a367')
labelbox(820,970,250,100,'IRQ mapper','UART 1 / JTAG 0',fill='#f8e0ed',stroke='#b9849e',size=23)
rect(1780,232,550,43,'#f1f3f5','#a6afb7',6)
text(2055,260,'CLOCK_50 / KEY0 → clock và reset SoC',19,anchor='middle')
# Explanatory labels stay outside data wires.
text(755,1269,'Top giữ reset khi bật nguồn; control[0] chọn loopback, control[1] cho CTS, control[3:2] điều khiển LED.',18,color='#52687c')
text(755,1305,'Trong chat: UART ngoài, CTS ngoài tắt; ESP32 chỉ dùng chip USB-UART, nối TX/RX và GND chung ở mức 3,3 V.',18,color='#52687c')
text(45,568,'Một cáp JTAG phục vụ:\n• cấu hình SOF\n• nạp/debug ELF\n• dữ liệu terminal JTAG',20,color='#52687c')
# Legend and implementation notes, unambiguous abstract edges.
for x,col,label,dash in [(45,B,'Avalon / APB: yêu cầu + phản hồi',False),(765,U,'UART TX/RX: dữ liệu nối tiếp',False),(1455,J,'USB / JTAG',False),(1930,IRQ,'IRQ (chỉ thông báo)',True)]:
 link([(x,1470),(x+70,1470)],col,dash=dash);text(x+86,1477,label,20,color=col)
text(45,1520,'Hai terminal chạy trên cùng một PC. Hình gộp đường instruction/data và lược dây cấu hình/trạng thái, CTS/RTS chi tiết; giao cắt không chấm là không nối.',19,color='#52687c')
text(45,1553,'Đối chiếu: de2_115_uart_top.v • create_system.tcl • uart_avalon.v • apb_uart.v • main.c • uart_irq.c. Baud RTL hiện dùng chung divider cho tick_tx/tick_rx.',18,color='#52687c')
put('</g></svg>')
svg=ROOT/'He_thong_UART_DE2_115_dataflow.svg';svg.write_text('\n'.join(parts))
# Vector PDF and 2x PNG through system librsvg/Cairo.
c=C.CDLL(find_library('cairo'));r=C.CDLL(find_library('rsvg-2'));g=C.CDLL(find_library('gobject-2.0'))
def bind(lib,n,args,ret=None):
 f=getattr(lib,n);f.argtypes=args;f.restype=ret;return f
ptr=C.c_void_p;D=C.c_double;I=C.c_int;S=C.c_char_p
load=bind(r,'rsvg_handle_new_from_file',[S,ptr],ptr);render=bind(r,'rsvg_handle_render_cairo',[ptr,ptr],I)
ctx_new=bind(c,'cairo_create',[ptr],ptr);finish=bind(c,'cairo_surface_finish',[ptr]);ctx_free=bind(c,'cairo_destroy',[ptr]);surf_free=bind(c,'cairo_surface_destroy',[ptr]);unref=bind(g,'g_object_unref',[ptr])
h=load(str(svg).encode(),None)
if not h:raise RuntimeError('SVG load failed')
surf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(svg.with_suffix('.pdf')).encode(),3050,1580)
ctx=ctx_new(surf);assert render(h,ctx);finish(surf);ctx_free(ctx);surf_free(surf)
surf=bind(c,'cairo_image_surface_create',[I,I,I],ptr)(0,6100,3160);ctx=ctx_new(surf)
bind(c,'cairo_scale',[ptr,D,D])(ctx,2,2);assert render(h,ctx)
assert bind(c,'cairo_surface_write_to_png',[ptr,S],I)(surf,str(svg.with_suffix('.png')).encode())==0
finish(surf);ctx_free(ctx);surf_free(surf);unref(h)
print('Generated system SVG / PDF / PNG:',svg.with_suffix(''))
