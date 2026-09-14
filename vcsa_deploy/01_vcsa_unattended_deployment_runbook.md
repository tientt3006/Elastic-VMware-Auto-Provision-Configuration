# Sổ tay quy trình cài đặt vCenter Server Appliance (VCSA) tự động không giám sát

Tài liệu này hướng dẫn chi tiết quy trình tự động hóa 100% việc cài đặt và khởi tạo máy ảo VMware vCenter Server Appliance (VCSA) lên máy chủ vật lý VMware ESXi đầu tiên (Host 1) từ trạm điều khiển trung tâm (Automation Ubuntu VM) bằng công cụ dòng lệnh chính thức `vcsa-deploy`.

---

## 1. Bản chất kỹ thuật và cơ chế hoạt động của `vcsa-deploy`

Công cụ `vcsa-deploy` là bộ cài đặt dòng lệnh chính thức do VMware cung cấp, được đóng gói trực tiếp bên trong tệp ISO cài đặt VCSA tại đường dẫn:
```text
/mnt/vcsa_iso/vcsa-cli-installer/lin64/vcsa-deploy
```

Quá trình cài đặt tự động diễn ra theo hai giai đoạn (two-stage process):

```text
+-----------------------------------------------------------------------------------------------+
|                            HAI GIAI ĐOẠN CÀI ĐẶT CỦA VCSA-DEPLOY                              |
|                                                                                               |
|  [ Giai đoạn 1: Triển khai máy ảo OVF/OVA lên ESXi Host ]                                     |
|  - Mount tệp ISO VCSA vào hệ thống tệp Linux.                                                 |
|  - Trích xuất gói OVF mẫu từ ISO và đẩy trực tiếp lên ESXi Host mục tiêu qua HTTPS.           |
|  - Khởi tạo phần cứng máy ảo: CPU, RAM, ổ đĩa VMDK (Thin/Thick), card mạng vNIC.              |
|  - Nạp các thông số mạng tĩnh (IP, Gateway, DNS, FQDN) vào OVF environment.                   |
|  - Bật nguồn máy ảo VCSA và đợi hệ điều hành VMware Photon OS khởi động hoàn tất.             |
|                                                                                               |
|  [ Giai đoạn 2: Cấu hình dịch vụ nền tảng vCenter và Single Sign-On (SSO) ]                  |
|  - Thiết lập múi giờ và đồng bộ hóa thời gian qua máy chủ NTP.                               |
|  - Khởi tạo cụm định danh VMware Single Sign-On (SSO Domain, ví dụ: vsphere.local).          |
|  - Cấu hình tài khoản quản trị tối cao: administrator@vsphere.local.                          |
|  - Sinh cặp khóa và chứng chỉ số nội bộ (VMware Certificate Authority - VMCA).              |
|  - Khởi động toàn bộ các dịch vụ hệ thống: vCenter Server, Envoy Reverse Proxy, vSphere API. |
+-----------------------------------------------------------------------------------------------+
```

---

## 2. Danh mục điều kiện tiên quyết (Prerequisites Checklist)

Trước khi thực thi cài đặt, phải xác nhận các điều kiện hạ tầng sau trên hệ thống mạng và máy chủ ESXi:

### 2.1. Phân giải tên miền xuôi và ngược (Forward & Reverse DNS)
VMware VCSA bắt buộc phải có bản ghi phân giải tên miền hợp lệ trước khi cài đặt. Nếu DNS không phân giải được cả hai chiều, giai đoạn 2 sẽ thất bại hoàn toàn.
- **Bản ghi xuôi (A Record)**: `vcsa.lab.internal` -> `10.255.242.20`.
- **Bản ghi ngược (PTR Record)**: `10.255.242.20` -> `vcsa.lab.internal`.

Kiểm tra từ terminal máy Automation:
```bash
# Kiểm tra phân giải xuôi
dig +short vcsa.lab.internal @10.255.242.1

# Kiểm tra phân giải ngược
dig +short -x 10.255.242.20 @10.255.242.1
```
Kết quả trả về phải hiển thị chính xác địa chỉ IP và FQDN tương ứng.

### 2.2. Đồng bộ thời gian hệ thống (NTP Synchronization)
Độ lệch thời gian giữa máy Automation, máy chủ ESXi Host 1 và máy ảo VCSA không được vượt quá 60 giây. Sai lệch thời gian sẽ làm hỏng cơ chế cấp phát token xác thực của Kerberos và SSO trong giai đoạn 2.
- Cấu hình máy chủ NTP đáng tin cậy (ví dụ: `pool.ntp.org` hoặc NTP server cục bộ).
- Trên ESXi Host, kích hoạt dịch vụ `ntpd` qua giao diện quản trị hoặc lệnh ESXi Shell:
  ```bash
  esxcli system time get
  ```

