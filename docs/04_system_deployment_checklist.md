# Kế hoạch và checklist triển khai hệ thống tự động hóa hạ tầng VMware và Elastic Stack

Tài liệu này đặc tả kế hoạch triển khai, checklist điều kiện tiên quyết, quy trình thực thi và xử lý sự cố cho hệ thống tự động hóa cung ứng hạ tầng VMware vSphere và Elastic Stack phân tán chuẩn HA.

---

## 1. Tổng quan kiến trúc và luồng điều phối

### 1.1. Mục tiêu hệ thống
- Tự động hóa khép kín: Khởi tạo Seed host, quản lý ISO, triển khai VCSA (nếu cần).
- Đóng gói Golden Image Ubuntu 24.04 bằng Packer.
- Cung ứng tài nguyên ảo hóa (Network, VM, DRS Anti-Affinity) bằng Terraform.
- Cấu hình cụm Elasticsearch HA 8.x (mTLS), Kibana Gateway và Fleet Server bằng Ansible.
- Kích hoạt ILM, Elastic Agent thu thập OS metrics và FortiGate Syslog UDP 9004.
- Thiết lập sao lưu/phục hồi qua SLM.

### 1.2. Kiến trúc và Định cỡ tài nguyên

- **Triết lý**: Tách biệt logic core (Packer, Terraform, Ansible) và cấu hình môi trường (`vars.conf`, `terraform.tfvars`, `hosts.yml`).
- **Phân bổ Node**:
  - *Elasticsearch Cluster*: Tối thiểu 3 nút để đảm bảo HA và tránh Split-Brain. Tên mẫu: `<PREFIX>-elastic-<INDEX>`.
  - *Kibana Gateway / Fleet*: Máy chủ trung gian quản lý và thu thập log. Tên mẫu: `<PREFIX>-kibana-gw`.

**Khung định cỡ tài nguyên chuẩn hóa:**

| Tiêu chí | Dev / Lab (< 1K EPS) | Standard Prod (5K-15K EPS) | Enterprise (> 30K EPS) |
| :--- | :--- | :--- | :--- |
| **Node Elasticsearch** | 3 nút tích hợp | 3 nút tích hợp hoặc tách rời | 3 Master + 3-6 Data Hot + Warm/Cold |
| **Cấu hình ES Node** | 2-4 vCPU, 4-8 GB RAM, 50 GB PVSCSI | 4-8 vCPU, 16-32 GB RAM, 200-500 GB SSD | 8-16 vCPU, 64 GB RAM, 1-2 TB NVMe RAID 10 |
| **Cấu hình Gateway** | 1 nút: 2 vCPU, 4 GB RAM, 40 GB PVSCSI | 1-2 nút: 4 vCPU, 8 GB RAM, 60-100 GB | 2 nút HA (LB): 8 vCPU, 16 GB RAM, 100 GB SSD |
| **Ghi chú JVM Heap** | \<= 50% RAM vật lý, tối đa 31 GB (Compressed OOPs). |

**Các biến hạ tầng chính:** `SITE_VCSA_IP`, `VCENTER_DC`, `ISO_DATASTORE`, `PKR_NETWORK`, `vms` (Terraform map).

### 1.3. Luồng điều phối toàn trình và cấu trúc menu

Hệ thống cung cấp hai điểm truy cập điều phối kịch bản chính:

