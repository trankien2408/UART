#!/usr/bin/env python3
"""Code-native SVG schematic matching rtl/baud_rate_gen.v; render with system librsvg/Cairo."""
from pathlib import Path
from html import escape
import ctypes as C
from ctypes.util import find_library
ROOT=Path(__file__).resolve().parent
parts=[]
def put(s):parts.append(s)
def text(x,y,s,size=19,color='#172b43',anchor='start',weight='normal'):
    lines=s.split('\n')
    put(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">')
    for i,v in enumerate(lines):put(f'<tspan x="{x}" dy="{0 if i==0 else size*1.3}">{escape(v)}</tspan>')
    put('</text>')
def rect(x,y,w,h,fill,stroke='#577084',r=0):
    put(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
def wire(points,color='#243d53',arrow=True,width=2.5):
    pts=' '.join(f'{x},{y}' for x,y in points)
    mark={'#243d53':'data','#16718a':'control','#c34848':'clock','#8056a5':'reset'}[color]
    put(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"'+(f' marker-end="url(#{mark})"' if arrow else '')+'/>')
def dot(x,y,color='#243d53'):
    put(f'<circle cx="{x}" cy="{y}" r="4" fill="{color}"/>')
def slash(x,y,label):
    wire([(x-6,y+10),(x+6,y-10)],arrow=False)
    text(x+10,y-12,label,15)
def gate_or(x,y):
    # ANSI OR: concave input edge and pointed output edge.
    put(f'<path d="M{x},{y} Q{x+22},{y+30} {x},{y+60} Q{x+65},{y+60} {x+100},{y+30} Q{x+65},{y} {x},{y} Z" fill="#deeedc" stroke="#6c9a69" stroke-width="2.5"/>')
def gate_and(x,y):
    # ANSI AND: flat input edge, semicircular output. Lower input inverted.
    put(f'<path d="M{x},{y} H{x+60} A30,30 0 0 1 {x+60},{y+60} H{x} Z" fill="#deeedc" stroke="#6c9a69" stroke-width="2.5"/>')
    put(f'<circle cx="{x-5}" cy="{y+45}" r="5" fill="white" stroke="#6c9a69" stroke-width="2.5"/>')
def lane(name,origin):
    # Coordinates below are local to the lane; clock/reset and divider taps are shared.
    put(f'<g transform="translate(0,{origin})">')
    text(300,-20,f'NHÁNH {name.upper()}: counter + flip-flop riêng',26,weight='bold')
    # Divider threshold path.
    wire([(180,90),(1130,90),(1130,50),(1180,50)])
    dot(180,90);slash(1110,90,'16')
    rect(1180,20,170,60,'#e0eef8')
    text(1265,58,'divider_i − 1',20,anchor='middle')
    wire([(1350,50),(1380,50),(1380,100),(1350,100),(1350,120)])
    # Count increment and data mux path.
    wire([(1020,165),(1080,165),(1080,40),(932,40)])
    dot(1080,165);wire([(1080,165),(1260,165)])
    slash(1190,165,'16');text(1100,143,f'cnt_{name}[15:0]',20)
    put('<circle cx="900" cy="40" r="32" fill="#deeedc" stroke="#6c9a69" stroke-width="2.5"/>')
    text(900,48,'+1',23,anchor='middle',weight='bold')
    wire([(868,40),(575,40),(575,130),(650,130)])
    text(585,112,'+1',17)
    wire([(580,210),(650,210)]);text(565,240,"16'd0",20)
    put('<polygon points="650,100 750,145 750,195 650,240" fill="#f6d8d4" stroke="#c27770" stroke-width="2.5"/>')
    text(666,139,'0',22,weight='bold');text(666,219,'1',22,weight='bold')
    text(696,179,'MUX',18,anchor='middle',weight='bold')
    wire([(750,165),(850,165)]);slash(800,165,'16')
    rect(850,120,170,110,'#e5ddf1','#9475b2')
    text(935,155,f'cnt_{name}',25,anchor='middle',weight='bold')
    text(935,202,'16-bit register',18,anchor='middle')
    text(861,174,'D',17);text(992,174,'Q',17)
    # Terminal comparison (unsigned).
    rect(1260,120,180,90,'#deeedc','#6c9a69',12)
    text(1350,160,'≥',32,anchor='middle',weight='bold')
    text(1350,193,'unsigned',17,anchor='middle')
    wire([(1440,165),(1560,165)],'#16718a')
    dot(1480,165,'#16718a')
    text(1455,137,f'term_{name}',19,color='#16718a')
    # Clear count gate OR(flush, terminal), drives mux select.
    wire([(1480,165),(1480,325),(620,325),(620,365),(688,365)],'#16718a')
    gate_or(680,350)
    text(858,408,f'clear_{name}',19,color='#16718a')
    wire([(780,380),(800,380),(800,275),(710,275),(710,213)],'#16718a')
    text(720,262,'S',17,color='#16718a')
    # Named flush net is common with the OR gate at top of sheet.
    wire([(300,305),(1500,305),(1500,195),(1550,195)],'#16718a')
    text(300,284,'flush',23,color='#16718a',weight='bold')
    dot(580,305,'#16718a')
    wire([(580,305),(580,395),(688,395)],'#16718a')
    # Tick D = terminal & !flush. Use actual AND symbol and inverted lower pin.
    gate_and(1560,150)
    text(1605,242,f'tick_{name}_D',19,anchor='middle',color='#16718a')
    wire([(1650,180),(1770,180)],'#16718a')
    rect(1770,120,150,130,'#fff0c6','#bd9a3b')
    text(1845,151,'D FLIP-FLOP',18,anchor='middle',weight='bold')
    text(1781,187,'D',19);text(1890,187,'Q',19)
    text(1845,212,f'tick_{name}',21,anchor='middle')
    wire([(1920,180),(2085,180)])
    text(1975,158,f'tick_{name}',25,weight='bold')
    text(1980,211,'1 bit',17)
    # Clock to both count and output register. Red wires, triangle clock pins.
    wire([(90,440),(1740,440),(1740,220),(1770,220)],'#c34848')
    dot(90,440,'#c34848');dot(825,440,'#c34848')
    wire([(825,440),(825,205),(850,205)],'#c34848')
    put('<path d="M850,197 L862,205 L850,213 M1770,212 L1782,220 L1770,228" fill="none" stroke="#c34848" stroke-width="2.5"/>')
    text(866,224,'clk',15,color='#c34848');text(1787,238,'clk',15,color='#c34848')
    # Asynchronous active-low reset into count and output storage.
    wire([(140,500),(1870,500),(1870,255)],'#8056a5',False)
    dot(140,500,'#8056a5');dot(970,500,'#8056a5')
    wire([(970,500),(970,235)],'#8056a5',False)
    put('<circle cx="970" cy="235" r="5" fill="white" stroke="#8056a5" stroke-width="2.5"/><circle cx="1870" cy="255" r="5" fill="white" stroke="#8056a5" stroke-width="2.5"/>')
    text(890,249,'CLR_n',16,color='#8056a5');text(1790,274,'CLR_n',16,color='#8056a5')
    put('</g>')
put('''<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1700" viewBox="0 0 2400 1700"><defs>''')
for name,col in [('data','#243d53'),('control','#16718a'),('clock','#c34848'),('reset','#8056a5')]:
    put(f'<marker id="{name}" markerWidth="10" markerHeight="8" refX="8" refY="4" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L8,4 L0,8 Z" fill="{col}"/></marker>')
put('</defs><g font-family="Noto Sans, DejaVu Sans, sans-serif">')
rect(0,0,2400,1700,'#ffffff','#ffffff')
text(65,52,'BAUD RATE GENERATOR — HAI NHÁNH TX / RX RIÊNG',34,weight='bold')
text(65,93,'Thiết kế đề xuất: 2 counter 16 bit + 2 flip-flop tick • cùng divider_i, reload_i, clk và rst_n',24,color='#52687c')
# Shared flush logic, outside the duplicated lanes.
wire([(65,165),(470,165)]);text(65,144,'divider_i[15:0]',22,weight='bold');dot(180,165)
wire([(180,165),(180,1010)],arrow=False)
rect(470,130,180,70,'#deeedc','#6c9a69',12)
text(560,172,'divider_i == 0',22,anchor='middle')
wire([(650,165),(720,165),(720,150),(808,150)],'#16718a')
wire([(65,215),(760,215),(760,180),(808,180)],'#16718a')
text(65,240,'reload_i',22,weight='bold')
gate_or(800,135)
wire([(900,165),(1050,165)],'#16718a');text(955,144,'flush',24,color='#16718a',weight='bold')
text(1110,162,'flush = reload_i OR (divider_i == 0)',22,color='#16718a')
text(1110,197,'Tên net flush xuất hiện ở cả hai nhánh bên dưới.',18,color='#52687c')
# Boundaries keep the named input taps explicit and reuse common clock/reset.
rect(265,255,1870,580,'#f8fbff','#8aa3b8',22)
rect(265,875,1870,580,'#f8fbff','#8aa3b8',22)
wire([(90,260),(90,1360)],'#c34848',False);text(44,285,'clk',20,color='#c34848',weight='bold')
wire([(140,260),(140,1420)],'#8056a5',False);text(149,285,'rst_n',20,color='#8056a5',weight='bold')
lane('tx',300);lane('rx',920)
# Footer separates design proposal from current implementation.
text(65,1510,'Cổng OR / AND dùng ký hiệu logic; chấm tròn là điểm nối, giao cắt không chấm không nối.',22,color='#52687c')
text(65,1550,'Mỗi nhánh: clear = flush OR terminal; counter_D = clear ? 0 : counter+1; tick_D = terminal AND NOT flush.',22,weight='bold')
text(65,1590,'Hai bộ đếm có cùng divider/reset/reload nên tick_tx và tick_rx vẫn cùng tần số và pha trong điều kiện này.',21,color='#52687c')
text(65,1630,'Lưu ý: đây là sơ đồ tách nhánh theo yêu cầu; RTL hiện tại vẫn có một counter/flip-flop và chưa được sửa trong bước vẽ này.',21,color='#97520d')
put('</g></svg>')
svg=ROOT/'Baud_rate_separate_TX_RX_microarchitecture.svg';svg.write_text('\n'.join(parts))
# Render vector PDF + high-resolution PNG without editing RTL or using raster generation.
c=C.CDLL(find_library('cairo'));r=C.CDLL(find_library('rsvg-2'));g=C.CDLL(find_library('gobject-2.0'))
def bind(lib,n,args,ret=None):
 f=getattr(lib,n);f.argtypes=args;f.restype=ret;return f
ptr=C.c_void_p;D=C.c_double;I=C.c_int;S=C.c_char_p
load=bind(r,'rsvg_handle_new_from_file',[S,ptr],ptr)
render=bind(r,'rsvg_handle_render_cairo',[ptr,ptr],I)
newctx=bind(c,'cairo_create',[ptr],ptr);scale=bind(c,'cairo_scale',[ptr,D,D])
finish=bind(c,'cairo_surface_finish',[ptr]);destroyctx=bind(c,'cairo_destroy',[ptr]);destroysurf=bind(c,'cairo_surface_destroy',[ptr])
unref=bind(g,'g_object_unref',[ptr])
handle=load(str(svg).encode(),None)
if not handle:raise RuntimeError('SVG load failed')
pdf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(svg.with_suffix('.pdf')).encode(),2400,1700)
ctx=newctx(pdf);assert render(handle,ctx);finish(pdf);destroyctx(ctx);destroysurf(pdf)
img=bind(c,'cairo_image_surface_create',[I,I,I],ptr)(0,4800,3400)
ctx=newctx(img);scale(ctx,2,2);assert render(handle,ctx)
assert bind(c,'cairo_surface_write_to_png',[ptr,S],I)(img,str(svg.with_suffix('.png')).encode())==0
finish(img);destroyctx(ctx);destroysurf(img);unref(handle)
print('Generated SVG, vector PDF and 4800×3400 PNG:',svg.with_suffix(''))
