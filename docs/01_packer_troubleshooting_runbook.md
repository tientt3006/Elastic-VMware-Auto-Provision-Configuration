# Sổ tay xử lý sự cố và giải pháp kỹ thuật: Quy trình đóng gói Packer Ubuntu 24.04 trên VMware vSphere

## 1. Tóm tắt tổng quan

Tài liệu này ghi lại toàn bộ các thách thức kỹ thuật, phân tích nguyên nhân gốc rễ (root cause), phương pháp chẩn đoán chuyên sâu và giải pháp khắc phục dứt điểm trong quá trình xây dựng bản mẫu máy ảo chuẩn (Golden Image / Template) chạy hệ điều hành Ubuntu Server 24.04 LTS trên nền tảng ảo hóa VMware vSphere, sử dụng công cụ HashiCorp Packer và môi trường WSL 2.

### 1.1. Bối cảnh hạ tầng và công cụ

- **Môi trường máy trạm**: Windows 11 chạy bản phân phối Ubuntu trên hệ thống phụ Windows Subsystem for Linux (WSL 2).
- **Hạ tầng ảo hóa**: Thiết bị máy chủ ảo VMware vCenter Server Appliance (`<VCENTER_IP>`), Datacenter `Datacenter`, Cụm máy chủ `Cluster1`, Vùng lưu trữ `DS_100_3`.
- **Hệ điều hành máy khách mục tiêu**: Ubuntu Server 24.04.4 LTS (64-bit, chuẩn khởi động UEFI firmware).
- **Quy trình tự động hóa**: HashiCorp Packer (builder `vsphere-iso`), công cụ cài đặt Subiquity autoinstall, Cloud-Init, Netplan và Open-VM-Tools.

---

## 2. Ma trận tổng hợp các sự cố kỹ thuật

