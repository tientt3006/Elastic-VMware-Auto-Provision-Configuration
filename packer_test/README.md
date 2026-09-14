# Quy trình đóng gói bản mẫu máy ảo Ubuntu 24.04 LTS trên VMware vSphere bằng HashiCorp Packer

## 1. Tổng quan và phạm vi kỹ thuật

Tài liệu này hướng dẫn chi tiết quy trình tự động hóa đóng gói bản mẫu máy ảo chuẩn (Golden Image / Template) chạy hệ điều hành Ubuntu Server 24.04 LTS trên hạ tầng ảo hóa VMware vSphere, sử dụng công cụ HashiCorp Packer và bộ cài đặt tự động Canonical Subiquity.

Bản mẫu máy ảo sau khi hoàn tất quá trình đóng gói đáp ứng đầy đủ các tiêu chuẩn kỹ thuật:
- Cài đặt hệ điều hành tự động, phi tương tác (non-interactive unattended installation) qua cơ chế Subiquity autoinstall.
- Nạp cấu hình tự động thông qua ổ đĩa CD-ROM ảo mang nhãn `cidata` (NoCloud datasource), triệt tiêu hoàn toàn các lỗi mạng trung chuyển khi chạy máy chủ HTTP từ môi trường WSL.
- Tích hợp sẵn gói điều khiển máy khách `open-vm-tools` và dịch vụ đồng bộ thời gian `chrony` phục vụ cơ chế giám sát heartbeat và tương tác API từ vCenter.
- Thiết lập chuẩn an ninh cơ sở (Security Baseline): Khóa tài khoản root trực tiếp qua SSH, giới hạn số lần xác thực sai, cấu hình tường lửa UFW mặc định chặn toàn bộ kết nối đi vào (chỉ mở cổng SSH TCP 22).
- Tích hợp sẵn Cloud-Init với cấu hình tương thích VMware Guest Customization.
- Tổng quát hóa hệ điều hành (OS Generalization): Cắt ngắn `machine-id`, thu hồi toàn bộ cặp khóa SSH host key cũ, dọn sạch log hệ thống và bộ nhớ đệm gói cài đặt để đảm bảo định danh duy nhất khi Terraform nhân bản (clone) hàng loạt.

---

## 2. Cấu trúc thư mục

```text
packer_test/
├── README.md                                 # Tài liệu hướng dẫn quy trình và vận hành
├── build_packer_secure.sh                    # Kịch bản điều phối build an toàn In-Memory kết hợp govc
├── co_che_ghi_de_va_quan_ly_vong_doi_template.md # Hướng dẫn xử lý trùng tên và vòng đời template
├── giai_phap_bao_mat_bien_moi_truong_packer.md   # Phân tích kỹ thuật giải pháp In-Memory Secrets
├── packer_capabilities_assessment.md         # Đánh giá mức độ đáp ứng 5 trụ cột năng lực Packer
├── packer_issues_and_solutions.md            # Sổ tay sự cố và giải pháp khắc phục chi tiết (INC-01 đến INC-11)
├── variables.pkr.hcl                         # Khai báo biến và ràng buộc kiểu dữ liệu Packer HCL
├── ubuntu-24.04.pkr.hcl                      # Định nghĩa nguồn vsphere-iso và quy trình build chính
├── packer.pkrvars.hcl                        # Giá trị tham số môi trường vCenter mục tiêu
├── packer.pkrvars.hcl.example                # File tham số mẫu phục vụ lưu trữ Git
├── http/
│   ├── meta-data                             # Metadata cấu hình máy ảo cho Cloud-Init
│   └── user-data                             # Cấu hình cài đặt tự động Subiquity
└── scripts/
    ├── 01_install_open_vm_tools.sh           # Cài đặt và kích hoạt open-vm-tools, chrony
    ├── 02_harden_ssh.sh                      # Gia cố an ninh cấu hình máy chủ OpenSSH
    ├── 03_configure_ufw.sh                   # Thiết lập chính sách tường lửa host UFW
    └── 04_generalize_template.sh             # Dọn dẹp machine-id, xóa SSH key, làm sạch log
```

