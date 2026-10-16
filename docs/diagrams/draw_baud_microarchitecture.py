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
put('''<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1150" viewBox="0 0 1800 1150">
<defs>''')
for name,col in [('data','#243d53'),('control','#16718a'),('clock','#c34848'),('reset','#8056a5')]:
    put(f'<marker id="{name}" markerWidth="10" markerHeight="8" refX="8" refY="4" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L8,4 L0,8 Z" fill="{col}"/></marker>')
put('</defs><g font-family="Noto Sans, DejaVu Sans, sans-serif">')
rect(0,0,1800,1150,'#ffffff','#ffffff')
text(65,52,'BAUD RATE GENERATOR — MICROARCHITECTURE',30,weight='bold')
text(65,88,'Một bộ đếm 16 bit • divider lập trình được • hai output tick_tx / tick_rx cùng nhịp ×16',21,color='#52687c')
rect(225,135,1275,885,'#f8fbff','#8aa3b8',24)
text(255,175,'baud_rate_gen  |  đúng theo RTL hiện tại',21,weight='bold')
text(255,199,'Chấm tròn: điểm nối. Giao cắt không chấm: không nối.',14,color='#52687c')
# Draw wires first; boxes later mask labels and interiors.
# Runtime divider buses to subtractor and zero comparator.
wire([(65,270),(305,270)])
dot(260,270);wire([(260,270),(260,435),(305,435)])
text(65,245,'divider_i[15:0]',21,weight='bold');slash(275,270,'16')
wire([(485,270),(580,270)]);slash(530,270,'16')
text(495,244,'threshold',16)
# Terminal comparator to tick gate; branch controls counter mux.
wire([(810,270),(1040,270)],'#16718a');dot(900,270,'#16718a')
text(830,245,'terminal',18,color='#16718a',weight='bold')
wire([(900,270),(900,520),(650,520),(650,540)],'#16718a')
wire([(485,435),(565,435)],'#16718a')
wire([(65,495),(530,495),(530,465),(565,465)],'#16718a')
text(65,473,'reload_i',21,weight='bold')
# Flush goes to tick mask and counter reset select.
wire([(735,445),(1110,445),(1110,325)],'#16718a');dot(940,445,'#16718a')
text(760,427,'flush',18,color='#16718a',weight='bold')
wire([(940,445),(940,495),(550,495),(550,575),(610,575)],'#16718a')
# Counter register and feedback.
wire([(1220,690),(1250,690),(1250,360),(695,360),(695,315)])
dot(1250,690);text(708,387,'counter[15:0]',17)
wire([(1250,690),(1250,830),(505,830),(505,720)])
text(900,812,'counter[15:0] — feedback',17)
wire([(570,680),(660,680),(660,665),(770,665)])
slash(703,665,'16');text(586,650,'counter + 16’d1',17)
wire([(670,730),(770,730)]);text(660,758,'16’d0',18)
wire([(885,690),(1040,690)]);slash(935,690,'16');text(910,665,'counter_D',17)
# Flush OR terminal selects clear for counter.
wire([(760,570),(827,570),(827,637)],'#16718a')
text(779,554,'clear_count',16,color='#16718a')
# Gate output into tick FF.
wire([(1180,270),(1260,270)],'#16718a');text(1189,246,'tick_D',16,color='#16718a')
wire([(1410,270),(1450,270),(1450,235),(1585,235)])
dot(1450,270);wire([(1450,270),(1450,345),(1585,345)])
text(1506,219,'tick_tx',20,weight='bold');text(1506,329,'tick_rx',20,weight='bold')
# Both registers use same clock. Clock triangles explicitly shown.
wire([(65,920),(1240,920)],'#c34848',False)
text(65,900,'clk',21,color='#c34848',weight='bold')
dot(1000,920,'#c34848');wire([(1000,920),(1000,735),(1040,735)],'#c34848')
wire([(1240,920),(1240,325),(1260,325)],'#c34848')
# Async active-low clear is independent of synchronous flush.
wire([(65,980),(1370,980),(1370,359)],'#8056a5',False)
text(65,960,'rst_n',21,color='#8056a5',weight='bold')
dot(1160,980,'#8056a5');wire([(1160,980),(1160,779)],'#8056a5',False)
# Combinational blocks.
rect(305,230,180,80,'#e0eef8')
text(395,261,'SUBTRACT 1',18,anchor='middle',weight='bold')
text(395,291,'divider_i − 16’d1',17,anchor='middle')
rect(580,225,230,90,'#ddefdf','#7aa577',12)
text(695,261,'UNSIGNED ≥',21,anchor='middle',weight='bold')
text(695,289,'counter ≥ threshold',17,anchor='middle')
rect(305,400,180,70,'#ddefdf','#7aa577',12)
text(395,430,'divider_i == 0',19,anchor='middle')
text(395,453,'invalid',16,anchor='middle',color='#52687c')
rect(565,405,170,80,'#ddefdf','#7aa577',12)
text(650,437,'OR',22,anchor='middle',weight='bold')
text(650,463,'reload | invalid',16,anchor='middle')
rect(610,540,150,62,'#ddefdf','#7aa577',12)
text(685,568,'OR',21,anchor='middle',weight='bold')
text(685,589,'flush | terminal',15,anchor='middle')
rect(1040,225,140,100,'#ddefdf','#7aa577',12)
text(1110,257,'AND',22,anchor='middle',weight='bold')
text(1110,285,'terminal',16,anchor='middle')
text(1110,307,'& !flush',16,anchor='middle')
# Incrementer and mux.
rect(440,645,130,75,'#ddefdf','#7aa577',12)
text(505,692,'+ 16’d1',22,anchor='middle',weight='bold')
put('<polygon points="770,620 885,655 885,725 770,770" fill="#f7d9d5" stroke="#c67469" stroke-width="2"/>')
text(789,672,'0',19,weight='bold');text(789,737,'1',19,weight='bold')
text(823,703,'MUX',17,anchor='middle',weight='bold')
text(843,611,'S',16,color='#16718a')
# Storage elements (all shown with async clear).
rect(1040,620,180,155,'#e5ddf1','#9475b2')
text(1130,655,'COUNTER',22,anchor='middle',weight='bold')
text(1130,683,'16-bit register',18,anchor='middle')
text(1050,714,'D',17);text(1192,714,'Q',17)
put('<path d="M1040,725 L1055,735 L1040,745" fill="none" stroke="#c34848" stroke-width="2"/>')
text(1065,741,'clk',15,color='#c34848')
put('<circle cx="1160" cy="779" r="4" fill="white" stroke="#8056a5" stroke-width="2"/>')
text(1097,763,'CLR_n',15,color='#8056a5')
rect(1260,220,150,135,'#fff0c6','#bd9a3b')
text(1335,249,'D FLIP-FLOP',17,anchor='middle',weight='bold')
text(1270,284,'D',17);text(1382,284,'Q',17)
text(1335,307,'tick_tx',18,anchor='middle')
put('<path d="M1260,315 L1275,325 L1260,335" fill="none" stroke="#c34848" stroke-width="2"/>')
text(1283,332,'clk',15,color='#c34848')
put('<circle cx="1370" cy="359" r="4" fill="white" stroke="#8056a5" stroke-width="2"/>')
text(1303,347,'CLR_n',14,color='#8056a5')
rect(1585,200,160,75,'#e0eef8',r=12);text(1665,231,'TX core',22,anchor='middle',weight='bold');text(1665,257,'tick_tx',17,anchor='middle')
rect(1585,310,160,75,'#e0eef8',r=12);text(1665,341,'RX core',22,anchor='middle',weight='bold');text(1665,367,'tick_rx',17,anchor='middle')
text(1585,414,'Nằm ngoài module',16,color='#52687c')
text(1510,465,'tick_rx = tick_tx',18,color='#16718a')
# Small legend and exact priority explanation outside circuit boundary.
text(65,1060,'Ưu tiên: !rst_n (reset bất đồng bộ) → flush → terminal → đếm tăng.',20,weight='bold')
text(65,1093,'divider_i ← BAUD_DIV_ACTIVE; reload_i ← baud_apply. Điều kiện đổi baud an toàn được kiểm tra bên ngoài module.',18,color='#52687c')
text(65,1125,'Nguồn: UART/rtl/baud_rate_gen.v và UART/rtl/dti_uart.v. Tick là clock-enable; divider = 1 cho tick liên tục mỗi clock.',16,color='#52687c')
put('</g></svg>')
svg=ROOT/'Baud_rate_programmable_microarchitecture.svg';svg.write_text('\n'.join(parts))
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
pdf=bind(c,'cairo_pdf_surface_create',[S,D,D],ptr)(str(svg.with_suffix('.pdf')).encode(),1800,1150)
ctx=newctx(pdf);assert render(handle,ctx);finish(pdf);destroyctx(ctx);destroysurf(pdf)
img=bind(c,'cairo_image_surface_create',[I,I,I],ptr)(0,3600,2300)
ctx=newctx(img);scale(ctx,2,2);assert render(handle,ctx)
assert bind(c,'cairo_surface_write_to_png',[ptr,S],I)(img,str(svg.with_suffix('.png')).encode())==0
finish(img);destroyctx(ctx);destroysurf(img);unref(handle)
print('Generated SVG, vector PDF and 3600×2300 PNG:',svg.with_suffix(''))
