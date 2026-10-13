# Cấp phép Nios V/m trước khi nạp kit

**Trạng thái mới nhất: ĐÃ ĐẠT.** Lượt build trong terminal thường kết thúc
12/10/2026 lúc 16:17:29, không còn lỗi license/Simulation-Only. Đã tạo marker
HARDWARE_BUILD_READY và xác nhận checksum FPGA/firmware. Các lỗi dưới đây là
lịch sử chẩn đoán, bao gồm giới hạn NIC ID của phiên công cụ. Chưa thử kit thật.

## License người dùng đã cung cấp

File `../../LR-199530_License.dat` có feature `6AF7_D036` mà Nios V/m yêu cầu,
hạn 12/10/2027; Host ID khớp một card mạng hiện có. Script `scripts/env.sh`
tự thêm file này vào `ALTERAD_LICENSE_FILE`, giữ các đường dẫn license khác
và không thay `LM_LICENSE_FILE` của Questa. Không cần export lại mỗi terminal
khi chạy các script project. Có thể đổi file bằng `UART_NIOSV_LICENSE_FILE`.

Chạy `bash UART/fpga/build.sh compile` để kiểm tra Quartus thực sự chấp nhận
license. Kiểm tra feature/Host ID ở trên không thay thế kết quả checkout.
Nếu mở Quartus GUI trực tiếp, cấu hình License Setup theo bước 3 bên dưới,
hoặc khởi động Quartus từ terminal đã `source UART/fpga/scripts/env.sh`.

## Kết quả build sau khi cấu hình file

Lượt kết thúc 12/10/2026 lúc 16:14:30: Quartus compile thành công, timing
worst slack 0.119 ns, nhưng Warning 12189 Simulation-Only vẫn còn. Không còn
Warning 24850 token HTTP 401. Không tạo marker sẵn sàng nạp.

Chẩn đoán FlexNet trong phiên công cụ: `lmhostid -ether` trả Host ID rỗng;
`lmdiag` cho feature `6AF7_D036` báo `Invalid host`, lỗi `-9,57`, System Error 1.
Đọc sysfs cho thấy Host ID trong file khớp card mạng máy. Vì vậy cần kiểm tra
checkout trong terminal thường; chưa có bằng chứng phải xin lại license.

Chạy từ terminal VS Code của người dùng:

```bash
cd /home/kien/Documents/uart
bash UART/fpga/build.sh compile
```

Nếu vẫn Simulation-Only, chẩn đoán ở cùng terminal:

```bash
source UART/fpga/scripts/env.sh
lmutil lmhostid -ether
lmutil lmdiag -n -c "$ALTERAD_LICENSE_FILE" 6AF7_D036
```

Phiên công cụ không thay Host ID, không sửa nội dung license, không bỏ
kiểm tra cấp phép. Kết quả build từ terminal thường là bước xác nhận còn lại.

## Nguyên nhân đã xác nhận ngày 12/10/2026

Lần build trong terminal người dùng báo Warning 24850:
`IP-NIOSVM: Client token expired.Server returned http code [401]`.
Warning 12189 cho biết `Evaluation Mode (Simulation-Only)`.
Đây là lỗi lấy license tự động; không phải lỗi RTL hoặc timing.
`AUTO_REFRESH_TOKEN = on` đã có trong cấu hình Quartus, nên chỉ bật lại tùy
chọn này không giải quyết được lỗi đã quan sát.

Trong các vị trí đã kiểm tra chỉ tìm thấy license `intelqsimstarter` của
Questa, chưa tìm thấy license Nios V/m. Hai license có mục đích riêng.

## Cách khắc phục bằng license file

1. Mở Quartus trên máy thật: **Tools → License Setup** (hoặc trang
   **License Setup** trong **Tools → Options**). Lấy NIC ID ở phần
   **Local system information**. Dùng NIC ID mà Quartus nhận trên chính máy
   này; không lấy ID của môi trường chạy công cụ bị giới hạn.
2. Đăng nhập [Self-Service Licensing Center](https://licensing.intel.com/psg/s/).
   Vào **Sign up for Evaluation or No-Cost Licenses**, chọn
   **Nios V/m Microcontroller FPGA IP (IP-NIOSVM)**, một seat; gán vào máy
   với NIC ID ở bước 1 và tạo/tải license file. Tên menu có thể thay đổi.
3. Trong License Setup, trỏ **License file** tới file vừa tải và xác nhận
   IP Nios V/m xuất hiện trong danh sách license. Giữ license Questa hiện có.
   Không sửa nội dung/chữ ký license file.
4. Để build bằng terminal dùng chính file mới, chạy (thay đường dẫn mẫu):

   ```bash
   export ALTERAD_LICENSE_FILE='/duong/dan/thuc/niosv_license.dat'
   cd /home/kien/Documents/uart
   bash UART/fpga/build.sh compile
   ```

   Nếu đã dùng ALTERAD_LICENSE_FILE cho license khác, thêm đường dẫn mới vào
   danh sách bằng dấu `:` trên Linux thay vì bỏ cấu hình đang dùng.

5. Chỉ coi bước build đạt khi script trả exit code 0, hết lỗi cấp phép và có
   `UART/fpga/build/HARDWARE_BUILD_READY.txt`. Nếu còn lỗi, kiểm tra log mới;
   không tự tạo marker hoặc bỏ kiểm tra trong `check_build.py`.

Các bước tải license phía trên được giữ để tham khảo khi gia hạn hoặc đổi máy.
Người dùng đã cung cấp file, không cần tải lại trừ khi Quartus báo file không
hợp lệ hoặc Host ID không phù hợp.

## Tài liệu hãng

- [Nios V Embedded Processor Design Handbook — Processor Licensing](https://cdrdv2-public.intel.com/820962/ug-726952-820962.pdf): Nios V có license riêng, có thể lấy miễn phí qua SSLC.
- [Software Installation and Licensing — Token Expired](https://cdrdv2-public.intel.com/840045/quartus_install-683472-840045.pdf): khi token hết hạn, dùng license lấy thủ công qua SSLC hoặc phiên bản phần mềm mới hơn. Hướng dẫn token trong tài liệu nói về Pro; log bản 25.1std đang cài cũng trực tiếp yêu cầu lấy license thủ công.