### 2.3. Cấu hình quy mô tài nguyên (Appliance Sizing)
Lựa chọn quy mô máy ảo phù hợp với tài nguyên phần cứng thực tế của ESXi Host 1:

| Cấu hình | vCPU | RAM | Dung lượng ổ đĩa (Thin) | Giới hạn quản lý tối đa |
| :--- | :--- | :--- | :--- | :--- |
| **tiny** | 2 | 14 GB | ~30 GB | 10 Hosts / 100 VMs (Khuyên dùng cho Lab/Staging) |
| **small** | 4 | 19 GB | ~35 GB | 100 Hosts / 1,000 VMs (Môi trường sản xuất nhỏ) |
| **medium** | 8 | 28 GB | ~50 GB | 400 Hosts / 4,000 VMs |

### 2.4. Tiêu chuẩn độ phức tạp của mật khẩu VMware
Mật khẩu cho tài khoản `root` của hệ điều hành VCSA và tài khoản `administrator@vsphere.local` bắt buộc phải thỏa mãn:
- Độ dài tối thiểu: 8 ký tự (khuyến nghị từ 12 ký tự trở lên).
- Chứa ít nhất một chữ cái viết hoa (`A-Z`).
- Chứa ít nhất một chữ cái viết thường (`a-z`).
- Chứa ít nhất một chữ số (`0-9`).
- Chứa ít nhất một ký tự đặc biệt (`!`, `@`, `#`, `$`, `%`).
- Không chứa các từ khóa phổ biến hoặc trùng với tên tài khoản.

---

## 3. Cấu trúc tệp đặc tả cài đặt (`embedded_vcs_on_esxi.json`)

Mẫu cấu hình chuẩn nằm tại [templates/embedded_vcs_on_esxi.json.tpl](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/templates/embedded_vcs_on_esxi.json.tpl). Dưới đây là ý nghĩa chi tiết từng khối tham số kỹ thuật:

```json
{
  "__version": "2.13.0",
  "new_vcsa": {
    "esxi": {
      "hostname": "10.255.242.10",             // IP hoặc FQDN của ESXi Host vật lý đích
      "username": "root",                     // Tài khoản quản trị cấp cao nhất của ESXi
      "password": "${ESXI_PASSWORD}",         // Mật khẩu ESXi (được tiêm động qua RAM)
      "deployment_network": "VM Network",     // Tên Portgroup mạng máy ảo kết nối
      "datastore": "datastore1"               // Tên Datastore lưu trữ máy ảo VCSA
    },
    "appliance": {
      "deployment_option": "tiny",            // Quy mô máy ảo: tiny, small, medium
      "name": "srv-vcsa-primary",             // Tên hiển thị của máy ảo trên ESXi Inventory
      "thick_provision": false                // false = Cấp phát dung lượng mỏng (Thin Provision)
    },
    "os": {
      "password": "${VCSA_ROOT_PASSWORD}",    // Mật khẩu root Photon OS của VCSA
      "ntp_servers": "pool.ntp.org",          // Danh sách máy chủ thời gian
      "ssh_enable": true                      // Bật dịch vụ SSH cổng 22 vào VCSA
    },
    "sso": {
      "password": "${SSO_ADMIN_PASSWORD}",    // Mật khẩu quản trị viên SSO
      "domain_name": "vsphere.local"          // Tên miền định danh Single Sign-On
    },
    "network": {
      "ip_family": "ipv4",                    // Giao thức mạng IPv4
      "mode": "static",                       // Bắt buộc là static đối với môi trường doanh nghiệp
      "ip": "10.255.242.20",                  // Địa chỉ IP tĩnh của VCSA
      "dns_servers": ["10.255.242.1"],        // Máy chủ DNS giải quyết được FQDN của VCSA
      "prefix": "24",                         // Subnet mask dạng tiền tố (24 tương đương 255.255.255.0)
      "gateway": "10.255.242.1",              // Cổng định tuyến mặc định (Default Gateway)
      "system_name": "vcsa.lab.internal"      // FQDN của VCSA (phải khớp hoàn toàn với DNS)
    }
  },
  "ceip": {
    "settings": {
      "ceip_enabled": false                   // Tắt chương trình thu thập dữ liệu trải nghiệm khách hàng
    }
  }
}
```

