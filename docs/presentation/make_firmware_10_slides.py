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
add('Firmware C: điều khiển hệ thống UART', 'Nios V thực thi chương trình • Avalon vận chuyển giao dịch',
['Firmware là chương trình điều khiển hệ thống nhúng, được viết bằng C trong đề tài.',
 'Nhiệm vụ: nhận, xử lý và chuyển dữ liệu giữa JTAG terminal và UART vật lý.',
 'C quyết định gửi gì và khi nào; phần cứng UART tạo và nhận các bit trên dây.'],
'Mở đầu bằng chức năng người dùng thấy: gõ dòng ở một terminal, Enter để chuyển sang terminal còn lại. Sau đó giới thiệu ba vai trò: firmware là chương trình, Nios V là CPU thực thi, Avalon là giao diện bus bên trong FPGA.',
'firmware/main.c; firmware/dti_uart.c; rtl/dti_uart.v')
add('Firmware chạy trên CPU Nios V', 'CPU mềm và chương trình C là hai thành phần khác nhau',
['Nios V/m được triển khai bằng logic trong FPGA; CPU lấy lệnh từ RAM on-chip.',
 'Code C được biên dịch thành lệnh RISC-V trong ELF rồi nạp để Nios V thực thi.',
 'CPU PC chạy công cụ build/nạp và terminal; firmware ứng dụng chạy trên Nios V.',
 'SOF cấu hình phần cứng FPGA; ELF cung cấp chương trình chạy trên CPU đó.'],
'Nios V không phải một file C. Nó là bộ xử lý đã được tạo khi FPGA được cấu hình. RAM 128 KiB chứa chương trình, dữ liệu và stack. Có thể đổi ứng dụng chat sang scope bằng ELF khác khi phần cứng vẫn tương thích.',
'fpga/scripts/create_system.tcl; firmware/build.sh; fpga/program.sh')
add('Firmware của đề tài làm những việc gì?', 'Ứng dụng chat hai chiều, điều khiển bằng thanh ghi',
['Khởi tạo: kiểm tra System ID, chọn UART 8N1, bật LED ready.',
 'Nhận byte từ JTAG UART và UART riêng; lưu hai dòng nhập độc lập.',
 'Chờ Enter, chuẩn hóa CRLF rồi chuyển dòng sang phía đối diện.',
 'Nạp TX FIFO, đọc RX FIFO; theo dõi parity, tràn RX và timeout.'],
'Firmware quyết định chính sách chat và xử lý lỗi. Baud 115200 được chọn trong RTL; C hiện chỉ cấu hình định dạng frame. Điều kiện Enter nằm trong chương trình C, không phải chức năng của FIFO hay bus Avalon.',
'firmware/main.c: uart_demo_init(), uart_demo_poll(), receive_char()')
add('Avalon-MM là gì, dùng để làm gì?', 'Kết nối truy cập bộ nhớ và ngoại vi bên trong FPGA',
['Avalon-MM là giao diện bus đọc/ghi theo địa chỉ; MM nghĩa là memory-mapped.',
 'Nios V phát yêu cầu; interconnect giải mã địa chỉ và định tuyến đến đích.',
 'RAM, JTAG UART, PIO và UART riêng cùng được CPU truy cập qua hệ thống này.',
 'Bridge chuyển Avalon-MM sang APB vì UART riêng của đề tài dùng giao diện APB.'],
'Cách nói chính xác: firmware truy cập ngoại vi bằng MMIO; phần cứng Nios V phát giao dịch Avalon. Avalon không phải chương trình C và không phải đường USB nối với PC. IP JTAG UART nối Avalon trực tiếp, không qua bridge APB của UART riêng.',
'fpga/scripts/create_system.tcl; rtl/uart_avalon.v; rtl/avalon_apb_bridge.v')
add('Quan hệ C → Nios V → Avalon → UART', 'Một lời gọi ghi thanh ghi được thực hiện qua các tầng sau',
[],
'Ví dụ C muốn ghi byte h. Macro IOWR_32DIRECT thực hiện truy cập MMIO; CPU đưa yêu cầu ra bus. Bridge tạo các pha APB, slave tiếp nhận và register_file cập nhật thanh ghi. Mỗi khối có một nhiệm vụ, C không tự bật PSEL hoặc PENABLE.',
'firmware/uart_platform.h; rtl/avalon_apb_bridge.v; rtl/apb_slave.v; rtl/register_file.v',
flow=[['C: uart_mmio_write()','BSP: IOWR_32DIRECT','Nios V: yêu cầu ghi'],['Avalon interconnect','Avalon → APB bridge','apb_slave'],['register_file','TX FIFO → TX core','Chân UART_TX']])
add('MMIO: chọn ngoại vi và thanh ghi bằng địa chỉ', 'Địa chỉ truy cập = địa chỉ nền + offset thanh ghi',
[],
'Ví dụ UART_BASE là 0x21000; cộng offset 0x0C được địa chỉ STATUS 0x2100C. Địa chỉ nền lấy từ system.h do BSP sinh. Ghi TX chỉ giữ staging; ghi START mới enqueue. Đọc RX có tác động pop nên driver kiểm tra RX_DONE trước.',
'firmware/dti_uart.h; firmware/uart_platform.h; fpga/scripts/create_system.tcl',
rows=[['Địa chỉ CPU','Thanh ghi / khối','Firmware sử dụng'],['0x20000','JTAG UART DATA','Nhận hoặc gửi byte console'],['0x21000','UART TX — offset 0x00','Ghi byte staging'],['0x21004 / 0x21008','CFG / CTRL','Chọn 8N1 / ghi START'],['0x2100C','STATUS','Kiểm tra TX_DONE, RX_DONE, parity'],['0x21010 / 0x21014','RX / FIFO_STATUS','Pop byte / kiểm tra đầy, rỗng, tràn']])
add('Ví dụ code: gửi ký tự h vào TX FIFO', 'dti_try_queue() — kiểm tra chỗ trống, ghi byte, ghi START',
['byte = 0x68 là ký tự h.',
 'TX_FULL = 1: trả DTI_AGAIN để thử lại sau.',
 'Ghi TX rồi START: đưa byte vào FIFO.',
 'DTI_OK là đã enqueue; TX_DONE mới báo toàn bộ TX đã phát xong.'],
'Thân hàm bên phải trích từ driver. Mỗi đọc/ghi MMIO tạo giao dịch bus; phần cứng TX tự phát frame sau khi lấy byte. Driver hiện dành cho một task sở hữu UART, tránh tác vụ khác chen vào giữa thao tác ghi TX và START.',
'firmware/dti_uart.c: dti_try_queue(); rtl/register_file.v',
code='if (dti_fifo_status(dev) & DTI_TX_FULL)\n    return DTI_AGAIN;\nuart_mmio_write(dev->base + DTI_TX, byte);\nuart_mmio_write(dev->base + DTI_CTRL, 1u);\nreturn DTI_OK;')
add('Firmware vận hành bằng vòng lặp polling', 'Khởi tạo một lần, sau đó liên tục phục vụ hai phía',
['Xuất tối đa 16 byte JTAG khi IP còn chỗ; kiểm tra TX hoàn tất hoặc lỗi.',
 'Thử nhận 1 byte UART và 1 byte JTAG; xử lý ký tự, Enter và Backspace.',
 'Khi đợt TX trước đã xong: nạp tối đa 16 byte mới vào FIFO rồi quay lại vòng lặp.',
 'main.c xử lý ứng dụng; dti_uart.c và console.c truy cập hai ngoại vi.'],
'Polling nghĩa là CPU chủ động kiểm tra trạng thái lặp lại; ứng dụng hiện không phục vụ dữ liệu bằng ngắt. Queue C nằm trong RAM, khác FIFO phần cứng 16 byte. Giới hạn công việc mỗi lượt giúp tránh dành quá lâu cho một phía; MMIO vẫn cần thời gian bus để hoàn tất.',
'firmware/main.c: uart_demo_poll(); firmware/console.c; firmware/dti_uart.c')
add('Hai terminal: firmware chuyển dữ liệu ở giữa', 'Ví dụ JTAG → UART; chiều ngược lại thực hiện tương tự',
[],
'Khi chưa Enter, firmware echo về bên nhập và giữ dòng. Khi Enter, nó chuyển cả dòng sang hàng đợi đầu ra. Chiều ngược: picocom → USB-UART → RX FIFO → C → JTAG UART → terminal 1. JTAG UART và UART vật lý là hai ngoại vi riêng; chip USB-UART trên ESP32 làm cầu USB–serial.',
'firmware/main.c: receive_char(); firmware/console.c; firmware/terminal_uart.sh',
flow=[['PC: JTAG terminal','USB-Blaster → JTAG','IP JTAG UART'],['Nios V đọc byte qua bus','C: giữ dòng đến Enter','C: enqueue UART TX'],['Avalon → APB → UART','Chip USB-UART ESP32','PC: picocom']])
add('Ba vai trò cần nhớ khi trình bày', 'Chương trình quyết định • CPU thực thi • Bus kết nối',
['Firmware C: chọn cấu hình, xử lý dòng, điều phối TX/RX và phản ứng với lỗi.',
 'CPU Nios V: thực thi lệnh máy, đọc/ghi RAM và thanh ghi ngoại vi.',
 'Avalon-MM: mang giao dịch CPU đến đúng đích; bridge đổi sang APB cho UART riêng.',
 'UART phần cứng: giữ FIFO và phát/nhận frame theo baud, độc lập với từng lệnh C.'],
'Câu kết: “Firmware chạy trên Nios V và điều khiển ngoại vi bằng MMIO qua hệ thống Avalon-MM; UART phần cứng đảm nhận truyền nhận bit.” Demo ngắn: gõ hello, chưa Enter phía kia chưa có dòng; Enter thì dòng được chuyển. Bản rút gọn này tổng hợp từ PDF chi tiết, không phải báo cáo kiểm thử mới.',
'Tổng hợp từ bản PDF chi tiết và source trong firmware/, rtl/, fpga/')
assert len(slides)==10