---

## 3. Cài đặt bộ công cụ trên môi trường WSL Ubuntu

Trước khi thực thi quy trình đóng gói trong hệ điều hành phụ WSL Ubuntu, kỹ sư thực hiện cài đặt HashiCorp Packer và các gói phụ trợ từ kho lưu trữ APT chính thức của HashiCorp.

### 3.1. Thêm kho lưu trữ APT chính thức của HashiCorp

1. Mở cửa sổ terminal WSL.

2. Cài đặt các gói phụ trợ cần thiết:
   ```bash
   sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl lsb-release
   ```

3. Tải và xác thực khóa GPG công khai của HashiCorp:
   ```bash
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   ```

4. Đăng ký kho lưu trữ APT của HashiCorp:
   ```bash
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   ```

5. Cập nhật danh mục gói và cài đặt Packer cùng tiện ích `xorriso` (công cụ bắt buộc để tạo file ISO ảo `cidata`):
   ```bash
   sudo apt-get update && sudo apt-get install -y packer xorriso
   ```

6. Kiểm tra phiên bản Packer đã cài đặt:
   ```bash
   packer version
   ```

   Kết quả tiêu chuẩn hiển thị:
   ```text
   Packer v1.11.2 (hoặc phiên bản mới hơn)
   ```

---

## 4. Tham số hạ tầng và định tuyến file ISO trên vCenter

### 4.1. Bảng ánh xạ thông số vCenter

File cấu hình [packer.pkrvars.hcl](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test/packer.pkrvars.hcl) được thiết lập tương thích với hạ tầng vCenter Server:

| Tham số | Giá trị gán | Ý nghĩa kỹ thuật |
| :--- | :--- | :--- |
| `vcenter_server` | `10.255.242.106` | Địa chỉ IP / FQDN của máy chủ vCenter Server |
| `vcenter_user` | `administrator@vsphere.local` | Tài khoản quản trị vCenter có đủ quyền cấp phát VM |
| `vcenter_datacenter` | `Datacenter` | Tên đối tượng Datacenter trên vCenter |
| `vcenter_cluster` | `Cluster1` | Tên cụm tính toán mục tiêu |
| `vcenter_datastore` | `DS_100_3` | Tên vùng lưu trữ VMFS chứa Content Library |
| `vcenter_network` | `VM Network` | Tên port group ảo hỗ trợ cấp phát DHCP tạm thời khi build |
| `vcenter_folder` | `VM Template` | Thư mục kiểm kê (Inventory Folder) lưu trữ template |
| `vm_name` | `tpl-ubuntu-2404-golden` | Tên bản mẫu máy ảo đích sau khi chuyển đổi |

### 4.2. Đường dẫn vật lý của file ISO trong Content Library

vSphere Content Library lưu trữ các file ISO trong cấu trúc thư mục phân cấp băm UUID trên datastore. File ISO `ubuntu-24.04.4-live-server-amd64.iso` được ánh xạ đường dẫn trực tiếp trên datastore `DS_100_3` như sau:

```hcl
iso_paths = [
  "[DS_100_3] contentlib-a0bc3584-8b7c-40cc-b2fd-bae7a6b9bf6c/befc5a25-2315-479a-833a-2cc168de715c/ubuntu-24.04.4-live-server-amd64_58a8cfa8-32e5-437c-b161-b18e4dc8d7aa.iso"
]
```

---

## 5. Cơ chế nạp cấu hình tự động qua đĩa ảo CD-ROM (cidata)

Thay vì chạy một máy chủ HTTP tạm thời trên máy trạm WSL vốn dễ gặp sự cố chặn cổng từ tường lửa Windows hoặc không thể định tuyến từ mạng vật lý ESXi vào mạng NAT nội bộ của WSL, kiến trúc Packer này ứng dụng giải pháp đóng gói trực tiếp cấu hình Cloud-Init thành đĩa CD-ROM ảo:

```hcl
cd_files = ["${path.root}/http/user-data", "${path.root}/http/meta-data"]
cd_label = "cidata"
```

Khi máy ảo khởi động, Packer tự động tạo file ISO từ thư mục `http/`, gắn làm ổ CD-ROM thứ hai trên máy ảo. Nhân Linux của bộ cài Ubuntu tự động nhận diện ổ đĩa có nhãn `cidata` thông qua cờ khởi động GRUB `autoinstall ds=nocloud`, triệt tiêu hoàn toàn sự phụ thuộc vào mạng ngoài hay máy chủ web trung gian.

Chuỗi lệnh GRUB tương tác trực tiếp với giao diện dòng lệnh:
```hcl
boot_command = [
  "c<wait>",
  "search --set=root --file /casper/vmlinuz<enter><wait>",
  "linux /casper/vmlinuz --- autoinstall ds=nocloud<enter><wait5s>",
  "initrd /casper/initrd<enter><wait5s>",
  "boot<enter>"
]
```

---

## 6. Quy trình thực thi đóng gói an toàn bằng kịch bản In-Memory

Để bảo đảm tuyệt đối không lưu mật khẩu vCenter và mật khẩu tài khoản quản trị máy ảo vào file cấu hình trên ổ đĩa, toàn bộ quy trình build được kích hoạt qua kịch bản điều phối [build_packer_secure.sh](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test/build_packer_secure.sh).

### 6.1. Các bước thực hiện

1. Điều hướng vào thư mục `packer_test` trong môi trường WSL:
   ```bash
   cd /mnt/d/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test
   ```

2. Cấp quyền thực thi và khởi chạy kịch bản:
   ```bash
   chmod +x ./build_packer_secure.sh
   ./build_packer_secure.sh
   ```

3. Kịch bản yêu cầu nhập mật khẩu quản trị vCenter và mật khẩu quản trị máy khách (chuỗi ký tự được ẩn hoàn toàn trên màn hình terminal):
   ```text
   ==============================================================================
   He thong dieu phoi dong goi Template Packer an toan In-Memory
   ==============================================================================
   May chu vCenter: 10.255.242.106
   Tai khoan:       administrator@vsphere.local
   Ten template VM: tpl-ubuntu-2404-golden
   ------------------------------------------------------------------------------
   Nhap mat khau quan tri vCenter: 
   Nhap mat khau SSH khoi tao may ao (svc_admin): 
   ```

4. **Tiền kiểm tra tự động (Pre-flight Checks)**:
   - Kịch bản xuất biến môi trường vào bộ nhớ RAM (`PKR_VAR_vcenter_password`, `PKR_VAR_ssh_password`, `GOVC_URL`, `GOVC_USERNAME`, `GOVC_PASSWORD`).
   - Sử dụng lệnh `govc about` để kiểm tra kết nối và tính hợp lệ của tài khoản vCenter trong 0.5 giây.
   - Sử dụng lệnh `govc vm.info` để kiểm tra xem template `tpl-ubuntu-2404-golden` đã tồn tại trên vCenter hay chưa. Nếu đã tồn tại, kịch bản đưa ra câu hỏi xác nhận cho phép xóa bản cũ để build đè hay dừng tiến trình an toàn.
   - Chạy lệnh `packer validate` để kiểm tra toàn vẹn cú pháp HCL trước khi cấp phát tài nguyên.

