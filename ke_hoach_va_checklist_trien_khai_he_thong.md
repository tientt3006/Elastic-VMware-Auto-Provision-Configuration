# Kế hoạch và checklist triển khai hệ thống tự động hóa hạ tầng VMware và Elastic Stack

Tài liệu này đặc tả toàn bộ kế hoạch triển khai, danh mục kiểm tra điều kiện tiên quyết (checklist), quy trình thực thi chi tiết và sổ tay xử lý sự cố cho hệ thống tự động hóa cung ứng hạ tầng máy ảo trên VMware vSphere và cấu hình cụm Elastic Stack phân tán chuẩn HA. Toàn bộ nội dung được xây dựng bám sát cấu trúc mã nguồn hiện có trong kho lưu trữ, đồng thời chỉ rõ các điểm giới hạn kỹ thuật cần tiếp tục hoàn thiện.

---

## 1. Tổng quan kiến trúc và luồng điều phối

### 1.1. Mục tiêu hệ thống
Hệ thống thực hiện tự động hóa chu trình khép kín từ hạ tầng ảo hóa đến dịch vụ quan sát:
- Khởi tạo trạm điều khiển tự động hóa (Seed host) và quản lý kho ảnh cài đặt (ISO cache).
- Cài đặt máy chủ quản trị ảo hóa vCenter Server Appliance (VCSA) không giám sát (unattended deployment) khi triển khai trên hạ tầng trắng (greenfield).
- Đóng gói mẫu máy ảo chuẩn (Golden Image Template) Ubuntu 24.04 LTS bằng Packer, tối ưu hóa hạt nhân và loại bỏ định danh máy ảo.
- Cung ứng tài nguyên ảo hóa (mạng, thư mục, máy ảo, phân tán tải DRS Anti-Affinity) bằng Terraform và tự động kết xuất danh mục máy chủ (dynamic inventory).
- Cấu hình cụm dịch vụ Elasticsearch 8.x Native chuẩn HA (3 node master/data/ingest) với mã hóa liên nút mTLS bằng Ansible.
- Cấu hình cổng giao tiếp Kibana Gateway và máy chủ điều phối Fleet Server.
- Tự động kích hoạt chính sách quản lý chỉ mục ILM, gói thu thập chỉ số hệ điều hành và cổng hứng nhật ký tường lửa FortiGate Syslog UDP 9004 qua Elastic Agent.
- Thiết lập quy trình sao lưu dữ liệu snapshot và phục hồi thảm họa qua SLM.

### 1.2. Mô hình kiến trúc phân bổ nút và định cỡ tài nguyên tổng quát

#### 1.2.1. Triết lý đóng gói và trừu tượng hóa đa hạ tầng
Kho lưu trữ này được thiết kế theo mô hình khung tự động hóa (automation framework) có khả năng tái sử dụng độc lập cho nhiều hạ tầng, dự án và môi trường khác nhau (phát triển, thử nghiệm, sản xuất). Toàn bộ các thông số kỹ thuật (địa chỉ IP, tên miền, dải VLAN, tên đối tượng ảo hóa, kích cỡ CPU, RAM, dung lượng đĩa) đều được trừu tượng hóa dưới dạng biến cấu hình thay vì gán cứng vào mã nguồn:
- **Lớp mã nguồn logic (Logic Core)**: Chịu trách nhiệm thực thi quy trình chuẩn hóa (chuẩn bị ảnh máy ảo qua Packer, khởi tạo tài nguyên qua Terraform, thiết lập phân tán qua Ansible). Lớp này hoàn toàn trung lập với môi trường.
- **Lớp tham số môi trường (Environment Profile)**: Từng dự án hoặc từng trung tâm dữ liệu sẽ nạp một bộ tham số độc lập thông qua tệp cấu hình biến tập trung (`vars.conf`, `terraform.tfvars`, `hosts.yml`).

#### 1.2.2. Phân loại vai trò máy chủ trong cụm (Role-based Node Taxonomy)
Kiến trúc tổng thể phân tách thành hai phân lớp chức năng:

1. **Phân lớp lưu trữ và xử lý phân tán (Elasticsearch Cluster Tier - N nút)**:
   - Quy mô tối thiểu yêu cầu 3 nút để đảm bảo tính sẵn sàng cao (High Availability) và thuật toán đồng thuận (Raft/Zen Discovery consensus) không xảy ra hiện tượng chia cắt cụm (Split-Brain) khi bầu chọn nút quản trị (Master).
   - Quy ước đặt tên tổng quát: `<PREFIX_DỰ_ÁN>-elastic-<INDEX>` (ví dụ: `srv-elastic-01`, `srv-elastic-02`, `srv-elastic-03` hoặc `prod-elk-data-01..N`).
   - Khả năng phân tách vai trò: Tùy theo lưu lượng tải, các nút có thể hoạt động ở chế độ tích hợp toàn diện (`master,data,ingest`) hoặc tách rời thành các nút chuyên biệt (Dedicated Master Nodes, Data Hot/Warm/Cold Nodes, Ingest Nodes).

2. **Phân lớp cổng giao tiếp và điều phối quản trị (Management & Ingestion Gateway Tier)**:
   - Đóng vai trò máy chủ trung gian quản lý: Chạy giao diện trực quan hóa Kibana, chạy máy chủ điều phối trung tâm Fleet Server để quản lý vòng đời và cấu hình của Elastic Agent, đồng thời làm cổng tiếp nhận nhật ký mạng diện rộng (FortiGate Syslog UDP 9004, NetFlow, Beats).
   - Quy ước đặt tên tổng quát: `<PREFIX_DỰ_ÁN>-kibana-gw` (hoặc cụm Gateway HA nếu triển khai quy mô lớn).

#### 1.2.3. Khung định cỡ tài nguyên chuẩn hóa (Sizing Profiles Matrix)
Hệ thống hỗ trợ 3 hồ sơ định cỡ chuẩn hóa để kỹ sư áp dụng linh hoạt theo yêu cầu dự án:

| Tiêu chí kỹ thuật | Hồ sơ Thử nghiệm / Lab (Dev & Lab Profile) | Hồ sơ Tiêu chuẩn Doanh nghiệp vừa (Standard Production) | Hồ sơ Hiệu năng cao / Doanh nghiệp lớn (High-Throughput Enterprise) |
| :--- | :--- | :--- | :--- |
| **Quy mô lưu lượng** | < 1.000 EPS, log < 10 GB/ngày | 5.000 - 15.000 EPS, log 50 - 150 GB/ngày | > 30.000 EPS, log > 500 GB/ngày |
| **Số lượng nút Elasticsearch** | 3 nút tích hợp (`master,data,ingest`) | 3 nút tích hợp hoặc tách riêng | 3 Dedicated Master + 3..6 Data Hot + Data Warm/Cold |
| **Cấu hình mỗi nút Elasticsearch** | 2 - 4 vCPU, 4 - 8 GB RAM (JVM: 2 - 4 GB), 50 GB PVSCSI | 4 - 8 vCPU, 16 - 32 GB RAM (JVM: 8 - 16 GB), 200 - 500 GB NVMe/SSD | 8 - 16 vCPU, 64 GB RAM (JVM: 31 GB con trỏ nén OOPs), 1 - 2 TB NVMe RAID 10 |
| **Cấu hình nút Gateway (Kibana/Fleet)** | 1 nút: 2 vCPU, 4 GB RAM, 40 GB PVSCSI | 1 - 2 nút: 4 vCPU, 8 GB RAM, 60 - 100 GB PVSCSI | 2 nút HA (sau Load Balancer): 8 vCPU, 16 GB RAM, 100 GB SSD |
| **Chính sách phân bổ JVM Heap** | 50% RAM vật lý của máy ảo, không vượt quá 31 GB để bảo toàn tính năng Compressed OOPs của Java Virtual Machine. |

