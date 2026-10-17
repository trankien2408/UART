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
repo=ROOT.parent.parent

def ref(path, needle):
    lines=(repo/path).read_text().splitlines()
    for i,line in enumerate(lines,1):
        if needle in line:return f'L{i}: {needle}'
    raise ValueError(f'Missing anchor: {path}: {needle}')
def row(path, needle, change, new=False):
    return [path+(' [MỚI]' if new else ''),ref(path,needle),change]
pages=[
('1. Thay đổi phần cứng RTL', 'Baud được ghi lúc chạy; IRQ được tạo từ trạng thái UART và đưa ra component.',[
row('rtl/baud_rate_gen.v','input wire [15:0] divider_i','Thêm divider_i 16 bit và reload_i; bộ đếm 16 bit xuất tick_tx và tick_rx cùng nhịp ×16 theo divider hiện tại. Khi APPLY: reset bộ đếm/tick; divider 0 dừng tick.'),
row('rtl/register_file.v',"REG_FIFO=12'h014",'Thêm 0x18 SHADOW, 0x1C ACTIVE, 0x20 CONTROL_STATUS. Thêm baud_safe và APPLY; chỉ đổi ACTIVE khi TX_DONE, RX an toàn và divider khác 0. Ghi byte lane 0/1 vào SHADOW.'),
row('rtl/register_file.v','wire [2:0] int_status','Thêm INT_ENABLE 0x24, INT_STATUS 0x28 và irq_o. Bit 0 RX có dữ liệu; bit 1 TX_DONE; bit 2 RX overrun. IRQ = OR(enable & status), reset tắt toàn bộ enable.'),
row('rtl/dti_uart.v','reg [4:0] rx_quiet_ticks','Thêm bộ đếm xác nhận RX idle 16 tick; nối baud_div và baud_apply giữa register_file và generator. Đưa IRQ ra top UART; parameter BAUDRATE giữ vai trò mặc định sau reset.'),
row('rtl/uart_rx/rx_topmodule.v','assign baud_idle_o','Xuất baud_idle_o khi RX controller idle, RX đã đồng bộ ở mức cao và không có start edge đang phát hiện. Đây là đầu vào cho điều kiện đổi baud an toàn.'),
row('rtl/uart_avalon.v','output wire tx, rts_n, irq','Bổ sung cổng irq, nối từ dti_uart ra giao diện component. Đường đọc/ghi Avalon → bridge → APB vẫn giữ nguyên.')
], 'Luồng baud: C → SHADOW → APPLY hợp lệ → ACTIVE → baud_tick → TX/RX.\nLuồng IRQ: trạng thái RX/TX/overrun → mask → irq → Nios V. Peer phải ngừng gửi khi đổi baud.'),
('2. Thay đổi firmware C', 'ISR phục vụ RX nhanh; main giữ phần xử lý dòng và điều phối baud/TX.',[
row('firmware/dti_uart.h','DTI_BAUD_SHADOW','Bổ sung offset 0x18–0x28, các mask baud/ngắt và khai báo API dti_baud_divider(), dti_set_baud().'),
row('firmware/dti_uart.c','int dti_baud_divider','Tính divider gần nhất bằng số học 64 bit; kiểm tra 1..65535 và sai số ≤2%. dti_set_baud() ghi SHADOW, kiểm tra BUSY, APPLY và xác nhận ACTIVE, có timeout.'),
row('firmware/uart_irq.c','int uart_irq_init','File mới: đăng ký ISR, bật RX/overrun; ISR lấy tối đa 16 byte kèm parity vào ring 512 entry (dùng được 511). TX_DONE được ghi nhận rồi mask; tràn lưu lỗi và tắt IRQ UART.',True),
row('firmware/uart_irq.h','int uart_irq_init','File mới: giao diện ISR, nhận từ ring, đọc lỗi, arm/nhận thông báo TX hoàn tất. ISR độc quyền pop RX phần cứng; main độc quyền enqueue TX.',True),
row('firmware/uart_platform.h','static inline uint32_t uart_irq_lock','Thêm wrapper khóa/khôi phục IRQ và đăng ký qua HAL alt_ic_isr_register(). Nếu BSP thiếu IRQ UART thì trả lỗi, không tự chuyển về polling.'),
row('firmware/main.c','static int baud_command','Thêm lệnh JTAG :baud N. Init đăng ký IRQ; poll đọc ring ISR và cờ TX hoàn tất. Sau khi queue TX rỗng, kiểm tra RX rồi APPLY trong critical section ngắn; tăng timeout theo baud thấp.')
], 'Vị trí thêm trong main.c: receive_char() nhận lệnh JTAG; uart_demo_init() gọi uart_irq_init(); uart_demo_poll() dùng ring/cờ ISR và xử lý pending_baud.\nChat Enter/CRLF/Backspace giữ hành vi cũ; JTAG console tiếp tục polling.'),
('3. Kết nối hệ thống và công cụ chạy', 'Cần sinh lại hệ thống/BSP và dùng SOF + ELF mới tương thích.',[
row('fpga/ip/uart_avalon_hw.tcl','add_interface irq interrupt sender','Khai báo interrupt sender, gắn clock/reset và associatedAddressablePoint avalon. Không thêm chân GPIO IRQ ra board.'),
row('fpga/scripts/create_system.tcl','add_connection cpu.platform_irq_rx uart.irq','Nối UART IRQ vào cpu.platform_irq_rx và gán irqNumber 1. JTAG UART vẫn ở IRQ 0.'),
row('firmware/build.sh','sources="$firmware_dir/main.c','Thêm uart_irq.c vào ứng dụng echo/chat. Scope và selftest giữ nguồn polling, không cần dùng ISR chat.'),
row('firmware/terminal_uart.sh','baud="${2:-115200}"','Thêm đối số baud thứ hai, mặc định 115200; truyền baud cho picocom. Ví dụ: terminal_uart.sh /dev/ttyUSB0 9600.'),
row('firmware/serial_echo_test.py',"parser.add_argument('--baud'",'Thêm --baud để kiểm tra serial ở tốc độ mới; điều chỉnh thời hạn đọc/ghi theo baud.'),
['File sinh tự động: uart_soc.qsys, uart_soc.sopcinfo, firmware/build/bsp/system.h','Sinh từ create_system.tcl và firmware/build.sh','Generate lại Platform Designer và BSP; system.h có UART_IRQ=1, controller ID=0. Các file này không sửa tay. bsp_settings.tcl chỉ cập nhật chú thích về IRQ/mtime.']
], 'Thao tác: dừng gửi picocom → gõ :baud 9600 tại JTAG → chờ báo thành công → mở lại picocom ở 9600.\nMặc định/reset: 115200. Driver từ chối 230400 vì sai số khoảng −3,12%; không có auto-baud.'),
('4. File kiểm thử và phạm vi xác nhận', 'Bảng này tóm tắt các nhóm kiểm thử đã bổ sung hoặc điều chỉnh.',[
row('tb/tb_baud_dynamic.v','module tb_baud_dynamic','File mới: divider 1/2/65535, reload, divider 0 và đổi divider; 263.816 checks.',True),
row('tb/tb_baud_irq.v','module tb_baud_irq','File mới: serial nhiều baud, APPLY khi CTS/RX bận hoặc có start edge, byte strobe, IRQ mask/level, parity/overrun và reset; 269 checks.',True),
['firmware/tests/test_driver.c; test_demo.c; test_irq.c [test_irq.c MỚI]','Các bài test C native; chạy bởi firmware/test_driver.sh','Kiểm tra tính baud, timeout, lệnh JTAG; ISR thật trong model host, ring wrap/overflow, parity, mask TX_DONE và lỗi đăng ký ISR.'],
['tb/firmware_cosim.c; tb_firmware_cosim.v; tb_firmware_echo_cosim.v','Co-simulation C + RTL; các script run_firmware_*cosim.sh','Driver + RTL: 768 frame, đổi baud bằng API. Chat + RTL: 538 byte, IRQ RTL được model host gọi ISR C; đổi 9600 → 115200, từ chối 230400.'],
['tb/tb_niosv_firmware.v; sim/run_tests.sh','Giám sát CPU thật; danh sách regression','Cho phép trap ngắt hợp lệ, kiểm tra có IRQ entry; payload chat dùng ASCII. Thêm hai test RTL mới; cập nhật các TB cũ cho cổng mới và địa chỉ không hợp lệ.'],
['docs/BAUD_INTERRUPT.md; firmware/VALIDATION.md; README và tài liệu tích hợp','Hướng dẫn sử dụng / kết quả đã ghi nhận','Ghi register map, quy trình đổi baud, chính sách ISR và kết quả. Tài liệu tóm tắt này không chạy lại các kiểm thử.']
], 'Đã ghi nhận: RTL 15/15 PASS; C/ISR và C+RTL PASS; ELF build PASS; Quartus timing +0,148 ns.\nQuesta compile-only PASS; chạy CPU bị chặn socket. SOF còn Simulation-Only trong môi trường công cụ; chưa xác nhận bản mới trên kit.')
]