1. **Kịch bản điều phối tổng thể nền tảng ([`run.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/run.sh))**:
   - Quản lý tập trung toàn bộ nền tảng tự động hóa đa sản phẩm.
   - Menu chính cấp 1 (Top-level orchestrator):
     ```text
     ==============================================================================
     HỆ THỐNG QUẢN LÝ HẠ TẦNG VMWARE - MENU ĐIỀU PHỐI TỔNG THỂ
     ==============================================================================
     1) Công cụ nền tảng (Platform Tools: Packer, Terraform, ISO, Seed)
     2) Triển khai Elastic Stack (SIEM, Observability, Fleet HA)
     3) Triển khai Zabbix Server             [Khung mở rộng]
     4) Triển khai HAProxy / Load Balancer   [Khung mở rộng]
     5) Triển khai dịch vụ hạ tầng mạng     [Khung mở rộng]
     0) Thoát chương trình
     ```
   - Nhánh `1) Công cụ nền tảng`: Cho phép chọn xây dựng template Packer bất kỳ (`packer/build.sh --template <tên>`), cấp phát hạ tầng qua Terraform profile bất kỳ (`terraform/profiles/<profile>/run.sh`), quản lý tệp ISO (`seed/download_iso.sh`, `seed/upload_iso.sh`) và cài đặt môi trường công cụ máy trạm (`seed/setup_env.sh`).
   - Nhánh `2) Triển khai Elastic Stack`: Điều hướng thẳng vào menu chuyên biệt của sản phẩm Elastic Stack (`products/elastic-stack/menu.sh`).

2. **Kịch bản điều phối tương thích ngược ([`run_all_onclick.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/run_all_onclick.sh))**:
   - Đóng vai trò wrapper tương thích ngược cho các quy trình vận hành hoặc kỹ sư quen thuộc với phiên bản trước.
   - Nạp các thư viện nền tảng (`lib/common.sh`, `lib/secrets.sh`, `lib/vsphere.sh`), khởi tạo phiên bảo vệ `tmux` và chuyển thẳng vào menu điều phối Elastic Stack:
     ```text
     ==============================================================================
     TRIỂN KHAI ELASTIC STACK - MENU ĐIỀU PHỐI SẢN PHẨM
     ==============================================================================
     1) Chạy toàn bộ quy trình (Đầu - Cuối: Packer -> Terraform -> Ansible -> Observability)
     2) Chỉ tạo Golden Template (Packer)
     3) Chỉ cấp phát hạ tầng (Terraform Provisioning)
     4) Chỉ cấu hình ứng dụng (Ansible Configuration)
     5) Tích hợp giám sát hạ tầng VMware vSphere
     6) Hoàn tác giám sát hạ tầng VMware vSphere
     7) Cấu hình tham số & đồng bộ các tệp cấu hình
     0) Quay lại / Thoát
     ```

Sơ đồ gọi kịch bản toàn trình:
```text
[run.sh / run_all_onclick.sh]
 │
 ├── [Platform Tools Menu]
 │    ├── seed/setup_env.sh                        (Cài đặt công cụ IaC: Packer, TF, Ansible, govc)
 │    ├── seed/download_iso.sh                     (Tải ISO Ubuntu/VCSA kèm kiểm tra SHA256)
 │    ├── seed/upload_iso.sh                       (Đẩy ISO lên Datastore / Content Library)
 │    ├── packer/build.sh                          (Đóng gói Golden Template OS)
 │    └── terraform/profiles/<profile>/run.sh      (Cấp phát hạ tầng máy ảo theo profile)
 │
 └── [Elastic Stack Menu: products/elastic-stack/menu.sh]
      ├── products/elastic-stack/configure.sh      (Thu thập tham số & đồng bộ biến cấu hình)
      ├── packer/build.sh --template ubuntu-24.04  (Tạo template Ubuntu 24.04 cho Elastic)
      ├── terraform/profiles/elastic-stack/run.sh  (Cung ứng cụm 4 máy ảo & DRS Anti-Affinity)
      ├── ansible/products/elastic-stack/run_deploy.sh (Cấu hình ES HA 3-node & Kibana Gateway)
      ├── ansible/products/elastic-stack/run_observability.sh (Kích hoạt Fleet, ILM & Syslog UDP)
      ├── products/elastic-stack/scripts/manage_vsphere_observability.sh (Giám sát vSphere / Rollback)
      └── ansible/products/elastic-stack/run_backup.sh (Cấu hình SLM Snapshot & Khôi phục)
```

## 2. Checklist điều kiện tiên quyết

### 2.1. Hạ tầng VMware vSphere
- [ ] **ESXi Host**: Tối thiểu 2 host (nếu dùng DRS Anti-Affinity). Bản 7.0U3 hoặc 8.0.
- [ ] **Datastore**: Trống tối thiểu 250 GB. Tên khớp với `ISO_DATASTORE` và `vsphere_datastore`.
- [ ] **Network**: vSwitch/vDS đã kết nối uplink. Định tuyến VLAN đầy đủ.
- [ ] **Quyền vCenter**: Tài khoản có quyền quản trị hoặc các quyền tối thiểu để tạo/quản lý Datastore, Network, VM.