| Mã sự cố | Giai đoạn vận hành | Mô tả sự cố | Nguyên nhân gốc rễ | Tóm tắt giải pháp |
| :--- | :--- | :--- | :--- | :--- |
| **INC-01** | Khởi tạo cấu hình | Không nhận diện đường dẫn ISO trong Content Library | Plugin `vsphere-iso` yêu cầu đường dẫn vật lý trên datastore, không nhận mã định danh URN của Content Library | Phân giải đường dẫn vật lý theo cấu trúc thư mục UUID `contentlib-*` trên datastore |
| **INC-02** | Khởi động hệ điều hành | Bỏ qua cài đặt tự động Subiquity, hiện màn hình chọn ngôn ngữ | Máy chủ HTTP của Packer tự động liên kết vào địa chỉ loopback nội bộ của WSL (`10.255.255.254`) | Cấu hình `http_bind_address = "0.0.0.0"` và gán `http_ip = "10.255.245.20"` |
| **INC-03** | Trung chuyển mạng | Hết thời gian chờ yêu cầu HTTP tới máy chủ autoinstall | Tường lửa Windows Defender và WSL chặn các gói tin đi vào trên dải cổng 8120–8130 | Bổ sung luật mở cổng trên tường lửa Windows và cho phép lưu lượng trong WSL |
| **INC-04** | Trình khởi động GRUB | Lỗi `error: file '/casper/vmlinuz' not found` | Giao diện dòng lệnh GRUB (`c`) không tự động trỏ biến `root` vào ổ đĩa CD-ROM UEFI | Chuyển sang chỉnh sửa dòng lệnh GRUB trực tiếp bằng phím `e` |
| **INC-05** | Trình khởi động GRUB | Phím bấm bị bỏ qua, hệ thống tự động khởi động trình cài đặt mặc định | Bộ đếm thời gian chờ của GRUB (5 giây) hết hạn trước khi tham số `boot_wait = "10s"` kịp gửi phím | Tinh chỉnh `boot_wait = "3s"` kết hợp gửi phím mũi tên để đóng băng bộ đếm |
| **INC-06** | Cài đặt hệ điều hành | Curtin bị lỗi với mã thoát khác 0 (exit status 100) | DHCP cấp địa chỉ IP nhưng không cấp máy chủ DNS; tải gói ngoài bị thất bại | Khai báo DNS dự phòng trong Netplan; chuyển quy trình autoinstall sang chế độ ngoại tuyến 100% |
| **INC-07** | Khởi động lại / SSH | Máy ảo khởi động thành công nhưng mất kết nối mạng (`IP: None`) | Netplan cấu hình cứng tên card mạng `ens192`, nhưng UEFI của VMware gán tên `ens160` | Cấu hình Netplan khớp mẫu ký tự đại diện cho toàn bộ card Ethernet (`en*`) |
| **INC-08** | Kiến trúc hệ thống | Ràng buộc đóng gói template trong môi trường mạng cách ly (Air-Gapped) | Mất kết nối tới các kho lưu trữ APT công cộng gây treo tiến trình build | Tách rời quy trình, sử dụng gói cài đặt sẵn trên file ISO, cô lập cấu hình NTP/DNS |
| **INC-09** | Cài đặt hệ điều hành | Curtin bị treo hơn 30 phút tại bước `installing-kernel` | Curtin thực thi lệnh `apt-get` cài đặt `linux-generic`; mạng drop gói gây ra cơn bão chờ TCP timeout | Cấu hình `apt: fallback: offline-install` và loại bỏ DNS công cộng không thể định tuyến |
| **INC-10** | Khởi động autoinstall | Subiquity tự động chuyển sang chế độ cài đặt thủ công qua giao diện | Sai cú pháp JSON schema do lặp khóa `network:` lồng nhau trong file YAML | Chuẩn hóa cấu trúc Netplan đặt trực tiếp `version: 2` dưới khóa `autoinstall.network` |
| **INC-11** | Trình khởi động GRUB | Yêu cầu xác nhận `Continue with autoinstall? (yes\|no)` chặn tiến trình tự động | Điều hướng phím mũi tên trong GRUB bị lệch dòng, khiến tham số `autoinstall` không vào kernel | Chuyển sang giao diện dòng lệnh GRUB `c` kết hợp lệnh `search --set=root` và chuyển sang dùng ổ CD-ROM ảo `cidata` |
| **INC-12** | Khởi động máy ảo (EFI) | Lỗi `Virtual SATA CDROM Drive... No Media` và Packer dừng tại `Waiting for IP` | Trỏ file ISO bằng đường dẫn raw datastore UUID của Content Library (`[DS] contentlib-*`) bị Content Library lease/lock, ESXi không mount được | Chuẩn hóa `iso_paths` sang cú pháp định danh Content Library (`"Library/Item/file.iso"` hoặc `"Library/Item"`), cấu hình `boot_order = "cdrom,disk"` và `cd_label = "OEMDRV"` |

---

## 3. Chẩn đoán chi tiết và giải pháp khắc phục từng sự cố

### 3.1. Sự cố 1 (INC-01): Phân giải đường dẫn vật lý của file ISO trong Content Library

#### Hiện tượng
Plugin `vsphere-iso` của Packer yêu cầu định dạng đường dẫn datastore theo mẫu `[tên_datastore] đường_dẫn/tới/tệp.iso`. Khi khai báo trực tiếp tên hoặc mã URN của Content Library trong biến `iso_paths`, quá trình khởi tạo VM thất bại với lỗi không tìm thấy tệp (file not found).

#### Phân tích nguyên nhân
VMware vSphere Content Library lưu trữ các tệp tải lên tại các phân vùng datastore bên dưới theo cấu trúc thư mục băm định danh UUID:
```text
[datastore_name] contentlib-<library_uuid>/<item_uuid>/<original_filename>_<file_uuid>.iso
```
Plugin `vsphere-iso` tiêu chuẩn của Packer không tích hợp sẵn cơ chế tự động phân giải từ URN của Content Library sang đường dẫn vật lý trên VMFS datastore.