W,H=842,595
pdf=ROOT/'Tom_tat_file_thay_doi_Baud_Interrupt.pdf'
surface=pdf_create(str(pdf).encode(),W,H)
metadata(surface,0,'Tóm tắt file thay đổi — Baud runtime và interrupt UART'.encode())
ctx=create(surface)
INK=(0.08,0.15,0.24);TEAL=(0,0.40,0.44);MUTED=(0.36,0.42,0.49)
def text(s,x,y,w,size=11,col=INK,bold=False,draw=True):
 l=layout_new(ctx);fd=font_new(('Noto Sans '+('Bold ' if bold else '')+str(size)).encode())
 font_size(fd,size*1024);set_font(l,fd);set_width(l,int(w*1024));set_wrap(l,2);set_spacing(l,2*1024);set_text(l,s.encode(),-1)
 ww,hh=I(),I();get_size(l,ct.byref(ww),ct.byref(hh))
 if draw: color(ctx,*col);move(ctx,x,y);show_layout(ctx,l)
 unref(l);font_free(fd);return hh.value
def rect(x,y,w,h,col):
 color(ctx,*col);rectangle(ctx,x,y,w,h);fill(ctx)
widths=[224,186,380]
md=['# Bảng tóm tắt file thay đổi: baud động và interrupt\n',
    'Đối chiếu source ngày 16/10/2026. Đường dẫn tính từ UART/. Dòng nguồn là mốc tại thời điểm tạo tài liệu; có thể dịch chuyển khi sửa code.\n']