### 2.2. Tường lửa và Network (Firewall Matrix)
| Cổng/Giao thức | Nguồn -> Đích | Mục đích |
| :--- | :--- | :--- |
| `TCP/443`, `902` | Trạm điều khiển -> vCenter/ESXi | API vSphere, upload ISO, truyền đĩa |
| `TCP/22` | Trạm điều khiển -> Tất cả VM | SSH/Ansible quản trị |
| `TCP/9200` | Nội bộ mạng VM, Kibana -> ES Nodes | REST API Elasticsearch |
| `TCP/9300` | ES Nodes -> ES Nodes | Đồng bộ cụm (mTLS) |
| `TCP/5601` | Mạng quản trị -> Kibana Gateway | Giao diện Kibana |
| `TCP/8220` | Tất cả VM -> Fleet Server | Quản lý Elastic Agent |
| `UDP/9004` | FortiGate -> Gateway | Nhận FortiGate Syslog |
| `UDP/9525` | ESXi Hosts & vCenter -> Gateway | Nhận VMware vSphere Syslog |
| `UDP/123`, `53` | Tất cả VM -> NTP, DNS | Đồng bộ thời gian, phân giải tên miền |

### 2.3. Trạm điều khiển (Seed Station)
- [ ] OS: Ubuntu 22.04/24.04 hoặc WSL2.
- [ ] Công cụ: `terraform` (>=1.5), `packer` (>=1.9), `ansible` (>=2.15), `govc`, `tmux`, `jq`.
- [ ] Khóa SSH RSA/ED25519 đã được tạo (`~/.ssh/id_ed25519`).

---

## 3. Quy trình thực thi chi tiết từng giai đoạn

### Giai đoạn 0: Khởi tạo máy trạm điều khiển và quản lý ISO

#### 1. Cài đặt môi trường công cụ IaC
- **Kịch bản thực thi**: [`seed/setup_env.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/setup_env.sh)
- **Vai trò kỹ thuật**: Cài đặt trọn bộ công cụ tự động hóa trên hệ điều hành Ubuntu/Debian trạm điều khiển.
- **Giao diện hiển thị**: Quá trình cài đặt APT, tải GPG key và thông báo xác nhận phiên bản.
- **Thao tác người dùng**: Chạy với quyền `sudo`:
  ```bash
  cd seed && sudo ./setup_env.sh
  ```
- **Cơ chế hoạt động**:
  1. Thêm kho phần mềm chính thức của HashiCorp (`apt.releases.hashicorp.com`).
  2. Cài đặt các gói `packer`, `terraform`, `ansible`, `jq`, `tmux`, `python3-pip`.
  3. Tải bản phân phối nhị phân của `govc` từ GitHub Release và đặt vào `/usr/local/bin/govc`.
  4. Cài đặt các thư viện Python VMware: `pyvmomi`, `requests`.
- **Kết quả đầu ra**: Các lệnh `terraform version`, `packer version`, `ansible --version`, `govc version` hoạt động bình thường trên terminal.

#### 2. Tải tệp ISO hệ điều hành
- **Kịch bản thực thi**: [`seed/download_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/download_iso.sh)
- **Vai trò kỹ thuật**: Tải ISO cài đặt chuẩn từ máy chủ nguồn kèm kiểm tra tính toàn vẹn SHA256.
- **Thao tác người dùng**: Chọn cờ hệ điều hành cần tải:
  ```bash
  ./seed/download_iso.sh --ubuntu
  ```
- **Cơ chế hoạt động**: Kịch bản lưu ISO vào thư mục tạm `iso_cache/`, hỗ trợ tính năng tiếp tục tải khi đứt kết nối (`curl -C -`), và tự động so khớp mã băm với giá trị checksum công bố từ nhà cung cấp.
- **Kết quả đầu ra**: Tệp `iso_cache/ubuntu-24.04.1-live-server-amd64.iso` toàn vẹn trên máy trạm.