#### 1.2.4. Bảng ánh xạ tham số biến hạ tầng
Mọi tài nguyên của dự án được định nghĩa qua các biến cấu hình:

| Biến cấu hình | Tệp khai báo | Mục đích ánh xạ kỹ thuật |
| :--- | :--- | :--- |
| `SITE_VCSA_IP` / `vsphere_server` | `vars.conf`, `terraform.tfvars` | Địa chỉ IP hoặc FQDN của máy chủ quản trị vCenter tại site |
| `VCENTER_DC`, `VCENTER_CLUSTER` | `vars.conf`, `terraform.tfvars` | Tên Datacenter và Cluster đích trên VMware vSphere |
| `ISO_DATASTORE` / `vsphere_datastore` | `vars.conf`, `terraform.tfvars` | Tên vùng lưu trữ Datastore chứa ISO và lưu trữ máy ảo |
| `PKR_NETWORK`, `virtual_switch_name` | `vars.conf`, `terraform.tfvars` | Phân vùng mạng và vSwitch gán cho máy ảo mẫu và máy ảo vận hành |
| `vms` (dạng map trong Terraform) | `terraform.tfvars` | Định nghĩa linh hoạt danh sách máy ảo: tên, IP tĩnh, gateway, DNS, CPU, RAM, Disk |
| `ansible_host` | Tự động sinh từ Terraform sang `hosts.yml` | Địa chỉ IP quản trị của từng máy chủ nạp cho Ansible |

#### 1.2.5. Cấu hình mẫu tham chiếu mặc định (Default Baseline Profile)
Trong các tệp mẫu `.example` hiện tại của kho mã nguồn, một cấu hình tham chiếu mặc định được thiết lập sẵn để kiểm thử xác minh chức năng:

| Tên máy ảo mẫu | Địa chỉ IP mẫu | Vai trò cụm | Cấu hình tham chiếu mẫu (CPU/RAM/Disk) | Phân vùng mạng mẫu |
| :--- | :--- | :--- | :--- | :--- |
| `srv-elastic-01` | `<IP_ELASTIC_01>` (`<IP_NODE_01>`) | Elasticsearch Node 01 (Master, Data, Ingest) | 4 vCPU / 8 GB RAM / 50 GB PVSCSI | `VM Network 3` (VLAN tương ứng) |
| `srv-elastic-02` | `<IP_ELASTIC_02>` (`<IP_NODE_02>`) | Elasticsearch Node 02 (Master, Data, Ingest) | 4 vCPU / 8 GB RAM / 50 GB PVSCSI | `VM Network 3` (VLAN tương ứng) |
| `srv-elastic-03` | `<IP_ELASTIC_03>` (`<IP_NODE_03>`) | Elasticsearch Node 03 (Master, Data, Ingest) | 4 vCPU / 8 GB RAM / 50 GB PVSCSI | `VM Network 3` (VLAN tương ứng) |
| `srv-kibana-gw` | `<IP_KIBANA_GW>` (`<IP_KIBANA>`) | Kibana Gateway, Fleet Server, Syslog Receiver | 2 vCPU / 4 GB RAM / 40 GB PVSCSI | `VM Network 3` (VLAN tương ứng) |

Thông số mạng mẫu:
- Mặt nạ mạng: `<NETMASK>` (mẫu: `/24`).
- Cổng mặc định: `<GATEWAY>` (mẫu: `<GATEWAY_IP>`).
- Tên miền nội bộ: `<DOMAIN_NAME>` (mẫu: khai báo qua `default_domain_name`).
- Máy chủ phân giải tên miền: `<DNS_SERVERS>`.


### 1.3. Luồng điều phối toàn trình
Chuỗi thực thi tuần tự được tích hợp qua kịch bản gốc `run_all_onclick.sh` hoặc chạy độc lập theo từng phân hệ:

```text
[Trạm điều khiển WSL / Linux]
         │
         ├── 0. automation_seed: Cài đặt công cụ + Tải ISO + Đẩy ISO lên Datastore
         │
         ├── (Tùy chọn) vcsa_deploy: Cài đặt VCSA không giám sát lên ESXi trắng
         │
         ├── 1. packer_test: Khởi tạo tpl-ubuntu-2404-golden (Autoinstall cidata)
         │
         ├── 2. terraform_test: Tạo Network + VM Folder + Các máy ảo + Anti-Affinity Rule
         │        └── Tự động sinh tệp ansible_test/inventories/lab/hosts.yml
         │
         ├── 3. ansible_test: Cài đặt cụm phân tán Elasticsearch HA + Kibana Gateway
         │        └── Kiểm tra API _cluster/health (Trạng thái green)
         │
         ├── 4. ansible_test: Cấu hình Observability + Fleet Server + FortiGate Syslog
         │        └── Ghi danh Elastic Agent trên toàn bộ các máy chủ
         │
         └── 5. ansible_test: Cấu hình Snapshot Repository + Chính sách SLM sao lưu
```

---

## 2. Checklist điều kiện tiên quyết trước khi triển khai

Trước khi kích hoạt bất kỳ tiến trình tự động hóa nào, kỹ sư hệ thống phải kiểm tra và xác nhận đầy đủ các điều kiện kỹ thuật dưới đây.

### 2.1. Kiểm toán hạ tầng VMware vSphere
- [ ] **Máy chủ vật lý (ESXi Host)**:
  - Có tối thiểu 2 máy chủ ESXi kết nối vào cùng 1 vCenter Datacenter/Cluster để thỏa mãn quy tắc phân tách tải DRS Anti-Affinity và khả năng dự phòng vSphere HA. Trường hợp môi trường lab chỉ có 1 host ESXi, quy tắc DRS phải chuyển sang trạng thái vô hiệu hóa (`enabled = false`) trong Terraform.
  - Phiên bản ESXi được hỗ trợ: VMware ESXi 7.0 Update 3 trở lên hoặc ESXi 8.0.
