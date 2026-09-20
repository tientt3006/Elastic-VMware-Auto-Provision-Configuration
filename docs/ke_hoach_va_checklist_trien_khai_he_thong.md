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

### 1.3. Luồng điều phối toàn trình
```text
[Trạm WSL/Linux]
 ├── 0. seed: Setup công cụ + Tải ISO lên Datastore
 ├── 1. packer: Tạo tpl-ubuntu-2404-golden (Autoinstall)
 ├── 2. terraform/profiles/elastic-stack: Tạo Network, VM, DRS Rules -> Sinh inventory
 ├── 3. ansible/products/elastic-stack: Cài Elasticsearch HA + Kibana Gateway
 ├── 4. ansible/products/elastic-stack: Cấu hình ILM, Fleet Server, FortiGate Syslog, Enroll Agents
 ├── 5. seed/manage_vsphere_observability.sh: Tích hợp giám sát VMware vCenter & ESXi
 └── 6. ansible/products/elastic-stack/run_backup.sh: Cấu hình SLM Backup & Restore
```

Menu điều phối tập trung tại `run_all_onclick.sh`:
1. Chạy toàn bộ quy trình
2. Chỉ tạo Golden Template (Packer)
3. Chỉ cấp phát hạ tầng (Terraform Provisioning)
4. Chỉ cấu hình ứng dụng (Ansible Configuration)
5. Tích hợp giám sát hạ tầng VMware vSphere
6. Hoàn tác giám sát hạ tầng VMware vSphere

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
| `UDP/123`, `53` | Tất cả VM -> NTP, DNS | Đồng bộ thời gian, phân giải tên miền |

### 2.3. Trạm điều khiển (Seed Station)
- [ ] OS: Ubuntu 22.04/24.04 hoặc WSL2.
- [ ] Công cụ: `terraform` (>=1.5), `packer` (>=1.9), `ansible` (>=2.15), `govc`, `tmux`, `jq`.
- [ ] Khóa SSH RSA/ED25519 đã được tạo (`~/.ssh/id_ed25519`).

---

## 3. Quy trình thực thi chi tiết

### Giai đoạn 0: Môi trường & Cấu hình
1. **Setup công cụ**: Chạy `./setup_automation_env.sh` (cài Terraform, Packer, Ansible, govc).
2. **Tải ISO & đẩy lên vCenter**: Chạy `./download_iso.sh --ubuntu` và dùng `govc datastore.upload`.
3. **Cấu hình `vars.conf`**: Cập nhật thông tin vCenter, Datastore, IP, mật khẩu tại tệp `vars.conf`.

### Giai đoạn 1: Đóng gói Golden Image (Packer)
1. **Cấu hình**: Chỉnh thông số trong `packer.pkrvars.hcl`. Sử dụng `cidata` autoinstall.
2. **Build an toàn**: Chạy `./build_packer_secure.sh`. Kịch bản nạp mật khẩu in-memory, cài VM, chạy các script dọn dẹp (xóa machine-id, DHCP, logs) và chuyển thành template `tpl-ubuntu-2404-golden`.

### Giai đoạn 2: Cung ứng hạ tầng (Terraform)
1. **Cấu hình**: Chỉnh sửa `terraform.tfvars` (VM folders, port groups, VM specs, IP tĩnh).
2. **Thực thi**: Chạy `./run_provision_secure.sh`. Quá trình tạo network, clone VM, cấu hình tĩnh qua guestinfo, thiết lập DRS rules và kết xuất inventory `hosts.yml`.

### Giai đoạn 3: Cấu hình Elastic Stack HA (Ansible)
1. **Kiểm tra**: Kiểm tra IP trong `hosts.yml` và chạy `ansible -m ping`.
2. **Triển khai**: Chạy `./run_ansible_secure.sh`.
   - Áp dụng tối ưu OS (`vm.max_map_count`, swap, limits).
   - Cài Elasticsearch, cấu hình mTLS, thiết lập mật khẩu admin/kibana.
   - Cài Kibana và kết nối tới cụm Elasticsearch.

### Giai đoạn 4: Kích hoạt Observability (Ansible)
1. **Thực thi**: Chạy `./run_observability_setup.sh`.
   - Cấu hình ILM Policy (Rollover 50GB/30D, Delete 15D).
   - Cài tích hợp Fortinet, Syslog UDP 9004, System metrics.
   - Triển khai Fleet Server trên Gateway và enroll Elastic Agent trên các node Elasticsearch.

### Giai đoạn 5: Tích hợp giám sát hạ tầng VMware vSphere
1. **Thực thi**: Chọn tùy chọn `5` trong menu `run_all_onclick.sh` hoặc chạy `seed/manage_vsphere_observability.sh apply`.
2. **Tiến trình**:
   - Cài đặt và kích hoạt Elastic package `vsphere` trên Kibana.
   - Cấu hình luồng Metrics (Datastore, Host, Cluster, VM) thông qua vCenter SDK.
   - Cấu hình vCenter Syslog Forwarding (đẩy log sự kiện vCenter về Kibana Gateway).

### Giai đoạn 6: Sao lưu và Phục hồi (SLM)
1. **Thực thi**: Chạy `./run_backup_restore.sh`.
2. **Cấu hình**: Đăng ký `fs` snapshot repo tại `/mnt/backups/elasticsearch`.
3. **SLM**: Thiết lập chính sách backup định kỳ (01:00 AM, giữ 5-30 bản). Hỗ trợ kịch bản khôi phục tự động.

> **Thực thi 1 chạm**: Kỹ sư có thể sử dụng `./run_all_onclick.sh` để chạy từ Giai đoạn 1 đến Giai đoạn 4 liên tục trong `tmux`, bảo vệ biến mật khẩu in-memory và sinh log đầy đủ. Đối với Giai đoạn 5, sử dụng menu tùy chọn số 5.

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