#### 3. Đẩy ISO lên Datastore vSphere
- **Kịch bản thực thi**: [`seed/upload_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/upload_iso.sh)
- **Vai trò kỹ thuật**: Đẩy ISO từ máy trạm lên Datastore đích hoặc nạp vào Content Library thông qua vSphere API.
- **Thao tác người dùng**:
  ```bash
  ./seed/upload_iso.sh -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso -d "datastore1" -p "iso"
  ```
- **Cơ chế hoạt động**: Sử dụng `govc datastore.upload` để truyền tệp qua HTTPS port 443 tới vCenter/ESXi.
- **Kết quả đầu ra**: Tệp `[datastore1] iso/ubuntu-24.04.1-live-server-amd64.iso` hiển thị trên vSphere Client.

---

### Giai đoạn chuẩn bị cấu hình sản phẩm (Configuration & Secrets In-Memory)

- **Kịch bản thực thi**: [`products/elastic-stack/configure.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/products/elastic-stack/configure.sh)
- **Vai trò kỹ thuật**: Thu thập tham số mạng, thông tin định danh vCenter, đồng bộ tệp cấu hình và quản lý mật khẩu in-memory.
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  THIẾT LẬP THÔNG SỐ VẬN HÀNH ELASTIC STACK
  ==============================================================================
  Địa chỉ IP vCenter Server: 
  Tên Datacenter vSphere: 
  Tên Datastore lưu ISO: 
  ...
  ```
- **Thao tác người dùng**: Nhập thông số trực tiếp hoặc xác nhận giữ nguyên các giá trị mặc định được gợi ý trong ngoặc vuông `[...]`. Nhập mật khẩu quản trị vCenter và mật khẩu SSH máy ảo qua cơ chế ẩn ký tự (`read -s`).
- **Cơ chế hoạt động**:
  1. Ghi nhận tham số vào `products/elastic-stack/product.conf`.
  2. Nạp cấu hình mẫu và thay thế giá trị biến sang:
     - `packer/templates/ubuntu-24.04/packer.pkrvars.hcl`
     - `terraform/profiles/elastic-stack/terraform.tfvars`
     - `ansible/products/elastic-stack/inventories/lab/hosts.yml`
     - `ansible/products/elastic-stack/inventories/lab/group_vars/all/shared_env.yml`
  3. Mật khẩu nhạy cảm (`VCENTER_PASS`, `SSH_PASS`, `ELASTIC_PASS`) chỉ được xuất (`export`) tạm thời trong RAM của phiên làm việc hiện tại, không ghi vào bất kỳ tệp cấu hình nào trên đĩa.
- **Kết quả đầu ra**: Tất cả các tệp cấu hình sẵn sàng, không còn chứa các biến giả định dạng `<PLACEHOLDER>`.

---

### Giai đoạn 1: Đóng gói Golden Template (Packer)

- **Kịch bản thực thi**: [`packer/build.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/packer/build.sh) `--template ubuntu-24.04`
- **Vai trò kỹ thuật**: Tự động cài đặt máy ảo Ubuntu 24.04 từ ISO, tối ưu hóa hệ thống, dọn dẹp định danh và chuyển đổi thành vSphere VM Template.
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  TIẾN TRÌNH: ĐÓNG GÓI GOLDEN TEMPLATE (PACKER)
  ==============================================================================
  ==> vsphere-iso.ubuntu-2404: Creating VM...
  ==> vsphere-iso.ubuntu-2404: Starting HTTP server on port 8123...
  ==> vsphere-iso.ubuntu-2404: Waiting for SSH to become available...
  ==> vsphere-iso.ubuntu-2404: Connected to SSH!
  ==> vsphere-iso.ubuntu-2404: Provisioning with shell script...
  ==> vsphere-iso.ubuntu-2404: Converting VM into template...
  Build 'vsphere-iso.ubuntu-2404' finished after 8 minutes 42 seconds.
  ```
- **Thao tác người dùng**: Xác nhận thông số hoặc khởi chạy qua tùy chọn `2` trong menu Elastic Stack.
- **Cơ chế hoạt động**:
  1. Khởi tạo máy ảo trên ESXi/vCenter với ổ đĩa CDROM thứ hai mang nhãn `cidata` chứa tệp cấu hình `user-data` (Subiquity Autoinstall).
  2. Boot hệ thống qua GRUB command line chỉ định nguồn autoinstall.
  3. Đăng nhập SSH bằng tài khoản tạm thời, thực hiện:
     - Cài đặt `open-vm-tools`, cấu hình SSH key.
     - Dọn dẹp `cloud-init`, xóa `/etc/machine-id`, xóa DHCP leases (`/var/lib/dhcp/*`, `/var/lib/NetworkManager/*`).
  4. Tắt máy ảo và gọi API vCenter chuyển đổi VM thành Template `tpl-ubuntu-2404-golden`.
  5. Tự động đồng bộ tên template mới tạo vào `terraform.tfvars`.
- **Kết quả đầu ra**: Template `tpl-ubuntu-2404-golden` hiển thị trong vCenter Inventory.

---

### Giai đoạn 2: Cung ứng hạ tầng máy ảo (Terraform)

- **Kịch bản thực thi**: [`terraform/profiles/elastic-stack/run.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/terraform/profiles/elastic-stack/run.sh)
- **Vai trò kỹ thuật**: Khởi tạo thư mục VM, Port Group, clone 4 máy ảo từ Golden Template, cấu hình mạng tĩnh qua VMware guestinfo và thiết lập quy tắc DRS phân tán.
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  PRE-FLIGHT CHECK: KIỂM TRA TEMPLATE TRƯỚC KHI CẤP PHÁT (TERRAFORM)
  Template 'tpl-ubuntu-2404-golden' tồn tại và sẵn sàng trên vCenter.
  ==============================================================================
  Terraform will perform the following actions:
    + vsphere_virtual_machine.elastic_nodes["srv-elastic-01"]
    + vsphere_virtual_machine.elastic_nodes["srv-elastic-02"]
    + vsphere_virtual_machine.elastic_nodes["srv-elastic-03"]
    + vsphere_virtual_machine.kibana_gateway
    + vsphere_compute_cluster_vm_anti_affinity_rule.es_nodes_anti_affinity
  Plan: 5 to add, 0 to change, 0 to destroy.
  Do you want to perform these actions? (yes/no):
  ```
- **Thao tác người dùng**: Kiểm tra bảng kế hoạch và xác nhận bằng cách nhập `yes`.
- **Cơ chế hoạt động**:
  1. `check_vsphere_template`: Kiểm tra template đích trên vCenter qua `govc`.
  2. Thực thi `terraform init -upgrade` và `terraform apply`.
  3. Cấp phát tài nguyên ảo hóa:
     - Clone 3 node Elasticsearch (`srv-elastic-01`, `srv-elastic-02`, `srv-elastic-03`) và 1 node Gateway (`srv-kibana-gw`).
     - Bơm cấu hình IP tĩnh và DNS vào máy ảo thông qua cơ chế `extra_config` (`guestinfo.metadata` / `guestinfo.userdata`).
     - Tạo quy tắc `vsphere_compute_cluster_vm_anti_affinity_rule` buộc 3 node Elasticsearch phải phân bổ trên các máy chủ ESXi vật lý khác nhau trong cụm DRS.
  4. Trích xuất đầu ra `terraform output -json` và tự động cập nhật địa chỉ IP vào tệp inventory của Ansible (`hosts.yml`).
- **Kết quả đầu ra**: 4 máy ảo được bật nguồn (`poweredOn`), nhận đúng địa chỉ IP tĩnh và phản hồi gói tin ICMP ping.

---

### Giai đoạn 3: Cấu hình hệ điều hành và cụm Elasticsearch HA (Ansible)

- **Kịch bản thực thi**: [`ansible/products/elastic-stack/run_deploy.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/ansible/products/elastic-stack/run_deploy.sh)
- **Vai trò kỹ thuật**: Tối ưu hóa nhân hệ điều hành Linux, cài đặt cấu hình cụm Elasticsearch 3 node chuẩn bảo mật mTLS và cài đặt Kibana Gateway.
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  PRE-FLIGHT CHECK: KIỂM TRA KẾT NỐI MÁY ẢO TRƯỚC KHI CẤU HÌNH (ANSIBLE)
  Toàn bộ 4 máy ảo mục tiêu đều có thể kết nối mạng (Ping OK).
  ==============================================================================
  PLAY [Deploy Base Infrastructure & Dependencies] *****************************
  PLAY [Configure High-Availability Elasticsearch Cluster] *********************
  PLAY [Configure Kibana Gateway Server] ***************************************
  PLAY RECAP *******************************************************************
  srv-elastic-01 : ok=28   changed=12   unreachable=0    failed=0
  srv-elastic-02 : ok=28   changed=12   unreachable=0    failed=0
  srv-elastic-03 : ok=28   changed=12   unreachable=0    failed=0
  srv-kibana-gw  : ok=24   changed=10   unreachable=0    failed=0
  ```
- **Thao tác người dùng**: Nhập mật khẩu SSH và sudo của máy ảo nếu chưa có trong RAM, xác nhận `Y` để bắt đầu.
- **Cơ chế hoạt động**:
  1. Ping kiểm tra sẵn sàng mạng trên toàn bộ 4 địa chỉ IP.
  2. Thực thi playbook `playbooks/site_deploy.yml`:
     - Role `common`: Tắt swap, thiết lập `vm.max_map_count=262144`, cấu hình giới hạn file descriptors `nofile=65535` trong `/etc/security/limits.conf`.
     - Role `elasticsearch`: Tự động khởi tạo chứng chỉ Certificate Authority (CA) nội bộ, sinh keystore mTLS `elastic-certificates.p12` cho tầng truyền thông nội bộ cổng 9300, cấu hình `discovery.seed_hosts` và `cluster.initial_master_nodes`, thiết lập mật khẩu cho tài khoản siêu quản trị `elastic`.
     - Role `kibana`: Cài đặt Kibana trên `srv-kibana-gw`, cấu hình tài khoản kết nối `kibana_system`, sinh chuỗi mã hóa `xpack.security.encryptionKey` và khởi chạy dịch vụ cổng 5601.
- **Kết quả đầu ra**: Cụm Elasticsearch đạt trạng thái `green` (3/3 node hoạt động), giao diện Kibana mở cổng 5601.

---

### Giai đoạn 4: Kích hoạt trung tâm quan sát tập trung (Observability & Fleet)

- **Kịch bản thực thi**: [`ansible/products/elastic-stack/run_observability.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/ansible/products/elastic-stack/run_observability.sh)
- **Vai trò kỹ thuật**: Cấu hình chính sách vòng đời chỉ mục (ILM), thiết lập Fleet Server quản lý tập trung và cấu hình tiếp nhận log FortiGate Syslog.
- **Giao diện hiển thị**: Quá trình đăng ký chính sách qua Elasticsearch REST API và cài đặt dịch vụ `elastic-agent`.
- **Thao tác người dùng**: Xác nhận thông số triển khai.
- **Cơ chế hoạt động**:
  1. Thực thi playbook `playbooks/site_observability.yml`.
  2. Thiết lập chính sách ILM: Tự động chuyển đổi rollover khi chỉ mục đạt dung lượng 50 GB hoặc sau 30 ngày, tự động xóa chỉ mục sau 15 ngày.
  3. Triển khai và cấu hình Fleet Server trên máy chủ `srv-kibana-gw` (lắng nghe cổng 8220).
  4. Đăng ký (enroll) Elastic Agent trên 3 node Elasticsearch để thu thập CPU, RAM, Disk, Network metrics.
  5. Kích hoạt tích hợp thu thập FortiGate Syslog qua cổng UDP 9004 trên máy chủ Gateway.
- **Kết quả đầu ra**: Toàn bộ Elastic Agent kết nối thành công tới Fleet Server (`HEALTHY`), cổng UDP 9004 ở trạng thái LISTEN.

---

### Giai đoạn 5: Tích hợp giám sát hạ tầng VMware vSphere

- **Kịch bản thực thi**: [`products/elastic-stack/scripts/manage_vsphere_observability.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/products/elastic-stack/scripts/manage_vsphere_observability.sh) `apply` (hoặc `rollback`)
- **Vai trò kỹ thuật**: Tự động cấu hình giám sát toàn diện hạ tầng VMware vSphere (vCenter & toàn bộ máy chủ ESXi) đẩy dữ liệu về Elastic Stack.
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  THIẾT LẬP THAM SỐ GIÁM SÁT VMWARE VSPHERE
  ==============================================================================
  --- [1/4] THIẾT LẬP TÀI KHOẢN SERVICE ACCOUNT READ-ONLY TRÊN VCENTER ---
  => Đang tạo mới tài khoản SSO 'svc_elastic_ro'...
  => Đảm bảo quyền ReadOnly tại cấp gốc (/) cho 'svc_elastic_ro@vsphere.local'...
  --- [2/4] KHÁM PHÁ MÁY CHỦ ESXi ĐỘNG VÀ THIẾT LẬP SYSLOG FORWARDING ---
  Phát hiện các máy chủ ESXi sau:
  /ha-datacenter/host/esxi-01.lab.internal
  /ha-datacenter/host/esxi-02.lab.internal
  Bắt đầu sao lưu hiện trạng vào tệp: state/esxi_syslog_backup_20260921_083000.json...
  => Mở quy tắc tường lửa Syslog trên esxi-01...
  => Thiết lập loghost -> udp://192.168.10.40:9525...
  --- [3/4] THIẾT LẬP VCENTER APPLIANCE SYSLOG FORWARDING QUA VCENTER REST API ---
  => Đã cấu hình vCenter Appliance chuyển tiếp Syslog về 192.168.10.40:9525 thành công.
  --- [4/4] CẤU HÌNH KIBANA FLEET INTEGRATION QUA ANSIBLE ---
  HOÀN TẤT TÍCH HỢP GIÁM SÁT VMWARE VSPHERE!
  ```
- **Thao tác người dùng**: Nhập mật khẩu quản trị vCenter và mật khẩu mong muốn cho tài khoản service account `svc_elastic_ro`.
- **Cơ chế hoạt động**:
  1. `check_and_create_sso_user`: Kết nối vCenter qua CLI `govc`, tạo hoặc cập nhật tài khoản SSO `svc_elastic_ro@vsphere.local`, gán quyền `ReadOnly` tại cấp thư mục gốc `/`.
  2. `configure_esxi_syslog_with_backup`: Dùng `govc find -type h` khám phá tất cả máy chủ ESXi trong cụm. Lưu cấu hình `loghost` và trạng thái tường lửa hiện tại vào tệp JSON `state/esxi_syslog_backup_<TIMESTAMP>.json`. Kích hoạt firewall ruleset `syslog` và cấu hình syslog daemon chuyển tiếp log về Kibana Gateway (`udp://${IP_KBN}:9525`).
  3. `configure_vcsa_syslog`: Gửi yêu cầu qua vCenter REST API port 443 (`/api/appliance/logging/forwarding`) để đẩy syslog sự kiện của máy ảo VCSA về `udp://${IP_KBN}:9525`.
  4. `run_fleet_ansible_integration`: Kích hoạt playbook Ansible cài đặt gói tích hợp `vsphere` trên Kibana Fleet, cấu hình định kỳ thu thập vSphere Metrics qua VMware Web Services API SDK.
  5. **Cơ chế hoàn tác (Rollback)**: Khi chạy tham số `rollback`, kịch bản đọc tệp sao lưu `state/esxi_syslog_backup_latest.json`, khôi phục nguyên trạng giá trị `loghost` và đóng cổng firewall trên từng ESXi, hoàn tác cấu hình syslog trên VCSA và gỡ bỏ chính sách giám sát trên Kibana Fleet.
- **Kết quả đầu ra**: Các dashboard VMware (VMware vSphere Overview, Host Performance, VM Performance, Datastore Capacity, ESXi Syslogs) hiển thị trực quan trên Kibana.

---

### Giai đoạn 6: Sao lưu và phục hồi dữ liệu cụm (SLM)

- **Kịch bản thực thi**: [`ansible/products/elastic-stack/run_backup.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/ansible/products/elastic-stack/run_backup.sh)
- **Vai trò kỹ thuật**: Đăng ký Snapshot Repository trên hệ thống tệp và cấu hình chính sách sao lưu tự động qua Snapshot Lifecycle Management (SLM).
- **Giao diện hiển thị**:
  ```text
  ==============================================================================
  QUẢN LÝ SAO LƯU VÀ PHỤC HỒI ELASTICSEARCH (SLM)
  ==============================================================================
  1) Thiết lập Snapshot Repository và Chính sách SLM tự động
  2) Tạo một bản Snapshot thủ công ngay lập tức
  3) Khôi phục dữ liệu từ Snapshot có sẵn
  0) Thoát
  Vui lòng chọn (0-3):
  ```
- **Thao tác người dùng**: Chọn thao tác vận hành tương ứng theo nhu cầu (thiết lập định kỳ, tạo bản chụp tức thì hoặc khôi phục).
- **Cơ chế hoạt động**:
  1. Tạo thư mục lưu trữ snapshot `/mnt/backups/elasticsearch` trên các node.
  2. Đăng ký Snapshot Repository dạng `fs` vào cụm Elasticsearch qua REST API.
  3. Cấu hình chính sách SLM định kỳ chạy snapshot vào 01:00 AM mỗi ngày, tự động lưu giữ tối thiểu 5 bản và tối đa 30 bản.
- **Kết quả đầu ra**: Xác thực repository thành công (`curl -u elastic... /_snapshot/fs_backup/_verify`), các bản snapshot hiển thị trong Kibana Management > Snapshot and Restore.

---

## 4. Bảng kiểm tra nghiệm thu

| Hạng mục | Lệnh xác minh | Tiêu chuẩn đạt |
| :--- | :--- | :--- |
| **Golden Image** | `govc find . -type m -name "<TPL_NAME>"` | Template tồn tại và đúng cấu hình |
| **VM & Network** | `ping -c 3 <IP_VM>` | Máy ảo poweredOn, IP tĩnh hoạt động |
| **DRS Anti-Affinity** | Check vCenter Cluster -> Rules | Các node ES nằm trên các host khác nhau |
| **ES Cluster Health** | `curl -u elastic... /_cluster/health` | Trạng thái `green`, đủ số node |
| **Kibana/Fleet** | Truy cập cổng `5601` và `8220` (API status) | Phản hồi HTTP 200, trạng thái `green` |
| **Elastic Agent** | `elastic-agent status` | Tất cả agent báo `HEALTHY` |
| **Cổng Syslog** | `ss -ulnp \| grep 9004` (trên Gateway) | Đang LISTEN bởi `elastic-agent` |
| **Snapshot Repo** | `curl -u elastic... /_snapshot/repo/_verify` | Xác thực repo thành công |

---

## 5. Xử lý sự cố thường gặp (Troubleshooting)

1. **Packer kẹt ở màn hình cài đặt Ubuntu**: Do sai nhãn ổ đĩa `cidata` hoặc sai lệnh boot GRUB trong `ubuntu-24.04.pkr.hcl`. Kiểm tra lại cấu hình autoinstall.
2. **Packer SSH Timeout**: Thiếu DHCP ở mạng khởi tạo VM, hoặc mật khẩu mã hóa trong `user-data` bị sai.
3. **Terraform không gán IP tĩnh được**: Lỗi xung đột `open-vm-tools` và `cloud-init`. Cần dọn dẹp thư mục `/var/lib/cloud` kỹ càng trước khi đóng gói template.
4. **Cụm ES không kết nạp Node**: Sai cấu hình mTLS, tường lửa UFW chặn cổng 9300, hoặc sai tên node trong `discovery.seed_hosts`. Kiểm tra `/var/log/elasticsearch/`.
5. **Kibana báo "Server is not ready"**: Mật khẩu `kibana_system` không khớp hoặc thiếu key mã hóa xpack. Chạy lệnh đổi mật khẩu và cập nhật lại Kibana Keystore.
6. **Mất kết nối SSH khi chạy Script**: Dùng lệnh `tmux attach-session -t deploy_session` để vào lại phiên làm việc.

---

## 6. Lộ trình nâng cấp (Roadmap)

1. **HA cho Kibana & Fleet Server**: Bổ sung Keepalived/HAProxy và Gateway thứ 2 để chống SPoF. Cấu hình Network Load Balancer cho cổng Syslog UDP.
2. **Phân tầng ILM Hot-Warm-Cold**: Thêm cấu hình node roles (Data Hot/Warm/Cold) và mở rộng ILM policy để tối ưu chi phí lưu trữ (NVMe vs HDD).
3. **TLS cho ES HTTP 9200**: Tự động hóa sinh chứng chỉ SSL/TLS cho REST API để mã hóa end-to-end.
4. **Lưu trữ Snapshot S3/NFS**: Tích hợp Ansible Role cấp phát NFS Client hoặc chuyển qua dùng S3 plugin thay vì FS cục bộ để hỗ trợ Snapshot phân tán.
5. **Động hóa DRS Anti-affinity**: Kiểm tra Terraform xem số host vật lý có lớn hơn số máy ảo Elasticsearch không trước khi kích hoạt rule (tránh lỗi lab nhỏ).
6. **Triệt tiêu Hardcode**: Loại bỏ hoàn toàn giới hạn 4 VMs cố định, chuyển qua xử lý `for_each` toàn diện từ tập biến môi trường độc lập.