- [ ] **Tài nguyên lưu trữ (Datastore)**:
  - Datastore đích (VMFS 6 hoặc vSAN) còn trống tối thiểu 250 GB dung lượng khả dụng.
  - Tên Datastore trùng khớp với biến khai báo `ISO_DATASTORE` và `vsphere_datastore`.
- [ ] **Hạ tầng mạng ảo (Virtual Networking)**:
  - vSwitch chuẩn (`vSwitch0`) hoặc Distributed Virtual Switch (vDS) đã được cấu hình đường truyền vật lý (uplink) thông suốt ra hệ thống switch vật lý.
  - Các dải VLAN cần thiết đã được định tuyến tại gateway hoặc cấu hình trên firewall trung tâm.
- [ ] **Phân quyền tài khoản vCenter (RBAC)**:
  - Sử dụng tài khoản có quyền quản trị toàn phần (`<VCENTER_USER>`) hoặc phân quyền tối thiểu gồm các nhóm quyền: `Datastore.AllocateSpace`, `Network.Assign`, `Resource.AssignVMToPool`, `VirtualMachine.Config.*`, `VirtualMachine.Interact.*`, `VirtualMachine.Inventory.CreateFromExisting`.

### 2.2. Kiểm toán hạ tầng mạng và tường lửa (Firewall Matrix)
Đảm bảo các cổng giao tiếp sau được mở thông suốt giữa các phân vùng mạng (các địa chỉ IP và phân vùng mạng tương ứng với khai báo trong tệp cấu hình của từng dự án):

| Cổng / Giao thức | Nguồn | Đích | Mục đích kỹ thuật |
| :--- | :--- | :--- | :--- |
| `TCP/443` | Trạm điều khiển | vCenter / ESXi Host | Quản trị API vSphere, đẩy ISO qua govc |
| `TCP/902` | Trạm điều khiển | ESXi Host | Truyền dữ liệu đĩa và máy ảo qua vSphere API |
| `TCP/22` | Trạm điều khiển | Toàn bộ máy ảo trong cụm | Quản trị từ xa và thực thi cấu hình SSH/Ansible |
| `TCP/9200` | Nội bộ mạng VM, Máy chủ Kibana | Các nút Elasticsearch | Giao tiếp REST API dữ liệu và giám sát |
| `TCP/9300` | Các nút Elasticsearch | Các nút Elasticsearch | Giao tiếp đồng bộ cụm và phân bổ shard (mTLS) |
| `TCP/5601` | Mạng quản trị kỹ sư | Máy chủ Kibana Gateway | Giao diện đồ họa Kibana |
| `TCP/8220` | Toàn bộ máy ảo cài Elastic Agent | Máy chủ Fleet Server | Giao tiếp quản trị tập trung Fleet Server |
| `UDP/9004` | Tường lửa FortiGate / Thiết bị mạng | Máy chủ Gateway thu thập log | Thu nhận luồng nhật ký sự kiện FortiGate Syslog |
| `UDP/123` | Toàn bộ máy ảo trong cụm | Máy chủ NTP nội bộ | Đồng bộ thời gian hệ thống (bắt buộc cho TLS) |
| `UDP/53`, `TCP/53` | Toàn bộ máy ảo trong cụm | Máy chủ DNS | Phân giải tên miền nội bộ và tra cứu ngược PTR |

### 2.3. Chuẩn bị trạm điều khiển (Seed / Control Station)
- [ ] Hệ điều hành trạm điều khiển: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS hoặc môi trường WSL2 trên máy tính Windows.
- [ ] Đã cài đặt đầy đủ bộ công cụ dòng lệnh:
  - `terraform` (phiên bản >= 1.5.0)
  - `packer` (phiên bản >= 1.9.0)
  - `ansible` / `ansible-core` (phiên bản >= 2.15.0)
  - `govc` (tiện ích tương tác VMware vSphere CLI)
  - `tmux` (chống đứt kết nối phiên làm việc)
  - `jq`, `curl`, `python3`, `python3-crypt`
- [ ] Khóa xác thực SSH: Đã sinh cặp khóa SSH RSA/ED25519 tại trạm điều khiển (`~/.ssh/id_rsa` hoặc `~/.ssh/id_ed25519`).

---

## 3. Quy trình thực thi chi tiết theo từng giai đoạn

### Giai đoạn 0: Khởi tạo môi trường điều khiển và chuẩn bị tệp cấu hình

#### Bước 0.1: Cài đặt bộ công cụ trên trạm điều khiển
Thực thi kịch bản cài đặt tự động từ thư mục `automation_seed`:
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/automation_seed
chmod +x setup_automation_env.sh
./setup_automation_env.sh
```
Kịch bản tự động bổ sung kho phần mềm HashiCorp, cài đặt Packer, Terraform, Ansible, govc và thiết lập môi trường ảo Python.

#### Bước 0.2: Tải và đẩy ảnh cài đặt Ubuntu lên vCenter Datastore
1. Tải ảnh ISO Ubuntu Server 24.04 LTS kèm kiểm tra mã băm SHA256:
   ```bash
   cd D:/neit_ng/prjs_i/auto_provision_configuration/automation_seed
   chmod +x download_iso.sh
   ./download_iso.sh --ubuntu
   ```
2. Đẩy tệp ISO lên Datastore chỉ định trên vCenter:
   ```bash
   export GOVC_URL="https://<IP_VCENTER>"
   export GOVC_USERNAME="<VCENTER_USER>"
   export GOVC_PASSWORD="<MAT_KHAU_VCENTER>"
   export GOVC_INSECURE="1"

   govc datastore.mkdir -ds="<TEN_DATASTORE>" iso
   govc datastore.upload -ds="<TEN_DATASTORE>" ./iso_cache/ubuntu-24.04.5-live-server-amd64.iso iso/ubuntu-24.04.5-live-server-amd64.iso
   ```

#### Bước 0.3: Thiết lập tệp cấu hình biến tập trung `vars.conf`
Tại thư mục gốc của dự án, tạo và cập nhật tệp `vars.conf`:
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration
cp vars.conf.example vars.conf 2>/dev/null || true
```
Điền chính xác các thông số hạ tầng:
```text
SITE_VCSA_IP="<IP_VCSA>"
VCENTER_USER="<VCENTER_USER>"
VCENTER_DC="Datacenter"
VCENTER_CLUSTER="Cluster1"
ISO_DATASTORE="datastore1"
PKR_NETWORK="VM Network"
VM_FOLDER="App_Workloads"
TPL_NAME="tpl-ubuntu-2404-golden"

SSH_USER="<SSH_USER>"
IP_E01="<IP_NODE_01>"
IP_E02="<IP_NODE_02>"
IP_E03="<IP_NODE_03>"
IP_KBN="<IP_KIBANA>"
GW="<GATEWAY_IP>"
NETMASK="24"
```

---

### Giai đoạn 1: Đóng gói mẫu máy ảo chuẩn (Golden Image Pipeline)