---

## 4. Các bước thực thi chi tiết (CLI Execution)

### Bước 1: Khai báo thông số cấu hình hạ tầng
Di chuyển vào thư mục cài đặt và tạo tệp cấu hình môi trường:
```bash
cd /mnt/d/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy
cp vcsa_vars.env.example vcsa_vars.env
```

Mở tệp `vcsa_vars.env` bằng trình soạn thảo và điền các thông số thực tế của dự án:
- `ESXI_HOSTNAME`: Địa chỉ IP của máy chủ ESXi Host 1.
- `DATASTORE_NAME`: Tên datastore đích trên ESXi.
- `VCSA_STATIC_IP`: Địa chỉ IP dự kiến gán cho máy ảo VCSA.
- `VCSA_FQDN`: Tên miền đầy đủ của VCSA.
- `VCSA_ISO_PATH`: Đường dẫn tuyệt đối tới tệp ISO cài đặt VCSA trên máy Automation.

### Bước 2: Thực thi kịch bản cài đặt tự động
Chạy kịch bản điều phối với quyền `sudo`:
```bash
sudo ./deploy_vcsa_unattended.sh
```

Kịch bản thực hiện tuần tự:
1. Nạp các biến hạ tầng từ tệp `vcsa_vars.env`.
2. Tự động kiểm tra và mount tệp ISO VCSA vào thư mục `/mnt/vcsa_iso`.
3. Yêu cầu nhập mật khẩu bảo mật qua terminal ẩn:
   - Mật khẩu root của ESXi Host.
   - Mật khẩu root của máy ảo VCSA.
   - Mật khẩu quản trị SSO (`administrator@vsphere.local`).
4. Tự động sinh tệp đặc tả JSON vào bộ nhớ tạm RAM disk (`/dev/shm/vcsa_deployment_spec_<PID>.json`) với phân quyền giới hạn `0600`.
5. Kích hoạt giai đoạn kiểm tra điều kiện tiên quyết (Precheck):
   ```bash
   vcsa-deploy install --precheck-only --accept-eula --no-ssl-certificate-verification ...
   ```
6. Khi Precheck hoàn tất và đạt tiêu chuẩn, kịch bản hiển thị bảng tóm tắt thông số và yêu cầu xác nhận `yes/no`.
7. Khi người dùng nhập `yes`, tiến trình cài đặt thực tế bắt đầu. Thời gian thực thi kéo dài từ 15 đến 25 phút tùy theo tốc độ mạng và hiệu năng ổ đĩa.
8. Khi tiến trình kết thúc (thành công hoặc có lỗi), kịch bản tự động kích hoạt hàm `cleanup`:
   - Ghi đè và tiêu hủy tệp JSON chứa mật khẩu khỏi RAM disk (`shred`).
   - Gỡ mount điểm `/mnt/vcsa_iso`.
   - Thu hồi (unset) toàn bộ biến mật khẩu khỏi bộ nhớ RAM.

---

## 5. Đọc và xác minh kết quả đầu ra (Output Verification)

### 5.1. Nhật ký thực thi thành công của `vcsa-deploy`
Sau khi giai đoạn 2 hoàn tất, dòng nhật ký cuối cùng sẽ xuất ra thông báo:
```text
==============================================================================
Result:
    The deployment of vCenter Server Appliance was successful.
Details:
    Appliance Name: srv-vcsa-primary
    Appliance IP: 10.255.242.20
    Log directory: /var/log/vmware/upgrade/
    vSphere Client URL: https://vcsa.lab.internal/ui
==============================================================================
```

### 5.2. Kiểm tra trạng thái dịch vụ vCenter qua API và dòng lệnh
Từ máy Automation, thực thi các lệnh sau để kiểm tra trạng thái hoạt động của vCenter:

1. **Kiểm tra cổng dịch vụ mạng (Port 443 HTTPS)**:
   ```bash
   nc -zv 10.255.242.20 443
   ```
   Kết quả mong đợi: `Connection to 10.255.242.20 443 port [tcp/https] succeeded!`.