# Layout: 16:9, vector text, embedded font subsets, overflow checks.
W,H=960,540
BG=(0.96,0.97,0.99); INK=(0.09,0.15,0.24); MUTED=(0.35,0.42,0.51); TEAL=(0.0,0.43,0.46)
surface=pdf_create(str(ROOT/'Firmware_NiosV_Avalon_10_slide.pdf').encode(),W,H)
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
for idx,s in enumerate(slides,1):
 box(0,0,W,H,BG);box(0,0,12,H,TEAL)
 txt('UART / DE2-115     •     FIRMWARE & BUS',38,19,820,11,TEAL,True)
 txt(s['title'],38,44,890,28,bold=True,limit=45)
 txt(s['subtitle'],38,91,884,15,MUTED,limit=45)
 y=143
 if s['rows']:
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
(ROOT/'slide_content_10.json').write_text(json.dumps(slides,ensure_ascii=False,indent=2))
md=['# Firmware C — nội dung và lời dẫn cho slide\n','Bản đối chiếu source ngày 15/10/2026.\n']
for i,s in enumerate(slides,1):
 md += [f'\n## Slide {i:02d}. {s["title"]}\n',s['subtitle']+'\n']
 md += ['- '+b for b in s['bullets']]
 if s['flow']: md += ['\n```text']+[' → '.join(r) for r in s['flow']]+['```']
 if s['rows']:
  md += ['\n|'+'|'.join(s['rows'][0])+'|','|'+'|'.join(['---']*len(s['rows'][0]))+'|']
  md += ['|'+'|'.join(r)+'|' for r in s['rows'][1:]]
 if s['code']: md+=['\n```c',s['code'],'```']
 md += ['\n**Gợi ý thuyết trình:** '+s['note'],'\n**Nguồn source:** '+s['source']]
(ROOT/'Loi_thuyet_trinh_10_slide.md').write_text('\n'.join(md)+'\n')
print(f'Generated {len(slides)} slides: {ROOT / "Firmware_NiosV_Avalon_10_slide.pdf"}')