#### Bước 1.1: Kiểm tra cấu hình Packer
Thư mục làm việc: `packer_test/`.
Tệp cấu hình biến: `packer.pkrvars.hcl` (sinh từ `packer.pkrvars.hcl.example`).
Các thông số cần xác minh:
- Khối tài nguyên máy ảo mẫu: 2 vCPU, 4096 MB RAM, 40 GB đĩa PVSCSI, card mạng VMXNET3.
- Cơ chế khởi động Subiquity: Sử dụng thiết bị ổ đĩa ảo nhãn `cidata` nạp `user-data` và `meta-data`, loại bỏ phụ thuộc vào HTTP server nội bộ.
- Chuỗi lệnh khởi động GRUB trong `ubuntu-24.04.pkr.hcl`:
  ```hcl
  boot_command = [
    "c<wait>",
    "search --set=root --file /casper/vmlinuz<enter><wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud<enter><wait5s>",
    "initrd /casper/initrd<enter><wait5s>",
    "boot<enter>"
  ]
  ```

#### Bước 1.2: Thực thi tiến trình đóng gói an toàn
Chạy kịch bản nạp mật khẩu In-Memory:
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/packer_test
chmod +x build_packer_secure.sh
./build_packer_secure.sh
```
Tiến trình thực hiện:
1. Nhập mật khẩu vCenter và mật khẩu quản trị OS (`<SSH_USER>`) vào bộ nhớ tạm RAM.
2. Khởi tạo máy ảo tạm thời trên ESXi, gắn ISO Ubuntu và đĩa ảo `cidata`.
3. Cài đặt hệ điều hành tự động qua Subiquity Autoinstall.
4. Kết nối SSH vào máy ảo thực thi tuần tự 4 kịch bản chuẩn hóa:
   - `01_install_open_vm_tools.sh`: Cài đặt `open-vm-tools`, kích hoạt dịch vụ giao tiếp vSphere.
   - `02_harden_ssh.sh`: Cấu hình SSH, vô hiệu hóa xác thực mật khẩu cho root, áp dụng PAM limits.
   - `03_configure_ufw.sh`: Kích hoạt tường lửa máy chủ UFW, mở cổng 22.
   - `04_generalize_template.sh`: Xóa `/etc/machine-id`, xóa cache Cloud-init, xóa DHCP leases, xóa lịch sử bash để tránh trùng lặp nhận dạng khi nhân bản.
5. Tắt máy ảo và chuyển đổi thành template vSphere (`convert_to_template = true`).

#### Bước 1.3: Nghiệm thu Giai đoạn 1
Kiểm tra sự tồn tại của template trên vCenter qua `govc`:
```bash
govc find . -type m -name "tpl-ubuntu-2404-golden"
```
Kết quả mong đợi: Hiển thị đường dẫn đối tượng máy ảo mẫu trên kho thư mục vCenter.

---

### Giai đoạn 2: Cung ứng hạ tầng máy ảo và mạng ảo (Terraform)

#### Bước 2.1: Khởi tạo cấu hình Terraform
Thư mục làm việc: `terraform_test/`.
Cấu hình thông số tại `terraform.tfvars`:
- `vm_folders`: Khai báo danh mục thư mục quản lý đối tượng máy ảo (ví dụ: `["App_Workloads", "Infra_Services"]`).
- `port_groups`: Danh sách Port Group tiêu chuẩn kèm VLAN ID cần tạo trên `vSwitch0`.
- `vms`: Định nghĩa 4 máy ảo (`srv-elastic-01`, `srv-elastic-02`, `srv-elastic-03`, `srv-kibana-gw`) kèm địa chỉ IP tĩnh, gateway, DNS server, CPU, RAM và dung lượng ổ đĩa.
- `drs_rule_mandatory`: Thiết lập `false` (Soft anti-affinity rule) để tránh khóa chết tài nguyên khi khởi động lại host.

#### Bước 2.2: Khởi tạo và kiểm tra tính hợp lệ của mã nguồn
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/terraform_test
terraform init
terraform validate
```

#### Bước 2.3: Thực thi cung ứng hạ tầng
Kích hoạt kịch bản tiêm mật khẩu RAM:
```bash
chmod +x run_provision_secure.sh
./run_provision_secure.sh
```
Tiến trình thực hiện:
1. Module `folder`: Tạo thư mục quản lý trên vCenter.
2. Module `network`: Tạo Port Group trên tất cả các host ESXi được chỉ định.
3. Module `compute`: Nhân bản đồng thời 4 máy ảo từ `tpl-ubuntu-2404-golden`, tiêm tham số mạng tĩnh qua cơ chế `guestinfo` / `clone customization`.
4. Module `cluster_rules`: Cấu hình quy tắc phân tán tải DRS Anti-Affinity cho 3 node Elasticsearch.
5. Tài nguyên `local_file.ansible_inventory`: Tự động kết xuất thông số IP của 4 máy ảo thành tệp danh mục máy chủ `ansible_test/inventories/lab/hosts.yml` với phân quyền `0644`.

#### Bước 2.4: Nghiệm thu Giai đoạn 2
1. Xác minh trạng thái máy ảo trên ESXi:
   ```bash
   # Liệt kê thông tin các máy ảo (sử dụng danh sách tên VM được khai báo trong dự án)
   govc vm.info <DANH_SÁCH_TÊN_VM>
   # (Ví dụ mẫu tham chiếu: govc vm.info srv-elastic-01 srv-elastic-02 srv-elastic-03 srv-kibana-gw)
   ```
2. Kiểm tra thông tuyến mạng và phân giải tên miền:
   ```bash
   ping -c 3 <IP_ELASTIC_01>
   ping -c 3 <IP_KIBANA_GW>
   # (Ví dụ mẫu tham chiếu: ping -c 3 <IP_NODE_01>; ping -c 3 <IP_KIBANA>)
   ```
3. Xác nhận tệp inventory tự động đã được tạo đầy đủ:
   ```bash
   cat ../ansible_test/inventories/lab/hosts.yml
   ```

---

### Giai đoạn 3: Cấu hình phân tán Elastic Stack HA (Ansible)

#### Bước 3.1: Kiểm tra danh mục máy chủ và cấu hình biến
Thư mục làm việc: `ansible_test/`.
Tệp cấu hình biến chung: `inventories/lab/group_vars/all/main.yml`.
Các thông số cần xác nhận:
- `elastic_version`: Phiên bản cài đặt (mặc định `8.19.0`).
- `elastic_cluster_name`: Tên định danh cụm (ví dụ `elastic-cluster-lab`).
- `elastic_heap_size`: Dung lượng bộ nhớ JVM gán cho Elasticsearch (khuyến nghị bằng 50% RAM máy ảo, ví dụ `4g` cho máy 8 GB RAM, không vượt quá 31 GB).
- `kibana_encryption_key`: Chuỗi mã hóa tối thiểu 32 ký tự ngẫu nhiên (tự động sinh qua `openssl rand -hex 24`).