for idx,(title,sub,rows,note) in enumerate(pages,1):
 rect(0,0,W,H,(0.97,0.98,0.99));rect(0,0,8,H,TEAL)
 text('UART / DE2-115 • BẢNG TÓM TẮT THAY ĐỔI',26,17,790,10,TEAL,True)
 text(title,26,38,790,23,bold=True)
 text(sub,26,76,790,11.5,col=MUTED)
 y=105
 headers=['File / trạng thái','Vị trí thay đổi trong source','Nội dung và mục đích']
 rect(26,y,790,28,TEAL);x=26
 for val,w in zip(headers,widths):text(val,x+8,y+6,w-16,11,(1,1,1),True);x+=w
 y+=28
 for n,row in enumerate(rows):
  heights=[text(v,0,0,w-16,10.6,draw=False) for v,w in zip(row,widths)]
  rh=max(heights)+14
  rect(26,y,790,rh-1,(1,1,1) if n%2==0 else (0.90,0.94,0.95))
  x=26
  for j,(v,w) in enumerate(zip(row,widths)):
   text(v,x+8,y+6,w-16,10.6,bold=False);x+=w
  y+=rh
 if idx==3:
  extra='Các khối giữ nguyên thuật toán: Avalon–APB bridge, APB slave, FIFO và TX/RX controller/datapath. RX top chỉ bổ sung idle; pin assignment không đổi.'
  eh=text(extra,26,y+12,790,10.5,col=MUTED)
  if y+12+eh>492:raise RuntimeError('Extra note overflow')
 if y>490:raise RuntimeError(f'Table overflow page {idx}: {y}')
 rect(26,498,790,65,(0.88,0.93,0.94));text('ĐIỂM CẦN NHỚ',36,505,770,9.5,TEAL,True)
 h=text(note,36,521,770,10.2)
 if h>39:raise RuntimeError(f'Note overflow page {idx}: {h}')
 text('16/10/2026 • Đường dẫn tương đối từ UART/ • Số dòng là mốc của source hiện tại',26,576,720,8.5,MUTED)
 text(f'{idx} / {len(pages)}',775,576,45,9,MUTED)
 show_page(ctx)
 md += ['\n## '+title+'\n',sub+'\n','| File | Vị trí | Nội dung |','|---|---|---|']
 md += ['|'+'|'.join(r)+'|' for r in rows]
 md += ['\n'+note+'\n']
finish(surface)
md += ['\nCác khối giữ nguyên thuật toán: avalon_apb_bridge.v, apb_slave.v, uart_fifo.v, TX controller/datapath và RX controller/datapath. RX top chỉ thêm tín hiệu idle. Không đổi pin assignment hoặc thêm chân IRQ ngoài FPGA.\n']
(ROOT/'Tom_tat_file_thay_doi_Baud_Interrupt.md').write_text('\n'.join(md))
print(f'Generated {len(pages)} pages: {pdf}')