#### Giải pháp khắc phục
1. Truy vấn API vSphere thông qua thư viện Python (`pyVmomi`) để xác định chính xác đường dẫn lưu trữ:
   ```python
   # Duyệt tìm các tệp trên datastore khớp với mẫu tên ubuntu
   search_spec = vim.host.DatastoreBrowser.SearchSpec()
   search_spec.matchPattern = ["*ubuntu-24.04*.iso"]
   ```
2. Cập nhật đường dẫn tuyệt đối đã phân giải vào file cấu hình [packer.pkrvars.hcl](file:///d:/neit_ng/prjs_i/auto_provision_configuration/packer/templates/ubuntu-24.04/packer.pkrvars.hcl):
   ```hcl
   iso_paths = [
     "[DS_100_3] contentlib-a0bc3584-8b7c-40cc-b2fd-bae7a6b9bf6c/befc5a25-2315-479a-833a-2cc168de715c/ubuntu-24.04.4-live-server-amd64_58a8cfa8-32e5-437c-b161-b18e4dc8d7aa.iso"
   ]
   ```

---

### 3.2. Sự cố 2 (INC-02): Máy chủ HTTP của Packer liên kết vào card mạng loopback nội bộ của WSL

#### Hiện tượng
Máy ảo trên ESXi khởi động file ISO thành công nhưng không thể tải file `user-data` qua mạng. Màn hình console dừng tại giao diện lựa chọn ngôn ngữ cài đặt Subiquity.

#### Phân tích nguyên nhân
Trong môi trường WSL 2, hệ điều hành Linux con sở hữu card mạng ảo riêng. Khi Packer khởi chạy máy chủ HTTP phục vụ file cấu hình, Packer tự động chọn địa chỉ IP đầu tiên phát hiện được, thường là `10.255.255.254` (giao diện loopback nội bộ của WSL). Máy ảo ESXi nằm trên phân vùng mạng vật lý (`<NETWORK_SUBNET>`) hoàn toàn không có tuyến định tuyến tới dải mạng ảo này của WSL. Khi truy vấn HTTP thất bại, Subiquity hủy tiến trình tự động và quay về chế độ tương tác thủ công.

#### Giải pháp khắc phục
Chỉ định rõ ràng địa chỉ IP vật lý của máy trạm có thể định tuyến được từ mạng ESXi trong tệp cấu hình:
```hcl
http_bind_address = "0.0.0.0"
http_ip           = "10.255.245.20"
```

---

### 3.3. Sự cố 3 (INC-03): Tường lửa Windows Host và WSL chặn luồng gói tin HTTP đi vào

#### Hiện tượng
Mặc dù đã chỉ định đúng IP máy trạm `10.255.245.20`, máy ảo ESXi vẫn nhận phản hồi `Connection timed out` khi gửi bản tin HTTP GET tới cổng do Packer mở (dải cổng 8120–8130).

#### Phân tích nguyên nhân
Hệ điều hành Windows 11 kích hoạt Windows Defender Firewall chặn các kết nối lạ đi vào cổng ngẫu nhiên. Đồng thời, cấu hình tường lửa bên trong WSL cũng có thể hạn chế chuyển tiếp gói tin từ host Windows vào không gian mạng WSL.

#### Giải pháp khắc phục
1. Khởi tạo luật tường lửa cho phép trên Windows Host bằng PowerShell quyền Administrator:
   ```powershell
   New-NetFirewallRule -DisplayName "Packer HTTP Listener" -Direction Inbound -LocalPort 8120-8130 -Protocol TCP -Action Allow
   ```
2. Cho phép lưu lượng trong WSL:
   ```bash
   sudo ufw allow 8120:8130/tcp
   sudo iptables -I INPUT -p tcp --dport 8120:8130 -j ACCEPT
   ```

---

### 3.4. Sự cố 4 (INC-04): Lỗi không tìm thấy nhân Linux trong dòng lệnh GRUB

#### Hiện tượng
Khi gửi chuỗi phím `c` vào menu GRUB để mở cửa sổ dòng lệnh và nhập đường dẫn kernel:
```text
linux /casper/vmlinuz --- autoinstall ...
```
Màn hình máy ảo báo lỗi:
```text
error: file '/casper/vmlinuz' not found.
```

#### Phân tích nguyên nhân
Khi khởi động ở chế độ UEFI, biến môi trường `root` của GRUB chưa được định nghĩa trỏ tới ổ đĩa CD-ROM. Đường dẫn `/casper/vmlinuz` được tìm kiếm trên ổ đĩa ảo trắng (chưa phân vùng), dẫn tới lỗi không tìm thấy file.

#### Giải pháp khắc phục
Sử dụng lệnh `search` của GRUB để tự động dò tìm phân vùng chứa kernel thay vì giả định ổ đĩa:
```hcl
"search --set=root --file /casper/vmlinuz<enter><wait>"
```

---

### 3.5. Sự cố 5 (INC-05): Hết hạn thời gian đếm ngược của menu GRUB trước khi gửi phím

#### Hiện tượng
Khi thiết lập `boot_wait = "10s"`, máy ảo tự động vào quy trình khởi động mặc định trước khi chuỗi phím trong `boot_command` kịp truyền tới.

#### Phân tích nguyên nhân
Tệp cấu hình `/boot/grub/grub.cfg` trên ISO Ubuntu 24.04 thiết lập thời gian chờ đếm ngược là 5 giây (`set timeout=5`). Khoảng chờ 10 giây vượt quá thời gian đếm ngược của GRUB. Ngược lại, nếu đặt `boot_wait = "3s"`, tiến trình khởi động POST của UEFI firmware trên VMware chưa hoàn tất, khiến các phím bấm ban đầu bị hypervisor bỏ rơi.

#### Giải pháp khắc phục
1. Thiết lập `boot_wait = "3s"` hoặc `"5s"` phù hợp với thời điểm vừa hiện menu GRUB.
2. Gửi một phím mũi tên (ví dụ: `<down><wait><up><wait>`) để lập tức đóng băng (freeze) bộ đếm thời gian 5 giây của GRUB, loại bỏ hoàn toàn nguy cơ tranh chấp thời gian trước khi thực thi lệnh kế tiếp.

---

### 3.6. Sự cố 6 (INC-06): Curtin Installer dừng với mã lỗi thoát 100 do tải gói ngoài

#### Hiện tượng
Trình cài đặt Subiquity bị dừng đột ngột giữa chừng với thông báo lỗi:
```text
An error occurred during installation:
cmd: ['curtin', 'system-install', ...] chrony returned non-zero exit status 100.
```

#### Phân tích nguyên nhân
Cấu hình `user-data` chứa khai báo tải thêm gói phần mềm và cập nhật an ninh qua Internet (`packages: [open-vm-tools, chrony]`, `updates: security`). Trong khi đó, máy chủ DHCP của mạng ảo cấp IP nhưng không cung cấp địa chỉ DNS, hoặc hệ thống mạng lab bị cô lập với Internet. Lệnh `apt-get update` bên trong môi trường chroot `/target` không thể phân giải tên miền kho lưu trữ của Canonical, khiến tiến trình cài đặt thất bại.

#### Giải pháp khắc phục
1. Bổ sung máy chủ DNS tĩnh vào cấu hình mạng của `user-data`.
2. Loại bỏ khối khai báo `packages:` và `updates:` trong `user-data` để quá trình cài đặt hệ điều hành gốc đạt trạng thái thuần ngoại tuyến (offline) 100% từ ảnh nén squashfs của ISO.
3. Chuyển các tác vụ cài đặt gói bổ sung sang giai đoạn provisioner của Packer thông qua các kịch bản shell chuyên trách (`scripts/01_install_open_vm_tools.sh`).

---

### 3.7. Sự cố 7 (INC-07): Lệch tên card mạng trong cấu hình Netplan (`ens192` so với `ens160`)

#### Hiện tượng
Quá trình cài đặt hoàn tất và máy ảo khởi động lại thành công tới màn hình đăng nhập, nhưng Packer bị treo tại thông báo:
```text
==> vsphere-iso.ubuntu: Waiting for SSH to become available...
```
Sau 30 phút, tiến trình build bị timeout. Trên vCenter, máy ảo hiển thị trạng thái `IP Address: None`.

#### Phân tích nguyên nhân
Tệp cấu hình Netplan ban đầu chỉ định cứng tên giao diện mạng là `ens192`. Trên VMware ESXi chạy firmware EFI kết hợp card mạng VMXNET3, nhân Linux gán tên giao diện mạng dựa trên sơ đồ topology PCI thực tế, khiến card mạng nhận tên là `ens160` (hoặc `ens33`, `ens224`). Do file cấu hình không có định nghĩa cho `ens160`, hệ điều hành không kích hoạt DHCP cho card mạng, dẫn tới máy ảo không nhận được IP và Packer không thể kết nối SSH.

#### Giải pháp khắc phục
Sử dụng tính năng khớp mẫu (pattern matching) của Netplan trong `http/user-data`:
```yaml
network:
  version: 2
  ethernets:
    all-en-interfaces:
      match:
        name: "en*"
      dhcp4: true
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```
Khai báo này tự động áp dụng cấu hình DHCP cho bất kỳ card mạng Ethernet nào có tên bắt đầu bằng ký tự `en`, bảo đảm hoạt động chính xác trên mọi phiên bản phần cứng ảo hóa.

---

### 3.8. Sự cố 8 (INC-08): Quy chuẩn đóng gói template trong môi trường hoàn toàn cô lập (Air-Gapped)

#### Hiện tượng
Yêu cầu đóng gói template trong trung tâm dữ liệu cô lập không có đường ra Internet.

#### Phân tích và kiến trúc giải pháp
Quy trình đóng gói template hỗ trợ hoạt động ngoại tuyến hoàn toàn dựa trên các nguyên tắc:
1. File ISO cài đặt gốc chứa đầy đủ hệ điều hành và gói công cụ ảo hóa cơ sở trong file nén `filesystem.squashfs`.
2. Cấu hình Subiquity không kích hoạt các tác vụ truy vấn ra Internet.
3. Đồng bộ thời gian qua máy chủ NTP nội bộ của doanh nghiệp thay vì các pool công cộng.
4. Thiết lập Cloud-Init giới hạn datasource nội bộ (`datasource_list: [ VMware, NoCloud, None ]`), ngăn chặn việc máy ảo bị trễ khi cố gắng truy vấn các endpoint metadata công cộng (như `169.254.169.254`).

---

### 3.9. Sự cố 9 (INC-09): Subiquity Curtin bị treo hơn 30 phút tại bước `installing-kernel`

#### Hiện tượng
Subiquity phân vùng đĩa và giải nén hệ điều hành thành công, nhưng bị treo liên tục hơn 30 phút tại bước:
```text
start: subiquity/Install/install/curtin_install/run_curtin_step/cmd-install/stage-curthooks/builtin/cmd-curthooks/installing-kernel: installing kernel
```
Sau đó Packer hủy tiến trình do hết hạn thời gian chờ SSH (`ssh_timeout = "30m"`).

#### Phân tích nguyên nhân
Trong quy trình của Curtin (`curtin/commands/curthooks.py`), module kiểm tra gói `linux-generic`. Mặc dù file squashfs đã có sẵn nhân Linux compiled, gói meta `linux-generic` chưa được đánh dấu là đã cài đặt. Curtin kích hoạt lệnh `apt-get install -y linux-generic`.
Trong môi trường mạng không có tuyến ra Internet nhưng không trả về cờ từ chối ngay (TCP RST), các yêu cầu kết nối tới kho lưu trữ Canonical bị drop gói âm thầm. Trình APT thử lần lượt 4 địa chỉ IPv4 và 4 địa chỉ IPv6 với thời gian chờ SYN timeout là 120 giây cho mỗi địa chỉ, dẫn đến tổng thời gian treo vượt quá 40 phút.

#### Giải pháp khắc phục
1. Kích hoạt cờ ngoại tuyến cho APT trong `http/user-data`:
   ```yaml
   apt:
     fallback: offline-install
     geoip: false
     mirror-selection:
       primary: []
   ```
2. Loại bỏ các máy chủ DNS ngoài không thể định tuyến.
3. Khi bật `fallback: offline-install`, Curtin bỏ qua việc truy vấn các mirror bên ngoài và sử dụng trực tiếp kernel có sẵn trong file nén squashfs, rút ngắn thời gian xử lý bước này xuống dưới 10 giây.

---

### 3.10. Sự cố 10 (INC-10): Lỗi xác thực cú pháp JSON Schema của Subiquity và tự động hạ cấp xuống giao diện thủ công

#### Hiện tượng
Máy ảo tải thành công `user-data` qua mạng nhưng không kích hoạt cài đặt tự động mà quay trở lại màn hình thủ công yêu cầu chọn ngôn ngữ và bàn phím.

#### Phân tích nguyên nhân
Subiquity sử dụng bộ phân tích cú pháp xác thực từng cấu trúc dữ liệu theo schema JSON chuẩn (`subiquity/models/autoinstall.py`). Do sơ suất trong quá trình soạn thảo, tệp YAML bị lặp hai tầng khóa `network:`:
```yaml
network:
  network:
    version: 2
    ethernets: ...
```
Bộ xác thực của Subiquity phát hiện thuộc tính không hợp lệ (`Additional properties are not allowed ('network' was unexpected)`). Khi gặp lỗi cú pháp, Subiquity không dừng khẩn cấp mà tự động chuyển sang chế độ dự phòng thủ công (DataSourceNone) để người dùng tiếp tục thao tác bằng tay.

#### Giải pháp khắc phục
Chuẩn hóa cấu trúc Netplan đặt trực tiếp `version: 2` dưới khóa `autoinstall.network`:
```yaml
network:
  version: 2
  ethernets:
    all-en-interfaces:
      match:
        name: "en*"
      dhcp4: true
```
Kiểm tra cú pháp dữ liệu bằng script Python trước khi đưa vào cấu hình build:
```bash
python3 -c "import yaml; data = yaml.safe_load(open('http/user-data')); assert 'version' in data['autoinstall']['network']"
```

---

### 3.11. Sự cố 11 (INC-11): Lời nhắc xác nhận cài đặt chặn đứng quy trình tự động và giải pháp chuyển đổi sang đĩa CD-ROM ảo `cidata`

#### Hiện tượng
Khi khởi động, Subiquity đọc được cấu hình nhưng dừng lại với lời nhắc:
```text
Confirmation is required to continue.
Add 'autoinstall' to your kernel command line to avoid this
Continue with autoinstall? (yes|no)
```
Tiến trình cài đặt bị dừng chờ kỹ sư nhập `yes` trên bàn phím máy ảo.

#### Phân tích nguyên nhân
1. Khi dùng phương pháp chỉnh sửa menu GRUB bằng phím `e`, việc điều hướng con trỏ bằng các phím mũi tên xuống dễ bị lệch dòng giữa các phiên bản ISO khác nhau. Từ khóa `autoinstall` bị gắn vào dòng không mong muốn, khiến tham số này không vào được nhân Linux (`/proc/cmdline`).
2. Cơ chế an toàn của Subiquity: Khi phát hiện có cấu hình autoinstall nhưng dòng lệnh nạp kernel không chứa cờ `autoinstall`, trình cài đặt sẽ dừng lại yêu cầu người dùng xác nhận để tránh việc ghi đè ngoài ý muốn lên hệ điều hành đang có trên ổ đĩa.
3. Việc phục vụ file qua máy chủ HTTP của Packer luôn tiềm ẩn nguy cơ lỗi định tuyến mạng máy trạm.

#### Giải pháp khắc phục dứt điểm
1. **Chuyển đổi sang phương thức nạp cấu hình qua ổ đĩa CD-ROM ảo (cidata)**:
   Packer tích hợp sẵn tính năng tự động đóng gói thư mục `http/` thành một file ISO và gắn làm ổ đĩa CD-ROM thứ hai trên máy ảo với nhãn `cidata`:
   ```hcl
   cd_files = ["${path.root}/http/user-data", "${path.root}/http/meta-data"]
   cd_label = "cidata"
   ```
2. **Khởi động bằng giao diện dòng lệnh GRUB `c` và tự động tìm thiết bị**:
   ```hcl
   boot_command = [
     "c<wait>",
     "search --set=root --file /casper/vmlinuz<enter><wait>",
     "linux /casper/vmlinuz --- autoinstall ds=nocloud<enter><wait5s>",
     "initrd /casper/initrd<enter><wait5s>",
     "boot<enter>"
   ]
   ```
Lệnh này đảm bảo kernel luôn nhận được tham số `autoinstall ds=nocloud`, triệt tiêu hoàn toàn lời nhắc xác nhận và không phụ thuộc vào bất kỳ kết nối mạng nào trong giai đoạn cài đặt hệ điều hành.

### 3.12. Sự cố 12 (INC-12): Khóa tệp Content Library trên Datastore dẫn đến lỗi No Media trên ổ đĩa CD-ROM EFI

#### Hiện tượng
Quá trình khởi động máy ảo Rocky Linux 9 (hoặc các bản phân phối Linux chạy EFI) dừng tại màn hình EFI firmware với thông báo:
```text
EFI VMware Virtual SATA CDROM Drive (0.0)... No Media
EFI VMware Virtual SATA CDROM Drive (1.0)... No Media
```
Trình cài đặt Anaconda Kickstart không thể khởi động, dẫn đến việc Packer dừng chờ địa chỉ IP (`Waiting for IP...`) cho đến khi vượt quá thời gian chờ (`timeout`).

#### Phân tích nguyên nhân
1. **Khóa tệp trên Content Library**: Khi sử dụng công cụ `govc library.info -L -l` để phân giải tệp ISO trong Content Library, hệ thống nhận được đường dẫn nội bộ tầng Datastore dạng:
   ```text
   [DatastoreName] contentlib-<library-uuid>/<item-uuid>/filename.iso
   ```
   Thư mục `contentlib-*` trên Datastore do vSphere Content Library Service trực tiếp quản lý cơ chế khóa tệp (file lease/lock). Khi máy ảo được bật nguồn bởi ESXi host, cơ chế khóa này ngăn cản tiến trình ảo hóa gắn kết tệp ISO vào ổ đĩa quang ảo ở tầng phần cứng, khiến ổ CD-ROM SATA 0.0 rơi vào trạng thái không có phương tiện lưu trữ (`No Media`).
2. **Sai lệch đường dẫn Datastore thực tế**: Trường hợp người dùng cấu hình đường dẫn trực tiếp trên Datastore dạng `[DatastoreName] filename.iso` (thư mục gốc) nhưng tệp thực tế nằm trong thư mục con (ví dụ: `[DatastoreName] iso/filename.iso`):
   vCenter vẫn khởi tạo cấu hình VM thành công nhưng khi bật nguồn, ESXi không tìm thấy tệp ISO để mount. ESXi tự động ngắt kết nối ổ ảo (`connected = false`), dẫn đến hiện tượng EFI firmware báo `No Media` khi quét ổ đĩa khởi động.
3. **Ổ đĩa Kickstart phụ**: Ổ đĩa thứ hai (SATA 1.0) chứa tệp Kickstart tạm thời do Packer sinh ra (`cd_content`), không chứa bộ khởi động UEFI bootloader (`/EFI/BOOT/BOOTX64.EFI`) nên EFI firmware bỏ qua và báo `No Media`, tiếp tục rơi xuống ổ đĩa cứng trống và treo tại `EFI Network...` (PXE boot).
4. **Thiếu bước tiền kiểm tra (Pre-flight Check)**: Tiến trình build trước đây chưa xác minh sự tồn tại của tệp ISO thông qua govc API trước khi chạy Packer, dẫn đến việc chỉ phát hiện lỗi sau khi VM đã bật nguồn và hết thời gian chờ (`timeout`).

#### Giải pháp khắc phục
1. **Chuẩn hóa cú pháp Content Library trong biến `iso_paths`**:
   Thay thế đường dẫn raw datastore bằng cú pháp chuẩn được `packer-plugin-vsphere` hỗ trợ trực tiếp qua vSphere Content Library API:
   ```hcl
   iso_paths = [
     "Tên_Content_Library/Tên_Item/Tên_Tệp.iso"
   ]
   ```
   hoặc:
   ```hcl
   iso_paths = [
     "Tên_Content_Library/Tên_Item"
   ]
   ```
   Khi sử dụng cú pháp này, Packer gọi trực tiếp Content Library API để gán tệp ISO vào thiết bị CD-ROM mà không truy cập trực tiếp vào hệ thống tệp bị khóa trên VMFS.
2. **Tiền kiểm tra tự động tệp ISO trước khi build (`validate_packer_iso_path`)**:
   Tích hợp hàm `validate_packer_iso_path` vào `packer/build.sh`. Trước khi khởi chạy Packer, hệ thống tự động kiểm tra sự tồn tại của tệp ISO:
   - Với Datastore: Thực thi `govc datastore.ls -ds="<DS>" "<PATH>"`. Nếu không tìm thấy, tự động quét đệ quy (`govc datastore.ls -R`) để tìm tệp ISO trùng tên và đề xuất tự động sửa đường dẫn (ví dụ: từ `[DS] Rocky.iso` sang `[DS] iso/Rocky.iso`).
   - Với Content Library: Thực thi `govc library.ls "/<Library>/<Item>"`.
3. **Mềm hóa loại bộ điều khiển CD-ROM (`vm_cdrom_type`)**:
   Khai báo biến `vm_cdrom_type` trong `variables.pkr.hcl` (mặc định `"sata"` cho Rocky Linux và `"ide"` cho Ubuntu), cho phép linh hoạt cấu hình theo từng loại phần cứng ảo thay vì cố định cứng trong mã HCL.
4. **Cấu hình thứ tự khởi động firmware (`boot_order`)**:
   Thiết lập tường minh `boot_order = "cdrom,disk"` thay vì `"disk,cdrom"`, đảm bảo ổ CD-ROM chứa ISO cài đặt được ưu tiên kiểm tra trước đĩa cứng trống.
5. **Định danh nhãn ổ đĩa Kickstart (`cd_label`)**:
   Bổ sung thuộc tính `cd_label = "OEMDRV"` cho ổ đĩa quang phụ sinh từ `cd_content`, cho phép Anaconda tự động phát hiện tệp cấu hình cài đặt không giám sát `ks.cfg`.

---

## 4. Quy trình kiểm tra và xác nhận chất lượng bản mẫu

Sau khi hoàn tất quá trình đóng gói, thực hiện kiểm tra bản mẫu máy ảo `tpl-ubuntu-2404-golden` trên vCenter:

1. **Trạng thái công cụ ảo hóa**:
   ```bash
   systemctl is-active open-vm-tools.service
   vmtoolsd --version
   ```
   Kết quả mong muốn: Trạng thái trả về `active` và hiển thị phiên bản Open-VM-Tools.

2. **Xác nhận tổng quát hóa hệ thống (OS Generalization)**:
   - Kiểm tra định danh máy: File `/etc/machine-id` phải có kích thước 0 byte trước khi clone.
   - Kiểm tra khóa SSH host: Thư mục `/etc/ssh/` không còn các file khóa cũ (`ssh_host_*_key`). Hệ điều hành tự sinh cặp khóa mới khi máy ảo nhân bản khởi động lần đầu.
   - Dọn sạch bộ nhớ đệm gói và log tạm thời: Đảm bảo dung lượng đĩa ảo ở mức tối ưu.

3. **Tính sẵn sàng của Cloud-Init**:
   ```bash
   cloud-init status
   ```
   Kết quả hiển thị: `status: done` hoặc `status: disabled` tuân theo cấu hình nhường quyền cho tiến trình VMware Guest Customization.