#### Bước 3.2: Kiểm tra kết nối quản trị Ansible
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/ansible_test
export ANSIBLE_CONFIG="./ansible.cfg"
ansible -i inventories/lab/hosts.yml all -m ping --ask-pass --ask-become-pass
```
Kết quả mong đợi: Toàn bộ máy chủ trong inventory trả về trạng thái `"ping": "pong"`.

#### Bước 3.3: Thực thi kịch bản cài đặt cụm dịch vụ
Chạy kịch bản an toàn:
```bash
chmod +x run_ansible_secure.sh
./run_ansible_secure.sh
```
Tiến trình playbook `deploy_cluster.yml` thực thi:
1. **Áp dụng tối ưu hạt nhân OS (Role `elastic_cluster`)**:
   - Thiết lập `vm.max_map_count = 262144` qua sysctl.
   - Vô hiệu hóa swap bằng `vm.swappiness = 1` để tối ưu hiệu năng JVM.
   - Cấu hình giới hạn tài nguyên hệ thống (nofile, nproc, memlock) trong `/etc/security/limits.conf`.
2. **Cài đặt Elasticsearch Native 8.x**:
   - Thêm GPG key chính thức và kho APT Elastic.
   - Cài đặt gói `elasticsearch`.
   - Tạo chứng chỉ số SSL nội bộ (PKI) và kích hoạt mã hóa lớp truyền tải mTLS (`xpack.security.transport.ssl`).
   - Cấu hình danh sách nút khởi tạo (`discovery.seed_hosts` và `cluster.initial_master_nodes`).
   - Khởi động dịch vụ `systemctl start elasticsearch`.
   - Thiết lập mật khẩu cho tài khoản siêu quản trị `elastic` và tài khoản hệ thống `kibana_system`.
3. **Cài đặt Kibana Gateway (Role `kibana_fleet_gateway`)**:
   - Cài đặt gói `kibana` trên nút gateway được chỉ định.
   - Cấu hình kết nối tới cụm Elasticsearch qua tài khoản `kibana_system`.
   - Khởi động dịch vụ `systemctl start kibana`.
4. **Kiểm tra sức khỏe cụm tự động**:
   - Truy vấn API `_cluster/health` từ node đầu tiên.

#### Bước 3.4: Nghiệm thu Giai đoạn 3
Thực thi lệnh kiểm tra trạng thái cụm từ trạm điều khiển:
```bash
curl -u elastic:<MAT_KHAU_ELASTIC> "http://<IP_ELASTIC_NODE>:9200/_cluster/health?pretty"
# (Ví dụ mẫu tham chiếu: curl -u elastic:... "http://<IP_NODE_01>:9200/_cluster/health?pretty")
```
Kết quả mong đợi:
```json
{
  "cluster_name" : "elastic-cluster-lab",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3,
  "active_primary_shards" : 0,
  "active_shards" : 0,
  "unassigned_shards" : 0
}
```
Truy cập giao diện Kibana qua trình duyệt: `http://<IP_KIBANA_GW>:5601` (ví dụ mẫu tham chiếu: `http://<IP_KIBANA>:5601`).

---

### Giai đoạn 4: Kích hoạt hệ thống quan sát tập trung (Ansible)