2. **Kiểm tra trạng thái hệ thống vCenter qua công cụ `govc`**:
   ```bash
   export GOVC_URL="https://10.255.242.20"
   export GOVC_USERNAME="administrator@vsphere.local"
   read -s -p "Nhap mat khau SSO: " GOVC_PASSWORD; export GOVC_PASSWORD
   export GOVC_INSECURE="true"

   govc about
   ```
   Kết quả hiển thị phiên bản phần mềm:
   ```text
   About:
     Name:         VMware vCenter Server
     Vendor:       VMware, Inc.
     Version:      8.0.2
     Build:        22385739
     OS type:      linux-x64
     API type:     VirtualCenter
     API version:  8.0.2.0
     Product ID:   vpx
   ```

3. **Truy cập giao diện đồ họa vSphere Client**:
   Mở trình duyệt web và truy cập địa chỉ:
   ```text
   https://vcsa.lab.internal/ui
   ```
   Đăng nhập bằng tài khoản: `administrator@vsphere.local` và mật khẩu đã thiết lập.

---

## 6. Xử lý sự cố thường gặp (Troubleshooting)

### 6.1. Lỗi không khớp bản ghi phân giải DNS (`FQDN does not resolve`)
- **Triệu chứng**: Giai đoạn Precheck hoặc Giai đoạn 2 báo lỗi: `The FQDN vcsa.lab.internal does not match the IP address 10.255.242.20 or cannot be resolved`.
- **Nguyên nhân gốc rễ**: DNS Server chưa khai báo bản ghi A hoặc PTR, hoặc máy ảo VCSA không kết nối được tới DNS Server qua cổng UDP 53.
- **Biện pháp khắc phục**:
  1. Kiểm tra cấu hình DNS trên máy chủ quản lý DNS nội bộ, đảm bảo đã tạo cả hai bản ghi:
     ```text
     A Record  : vcsa.lab.internal -> 10.255.242.20
     PTR Record: 10.255.242.20     -> vcsa.lab.internal
     ```
  2. Nếu môi trường lab không có DNS server chuyên dụng, có thể cấu hình tạm dịch vụ `dnsmasq` hoặc cấu hình bản ghi phân giải cục bộ trên router/gateway.

### 6.2. Lỗi lệch thời gian hệ thống (`Time skew between ESXi and VCSA`)
- **Triệu chứng**: Giai đoạn 2 bị dừng ở mức 80% - 90% khi khởi tạo SSO service với thông báo lỗi: `An error occurred while starting the service 'vmware-vpxd' / 'vmware-sts-idmd'`.
- **Nguyên nhân gốc rễ**: ESXi Host và máy ảo VCSA có đồng hồ phần cứng (RTC) lệch nhau quá nhiều khiến chứng chỉ bảo mật và phiên xác thực Kerberos bị từ chối.
- **Biện pháp khắc phục**:
  1. Đăng nhập trực tiếp vào ESXi Host qua SSH:
     ```bash
     esxcli system time set -d 14 -M 09 -y 2026 -H 10 -m 30 -s 00
     ```
  2. Đảm bảo tham số `ntp_servers` trong tệp cấu hình JSON trỏ tới một NTP server đang hoạt động ổn định.

### 6.3. Lỗi không đủ dung lượng bộ nhớ hoặc ổ đĩa Datastore
- **Triệu chứng**: Giai đoạn Precheck báo lỗi: `Target datastore does not have enough capacity`.
- **Nguyên nhân gốc rễ**: Datastore trên ESXi Host có dung lượng trống thấp hơn mức yêu cầu của quy mô cài đặt (Tiny yêu cầu tối thiểu khoảng 30 GB trống khi bật Thin Provisioning và hơn 500 GB nếu dùng Thick Provisioning).
- **Biện pháp khắc phục**:
  1. Đảm bảo tham số `"thick_provision": false` trong tệp cấu hình để sử dụng cấp phát dung lượng mỏng.
  2. Dọn dẹp các máy ảo cũ hoặc tệp ISO không dùng trên Datastore để giải phóng tối thiểu 40 GB dung lượng trống.

### 6.4. Vị trí lưu trữ tệp nhật ký điều tra chuyên sâu
Khi tiến trình `vcsa-deploy` gặp lỗi, toàn bộ nhật ký chi tiết của từng bước được ghi nhận tại thư mục:
```text
/var/log/vmware/upgrade/
```
Xem tệp nhật ký chi tiết nhất bằng lệnh:
```bash
tail -n 100 /var/log/vmware/upgrade/vcsa-cli-installer.log
```
Tra cứu mã lỗi hoặc thông báo lỗi cụ thể trong tệp này để xác định chính xác dịch vụ gây ra sự cố.