5. **Tiến trình đóng gói tự động**:
   - Cấp phát máy ảo tạm thời trên ESXi với thông số: 4 CPU cores, 8GB RAM, 50GB ổ đĩa PVSCSI, card mạng VMXNET3.
   - Gắn file ISO cài đặt Ubuntu 24.04 và đĩa CD-ROM cấu hình `cidata`.
   - Gửi lệnh GRUB khởi động Subiquity autoinstall.
   - Hệ điều hành tự động phân vùng đĩa, cài đặt gói cơ sở, thiết lập tài khoản `svc_admin` và khởi động lại.
   - Packer kết nối SSH vào máy ảo qua cổng 22.
   - Thực thi lần lượt 4 kịch bản cấu hình trong thư mục `scripts/`:
     1. `01_install_open_vm_tools.sh`: Cài đặt `open-vm-tools`, `chrony`, thiết lập dịch vụ hệ thống.
     2. `02_harden_ssh.sh`: Cấu hình an toàn OpenSSH.
     3. `03_configure_ufw.sh`: Kích hoạt tường lửa UFW, chỉ cho phép cổng SSH.
     4. `04_generalize_template.sh`: Dọn sạch `machine-id`, SSH host keys, log hệ thống, giải phóng bộ nhớ đệm APT.
   - Tắt máy ảo an toàn (`poweroff`) và gọi API vCenter chuyển đổi máy ảo thành vSphere Template.
   - Kịch bản tự động thu hồi toàn bộ biến môi trường mật khẩu khỏi RAM nhờ cơ chế `trap cleanup EXIT`.

---

## 7. Khắc phục sự cố thường gặp

Chi tiết phân tích mã lỗi, nhật ký điều tra và 11 tình huống sự cố thực tế được trình bày đầy đủ tại [packer_issues_and_solutions.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test/packer_issues_and_solutions.md). Dưới đây là các sự cố thường gặp nhất:

### 7.1. Lỗi: Template đã tồn tại trên vCenter (The name already exists)

- **Hiện tượng**: Quá trình khởi tạo máy ảo bị từ chối với thông báo:
  ```text
  ==> vsphere-iso.ubuntu: Error creating virtual machine: The name 'tpl-ubuntu-2404-golden' already exists.
  ```
- **Nguyên nhân**: vCenter không cho phép tạo hai đối tượng trùng tên trong cùng thư mục kiểm kê.
- **Biện pháp xử lý**:
  - Khi sử dụng `build_packer_secure.sh`, kịch bản tự động phát hiện và hỏi người dùng có muốn xóa bản cũ hay không.
  - Hoặc thực hiện xóa thủ công qua công cụ `govc`:
    ```bash
    govc vm.destroy "tpl-ubuntu-2404-golden"
    ```
  - Hoặc đổi tên bản build mới theo phiên bản thời gian trong `packer.pkrvars.hcl` (ví dụ: `tpl-ubuntu-2404-20260912`).

### 7.2. Lỗi: Trình cài đặt dừng tại màn hình chọn ngôn ngữ của Subiquity

- **Hiện tượng**: Màn hình console máy ảo dừng tại giao diện lựa chọn ngôn ngữ, Packer bị timeout kết nối SSH.
- **Nguyên nhân**: Lệnh khởi động GRUB không truyền được tham số `autoinstall ds=nocloud` vào kernel hoặc đĩa CD-ROM `cidata` không được gắn đúng nhãn.
- **Biện pháp xử lý**: Kiểm tra lại cấu hình `boot_command` trong [ubuntu-24.04.pkr.hcl](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test/ubuntu-24.04.pkr.hcl). Đảm bảo sử dụng chế độ nhập dòng lệnh GRUB `c` và tìm kiếm đúng phân vùng chứa kernel bằng lệnh `search --set=root --file /casper/vmlinuz`.

### 7.3. Lỗi: Hết thời gian chờ tùy biến máy ảo khi Terraform nhân bản

- **Hiện tượng**: Lệnh `terraform apply` bị treo và báo lỗi: `Waiting for customization to complete... timeout`.
- **Nguyên nhân**: Dịch vụ `open-vm-tools` trên template bị vô hiệu hóa hoặc Cloud-Init ghi đè cấu hình mạng gây xung đột với cơ chế guest customization của vSphere.
- **Biện pháp xử lý**: Kiểm tra kịch bản `04_generalize_template.sh`. Đảm bảo file cấu hình `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` chứa nội dung `network: {config: disabled}` để nhường quyền cấu hình card mạng cho tiến trình guest customization của VMware.