#### Bước 4.1: Thực thi cấu hình Observability tự động
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/ansible_test
chmod +x run_observability_setup.sh
./run_observability_setup.sh
```
Tiến trình playbook `site_observability.yml` thực thi tuần tự 3 playbook thành phần:

1. **Cấu hình chính sách ngăn xếp (`configure_stack_policies.yml`)**:
   - Tạo chính sách vòng đời chỉ mục ILM `fortinet-firewall-ilm-policy`: Rollover sau 50 GB hoặc 30 ngày, tự động xóa (Delete phase) sau 15 ngày.
   - Cài đặt gói tích hợp `fortinet` (Fortinet Integration Package) từ kho quản trị Kibana.
   - Cấu hình luồng hứng nhật ký tường lửa FortiGate Syslog trên cổng `UDP/9004`.
   - Cấu hình gói tích hợp `system` thu thập 18 luồng chỉ số máy chủ (CPU, memory, disk, network, process, socket,...).
   - Kích hoạt tính năng giám sát nội bộ cụm (Stack Monitoring).
2. **Triển khai Fleet Server (`deploy_fleet_server.yml`)**:
   - Sinh Service Token cho Fleet Server qua REST API của Elasticsearch.
   - Cài đặt Elastic Agent trên `srv-kibana-gw` đóng vai trò Fleet Server tập trung, lắng nghe trên cổng `HTTPS/8220`.
   - Sinh Enrollment Token cho các agent thành viên.
3. **Ghi danh Elastic Agent diện rộng (`enroll_agents.yml`)**:
   - Tải và cài đặt Elastic Agent trên toàn bộ 3 máy chủ Elasticsearch (`srv-elastic-01`, `02`, `03`).
   - Ghi danh (enroll) các agent vào Fleet Server sử dụng Enrollment Token.
   - Kích hoạt dịch vụ `elastic-agent` chạy nền.

#### Bước 4.2: Nghiệm thu Giai đoạn 4
1. Kiểm tra trạng thái Agent trên Kibana GUI:
   - Truy cập: **Management** -> **Fleet** -> **Agents**.
   - Xác nhận toàn bộ máy chủ trong cụm đều ở trạng thái `Healthy`.
2. Kiểm tra cổng tiếp nhận nhật ký Syslog:
   ```bash
   ssh <SSH_USER>@<IP_KIBANA_GW> "ss -ulnp | grep 9004"
   # (Ví dụ mẫu tham chiếu: ssh <SSH_USER>@<IP_KIBANA> "ss -ulnp | grep 9004")
   ```
   Kết quả mong đợi: Hiển thị tiến trình `elastic-agent` đang lắng nghe trên cổng UDP 9004.
3. Kiểm tra chỉ mục dữ liệu được sinh ra:
   ```bash
   curl -u elastic:<MAT_KHAU_ELASTIC> "http://<IP_ELASTIC_NODE>:9200/_cat/indices/*fortinet*?v"
   curl -u elastic:<MAT_KHAU_ELASTIC> "http://<IP_ELASTIC_NODE>:9200/_cat/indices/metrics-*?v"
   ```

---

### Giai đoạn 5: Cấu hình sao lưu và phục hồi thảm họa (Backup & Disaster Recovery)

#### Bước 5.1: Đăng ký kho lưu trữ Snapshot Repository
Sử dụng công cụ điều phối sao lưu:
```bash
cd D:/neit_ng/prjs_i/auto_provision_configuration/ansible_test
chmod +x run_backup_restore.sh
./run_backup_restore.sh
```
Chọn tùy chọn cấu hình kho lưu trữ:
- Thiết lập đường dẫn chia sẻ `path.repo: ["/mnt/backups/elasticsearch"]` trong cấu hình `elasticsearch.yml` trên toàn bộ các nút.
- Tạo thư mục chia sẻ, cấp quyền sở hữu cho tài khoản `elasticsearch:elasticsearch`.
- Gửi lệnh REST API đăng ký kho lưu trữ kiểu `fs`:
  ```bash
  PUT _snapshot/fs_backup_repo
  {
    "type": "fs",
    "settings": {
      "location": "/mnt/backups/elasticsearch",
      "compress": true
    }
  }
  ```
- Kiểm tra tính hợp lệ của kho lưu trữ qua API `_snapshot/fs_backup_repo/_verify`.

#### Bước 5.2: Thiết lập chính sách Snapshot Lifecycle Management (SLM)
Đăng ký chính sách chụp ảnh định kỳ tự động:
- Lịch thực thi: 01:00 AM hàng ngày.
- Định dạng tên snapshot: `<daily-snap-{now/d}>`.
- Giữ lại tối thiểu 5 bản ghi và tối đa 30 bản ghi, xóa bản ghi cũ hơn 30 ngày.

#### Bước 5.3: Quy trình kiểm thử phục hồi thảm họa (Disaster Recovery Simulation)
Khi cần diễn tập hoặc phục hồi dữ liệu:
1. Thực thi kịch bản:
   ```bash
   ./run_backup_restore.sh
   ```
2. Chọn chức năng khôi phục chỉ mục từ snapshot gần nhất.
3. Kịch bản tự động đóng chỉ mục (close index), phục hồi dữ liệu từ snapshot và mở lại chỉ mục (open index) mà không làm gián đoạn toàn bộ cụm.

---

### Lựa chọn điều phối thay thế: Kịch bản thực thi một chạm (`run_all_onclick.sh`)

Trường hợp kỹ sư muốn thực hiện toàn bộ 5 giai đoạn trên hoàn toàn tự động trong một phiên duy nhất:
1. Cấu hình tệp `vars.conf` tại thư mục gốc.
2. Khởi chạy kịch bản điều phối:
   ```bash
   cd D:/neit_ng/prjs_i/auto_provision_configuration
   chmod +x run_all_onclick.sh
   ./run_all_onclick.sh
   ```
3. Cơ chế hoạt động của `run_all_onclick.sh`:
   - Tự động mở phiên `tmux` mang tên `deploy_session` để bảo vệ tiến trình khỏi đứt kết nối mạng giữa chừng.
   - Nhắc nhập mật khẩu 1 lần duy nhất cho: vCenter, SSH OS, sudo, mật khẩu Elastic, mật khẩu Kibana. Toàn bộ mật khẩu được giữ trong RAM và tự động hủy sau khi kết thúc kịch bản.
   - Tự động đồng bộ các biến mạng, IP và tên template giữa Packer, Terraform và Ansible bằng regex và python script.
   - Chạy tuần tự: Xử lý ISO -> Packer Build -> Terraform Provision -> Ansible Deploy Cluster -> Ansible Observability Setup.
   - Ghi nhật ký đầy đủ ra tệp `deploy_YYYYMMDD_HHMMSS.log`.

---

## 4. Bảng kiểm tra nghiệm thu hệ thống (Verification & Acceptance Checklist)

| Hạng mục kiểm tra | Lệnh / Thao tác xác minh | Tiêu chuẩn đạt yêu cầu | Trạng thái |
| :--- | :--- | :--- | :--- |
| **Mẫu máy ảo Golden Image** | `govc find . -type m -name "<TÊN_TEMPLATE>"` | Template xuất hiện trên vCenter, dung lượng đĩa và định dạng đúng khai báo | [ ] |
| **Cung ứng máy ảo** | `govc vm.info <TÊN_VM>` | Máy ảo ở trạng thái `poweredOn`, nhận đúng địa chỉ IP tĩnh đã cấu hình | [ ] |
| **Độ trễ và định tuyến** | `ping -c 5 <IP_VM>` từ gateway | Mất gói 0%, thời gian phản hồi < 1ms | [ ] |
| **Phân tách tải DRS** | Kiểm tra trên vCenter Cluster -> VM Anti-Affinity | Quy tắc anti-affinity tồn tại, các máy ảo Elasticsearch nằm trên các ESXi host khác nhau | [ ] |
| **Danh mục máy chủ Ansible** | `test -f ansible_test/inventories/lab/hosts.yml` | Tệp tồn tại, các máy ảo phân đúng nhóm `elastic_cluster`, `kibana_gateway` | [ ] |
| **Sức khỏe cụm Elasticsearch** | `curl -u elastic:... "http://<IP_ELASTIC_NODE>:9200/_cluster/health"` | Trạng thái cụm đạt `green`, đủ số lượng node và data node theo cấu hình | [ ] |
| **Mã hóa Transport mTLS** | `curl -u elastic:... "http://<IP_ELASTIC_NODE>:9200/_nodes/_all/settings"` | Tham số `xpack.security.transport.ssl.enabled` có giá trị `true` | [ ] |
| **Giao diện quản trị Kibana** | `curl -s -I http://<IP_KIBANA_GW>:5601/api/status` | Trả về mã phản hồi `HTTP 200 OK`, trạng thái `Overall status: green` | [ ] |
| **Dịch vụ Fleet Server** | `curl -k -I https://<IP_KIBANA_GW>:8220/api/status` | Trả về mã phản hồi `HTTP 200 OK` | [ ] |
| **Trạng thái Elastic Agent** | `elastic-agent status` trên từng máy ảo | Toàn bộ các agent báo trạng thái `HEALTHY` | [ ] |
| **Cổng tiếp nhận Syslog** | `ss -ulnp \| grep 9004` trên máy chủ Gateway | Cổng UDP 9004 đang mở ở chế độ LISTEN bởi tiến trình `elastic-agent` | [ ] |
| **Chính sách vòng đời ILM** | `curl -u elastic:... "http://<IP_ELASTIC_NODE>:9200/_ilm/policy/fortinet-firewall-ilm-policy"` | Chính sách tồn tại, cấu hình đúng điều kiện rollover và delete | [ ] |
| **Kho lưu trữ Snapshot** | `curl -u elastic:... "http://<IP_ELASTIC_NODE>:9200/_snapshot/fs_backup_repo/_verify"` | Xác thực thành công trên toàn bộ các nút trong cụm | [ ] |

---

## 5. Sổ tay xử lý sự cố thường gặp (Troubleshooting Runbook)

### 5.1. Lỗi Packer không nhận cấu hình Autoinstall Subiquity
- **Hiện tượng**: Quá trình khởi động máy ảo dừng lại ở màn hình cài đặt tương tác thủ công của Ubuntu (chọn ngôn ngữ, bàn phím).
- **Nguyên nhân gốc rễ**: 
  - Ubuntu Subiquity không tìm thấy ổ đĩa cấu hình `cidata` hoặc nhãn ổ đĩa CD bị sai lệch.
  - Cú pháp lệnh boot trong GRUB không kích hoạt đúng nhân Linux với tham số `autoinstall ds=nocloud`.
- **Biện pháp khắc phục**:
  1. Kiểm tra tệp `ubuntu-24.04.pkr.hcl`, đảm bảo tham số `cd_label = "cidata"` và danh sách tệp đính kèm đúng đường dẫn: `cd_files = ["${path.root}/http/user-data", "${path.root}/http/meta-data"]`.
  2. Xác minh lệnh boot sử dụng chế độ dòng lệnh GRUB (`c<wait>`) thay vì chỉnh sửa dòng trực tiếp (`e`).
  3. Kiểm tra cú pháp YAML của tệp `http/user-data` bằng công cụ `cloud-init schema --config-file http/user-data`.

### 5.2. Lỗi Packer timeout khi chờ kết nối SSH
- **Hiện tượng**: Tiến trình Packer báo lỗi: `Timeout waiting for SSH to become available: 30m0s`.
- **Nguyên nhân gốc rễ**:
  - Máy ảo không nhận được địa chỉ IP qua DHCP trong phân vùng mạng cài đặt.
  - Mật khẩu mã hóa trong tệp `user-data` không khớp với `ssh_password` được truyền qua Packer CLI.
  - Dịch vụ SSH trên máy ảo bị chặn bởi cấu hình mạng Netplan hoặc chưa hoàn tất cài đặt Subiquity.
- **Biện pháp khắc phục**:
  1. Mở giao diện VMware Remote Console (VMRC) quan sát tiến trình cài đặt máy ảo để xác định thời điểm bị kẹt.
  2. Đảm bảo dải mạng `vcenter_network` gán cho Packer có máy chủ DHCP cấp phát IP tạm thời trong giai đoạn cài đặt.
  3. Kiểm tra lệnh sinh mã băm SHA-512 cho mật khẩu SSH trong kịch bản điều phối, đảm bảo không có ký tự đặc biệt làm sai lệch chuỗi.

### 5.3. Lỗi Terraform không thể gán IP tĩnh hoặc lỗi vSphere Customization
- **Hiện tượng**: Máy ảo tạo thành công nhưng không áp dụng được cấu hình mạng tĩnh, giữ nguyên tên hostname cũ hoặc không thể bật nguồn.
- **Nguyên nhân gốc rễ**:
  - Gói `open-vm-tools` và `cloud-init` xung đột trong quá trình xử lý cấu hình tùy biến vSphere (`vsphere_virtual_machine.clone.customize`).
  - Thiếu cờ cấu hình `disable_vmware_customization: false` trong Cloud-init.
- **Biện pháp khắc phục**:
  1. Đảm bảo trong kịch bản `packer_test/scripts/04_generalize_template.sh` đã làm sạch các thư mục tạm:
     ```bash
     rm -rf /var/lib/cloud/instances/*
     rm -rf /var/lib/cloud/instance
     truncate -s 0 /etc/machine-id
     ```
  2. Xác nhận `open-vm-tools` đã khởi chạy trên template: `systemctl is-active open-vm-tools`.

### 5.4. Lỗi cụm Elasticsearch không kết nạp nút (Cluster Formation Failure)
- **Hiện tượng**: Dịch vụ Elasticsearch chạy trên từng node nhưng cụm không hình thành, API `_cluster/health` báo lỗi timeout hoặc chỉ thấy 1 node độc lập.
- **Nguyên nhân gốc rễ**:
  - Chứng chỉ số mTLS trên lớp `transport` không đồng nhất giữa các nút hoặc bị lỗi cấu hình Keystore.
  - Tên máy chủ trong `discovery.seed_hosts` hoặc `cluster.initial_master_nodes` không phân giải được địa chỉ IP.
  - Tường lửa UFW hoặc iptables trên máy ảo chặn cổng `TCP/9300`.
- **Biện pháp khắc phục**:
  1. Kiểm tra tệp nhật ký: `tail -n 100 /var/log/elasticsearch/elastic-cluster-lab.log`.
  2. Xác minh mở cổng 9300 trên các node:
     ```bash
     sudo ufw allow from <DẢI_MẠNG_CỤM_VM> to any port 9300 proto tcp
     # (Ví dụ mẫu tham chiếu: sudo ufw allow from <NETWORK_SUBNET> to any port 9300 proto tcp)
     ```
  3. Đảm bảo tệp chứng chỉ CA và node certificate được phân phối đồng bộ vào thư mục `/etc/elasticsearch/certs/` với quyền đọc thuộc về người dùng `elasticsearch:elasticsearch`.

### 5.5. Lỗi Kibana không thể kết nối hoặc báo trạng thái Kibana server is not ready
- **Hiện tượng**: Truy cập cổng 5601 hiển thị thông báo "Kibana server is not ready yet".
- **Nguyên nhân gốc rễ**:
  - Mật khẩu tài khoản `kibana_system` trong Keystore của Kibana không khớp với mật khẩu đã đặt trên Elasticsearch.
  - Cụm Elasticsearch đang ở trạng thái `red`.
  - Thiếu khóa mã hóa `xpack.security.encryptionKey`, `xpack.encryptedSavedObjects.encryptionKey`, `xpack.reporting.encryptionKey` trong `kibana.yml`.
- **Biện pháp khắc phục**:
  1. Đặt lại mật khẩu hệ thống `kibana_system`:
     ```bash
     curl -u elastic:<MAT_KHAU_ELASTIC> -X POST "http://<IP_ELASTIC_NODE>:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d '{"password":"<MAT_KHAU_KIBANA>"}'
     ```
  2. Nạp lại mật khẩu vào Kibana Keystore trên máy chủ Kibana Gateway:
     ```bash
     /usr/share/kibana/bin/kibana-keystore add elasticsearch.password
     systemctl restart kibana
     ```

### 5.6. Phục hồi phiên làm việc khi bị ngắt kết nối SSH
- **Hiện tượng**: Mất kết nối SSH tới trạm điều khiển khi đang chạy kịch bản `run_all_onclick.sh`.
- **Nguyên nhân gốc rễ**: Gián đoạn mạng trạm làm việc, timeout phiên SSH terminal.
- **Biện pháp khắc phục**:
  1. Kịch bản đã tích hợp cơ chế chạy trong phiên `tmux`. Kết nối lại trạm điều khiển và khôi phục phiên:
     ```bash
     tmux attach-session -t deploy_session
     ```
  2. Theo dõi tệp nhật ký ghi song song:
     ```bash
     tail -f D:/neit_ng/prjs_i/auto_provision_configuration/deploy_*.log
     ```

---

## 6. Đánh giá các thiếu sót hiện tại trong mã nguồn và lộ trình nâng cấp

Dựa trên việc rà soát toàn diện kho mã nguồn, hệ thống đã đạt mức tự động hóa cao nhưng vẫn tồn tại các điểm giới hạn kỹ thuật cần tiếp tục tối ưu hóa cho môi trường sản xuất quy mô lớn:

### 6.1. Thiếu tính sẵn sàng cao (High Availability) cho lớp cổng Kibana và Fleet Server
- **Hiện trạng trong mã nguồn**: Máy chủ `srv-kibana-gw` là điểm lỗi đơn lẻ (Single Point of Failure - SPoF). Cả Kibana, Fleet Server và cổng tiếp nhận FortiGate Syslog UDP 9004 đều tập trung trên duy nhất máy chủ này. Nếu máy chủ này gặp sự cố phần cứng, toàn bộ việc giám sát và thu thập nhật ký bị gián đoạn.
- **Giải pháp nâng cấp**: 
  - Mở rộng Terraform triển khai 2 máy chủ Gateway (`srv-kibana-gw-01`, `srv-kibana-gw-02`).
  - Bổ sung cấu hình Keepalived gán địa chỉ IP ảo (Virtual IP - VIP) hoặc thiết lập bộ cân bằng tải HAProxy đứng trước để phân tải cho Kibana và Fleet Server.
  - Sử dụng giải pháp cân bằng tải mạng (Network Load Balancer) cho luồng UDP 9004.

### 6.2. Chưa triển khai phân tầng lưu trữ Hot-Warm-Cold trong chính sách ILM
- **Hiện trạng trong mã nguồn**: Role `elastic_stack_config` cấu hình chính sách `fortinet-firewall-ilm-policy` chỉ gồm 2 pha: Pha Hot (Rollover khi đạt 50 GB hoặc 30 ngày) và Pha Delete (xóa sau 15 ngày).
- **Điểm giới hạn**: Toàn bộ 3 nút Elasticsearch đều dùng chung vai trò (`master,data,ingest`) trên cùng một phân vùng lưu trữ, chưa tận dụng được mô hình phân tầng chi phí lưu trữ (Hot: SSD NVMe tốc độ cao; Warm/Cold: HDD dung lượng lớn, giảm số lượng shard replica, force-merge dữ liệu).
- **Giải pháp nâng cấp**: Phân tách vai trò nút trong Ansible inventory (`node.roles: [data_hot]`, `node.roles: [data_warm]`) và bổ sung cấu hình các pha Warm/Cold trong tệp mẫu ILM.

### 6.3. Chưa kích hoạt mã hóa TLS cho giao diện REST API (HTTP 9200)
- **Hiện trạng trong mã nguồn**: Cụm Elasticsearch đã kích hoạt mTLS trên tầng giao tiếp nội bộ (`xpack.security.transport.ssl.enabled: true` trên cổng 9300), tuy nhiên tầng giao diện ứng dụng REST API vẫn đang chạy giao thức HTTP không mã hóa (`http://...:9200`).
- **Điểm giới hạn**: Dữ liệu truyền giữa Kibana, Elastic Agent và Elasticsearch qua mạng nội bộ có nguy cơ bị bắt gói tin (packet sniffing) trong các môi trường mạng dùng chung không an toàn.
- **Giải pháp nâng cấp**: Cấu hình tự động sinh chứng chỉ HTTP SSL/TLS cho cổng 9200, cập nhật `xpack.security.http.ssl.enabled: true` và phân phối CA certificate tới Kibana và Elastic Agent.

### 6.4. Phụ thuộc vào thư mục lưu trữ cục bộ cho tính năng Snapshot
- **Hiện trạng trong mã nguồn**: Role `elastic_backup_restore` cấu hình kho lưu trữ dạng `fs` tại đường dẫn `/mnt/backups/elasticsearch`.
- **Điểm giới hạn**: Để cơ chế sao lưu Snapshot dạng file-system của Elasticsearch hoạt động đồng bộ trên cụm đa nút, đường dẫn này bắt buộc phải là một phân vùng NFS được mount đồng thời trên toàn bộ các nút. Mã nguồn hiện tại chưa bao gồm vai trò tự động dựng và cấu hình máy chủ NFS Server / NFS Client.
- **Giải pháp nâng cấp**: Tích hợp thêm role cài đặt NFS client kết nối vào hệ sinh thái NAS doanh nghiệp hoặc chuyển đổi plugin sang hỗ trợ lưu trữ đối tượng S3 / MinIO (`repository-s3`).

### 6.5. Chưa tự động hóa kiểm tra tài nguyên ESXi trước khi kích hoạt DRS Anti-Affinity
- **Hiện trạng trong mã nguồn**: Module `cluster_rules` trong `terraform_test/main.tf` đang được đặt ở trạng thái tắt mặc định (`enabled = false`) để tránh lỗi khi người dùng triển khai trên môi trường lab chỉ có 1 hoặc 2 ESXi host.
- **Giải pháp nâng cấp**: Bổ sung điều kiện kiểm tra số lượng host vật lý thông qua `data.vsphere_compute_cluster` trong Terraform. Nếu số lượng host >= số lượng máy ảo Elasticsearch, tự động kích hoạt Anti-Affinity Rule ở mức độ mềm (`mandatory = false`); nếu không đủ host, tự động bỏ qua kèm cảnh báo mà không làm gãy luồng khởi tạo.

### 6.6. Hoàn thiện tổng quát hóa mã nguồn và triệt tiêu hardcode đa dự án
- **Hiện trạng trong mã nguồn**: Một số tệp kịch bản hiện tại vẫn chứa các giá trị gán cứng mang tính chất thử nghiệm cục bộ (ví dụ: các khối thay thế regex trong `run_all_onclick.sh` đang nhắm cụ thể vào 4 khóa máy ảo `elastic_01` đến `elastic_03` và `kibana_gw`; dải IP tĩnh mẫu `<IP_SUBNET>` hoặc `<IP_SUBNET>` trong một số tệp con).
- **Điểm giới hạn**: Khi áp dụng cho dự án mới với số lượng máy ảo tùy biến (ví dụ: mở rộng lên cụm 5 nút hoặc tách riêng Dedicated Master Nodes) hoặc quy hoạch mạng khác, kỹ sư buộc phải can thiệp trực tiếp vào mã nguồn kịch bản con thay vì chỉ nạp tệp biến.
- **Giải pháp nâng cấp**:
  - Chuẩn hóa cấu trúc thư mục tham số hóa theo mô hình `environments/<tên_dự_án>/` hoặc `projects/<site_id>/` độc lập, phân tách tuyệt đối giữa mã nguồn logic và dữ liệu cấu hình.
  - Tái cấu trúc logic Terraform và kịch bản điều phối để duyệt động danh sách máy ảo qua `for_each` từ một map tùy biến N nút, loại bỏ hoàn toàn giả định cố định 4 máy ảo.
  - Chuyển đổi toàn bộ kịch bản cấu hình Ansible sang cơ chế phát hiện động (Dynamic Discovery) dựa trên các nhóm máy chủ `[elastic_master]`, `[elastic_data]`, `[kibana_gateway]` thay vì các tên máy cố định.
