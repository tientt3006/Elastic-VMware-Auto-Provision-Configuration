# Bộ tự động hóa Terraform: Khởi tạo hạ tầng vSphere, mạng và triển khai cụm máy ảo Elastic Stack

## 1. Tổng quan dự án

Dự án Terraform này chịu trách nhiệm tự động hóa việc khởi tạo và định hình toàn bộ hạ tầng ảo hóa trên nền tảng VMware vSphere 8.0, tích hợp với mẫu máy ảo chuẩn (Golden Template `tpl-ubuntu-2404-golden`) do HashiCorp Packer đóng gói.

### Các năng lực cốt lõi
1. **Quản lý cấu trúc thư mục (Inventory Folders)**: Khởi tạo hàng loạt các thư mục phân cấp trong vSphere inventory (`App_Workloads`, `Infra_Services`).
2. **Đồng bộ Content Library**: Đồng bộ mẫu máy ảo vào thư viện Content Library `Content Lib DS_100_3_1` dưới dạng OVF template mà không làm thay đổi hay xóa máy ảo gốc tại thư mục `VM Template`.
3. **Định hình mạng cluster (Cluster Networking)**: Tự động khởi tạo đồng bộ các standard port group `VM Network 3` và `VM Network 4` trên switch chuẩn `vSwitch0` trên toàn bộ các máy chủ ESXi (`<ESXI_HOST_01>`, `<ESXI_HOST_02>`).
4. **Khởi tạo và tùy biến cụm máy ảo (Customized Compute Provisioning)**: Nhân bản 4 máy ảo chuyên dụng cho cụm Elastic Stack HA và Kibana Gateway, tự động cấu hình địa chỉ IP tĩnh, tên máy chủ, card mạng và tiêm siêu dữ liệu `guestinfo`.
5. **Quy tắc phân tán tải DRS (DRS Anti-Affinity Rule)**: Thiết lập quy tắc chống gom cụm (Anti-Affinity) trên VMware DRS để phân tách các máy ảo Elasticsearch trên các máy chủ vật lý khác nhau.

---

## 2. Cấu trúc thư mục dự án

```text
terraform/
├── modules/                        # Các module dùng chung (compute, network, folder, cluster_rules, content_library)
└── profiles/
    └── elastic-stack/
        ├── versions.tf             # Ràng buộc phiên bản Terraform core và vSphere provider
        ├── variables.tf            # Định nghĩa schema đầu vào có kiểm tra kiểu dữ liệu
        ├── main.tf                 # Tệp điều phối trung tâm kết nối các data source và module
        ├── outputs.tf              # Xuất thông tin IP, ID tài nguyên và inventory cho Ansible
        ├── terraform.tfvars.example # Tệp mẫu tham khảo không chứa thông tin nhạy cảm
        ├── run.sh                  # Kịch bản thực thi an toàn với cơ chế tiêm mật khẩu In-Memory
        └── templates/
            └── hosts.yml.tpl       # Template sinh inventory Ansible
├── README.md                       # Tài liệu hướng dẫn vận hành kỹ thuật
├── giai_thich_ke_hoach_thuc_thi.md # Phân tích chi tiết các giai đoạn Plan và Apply
└── modules/
    ├── folder/                     # Module khởi tạo hàng loạt thư mục máy ảo
    ├── content_library/            # Module đồng bộ mẫu máy ảo vào Content Library
    ├── network/                    # Module tạo port group trên vSwitch vật lý
    ├── compute/                    # Module nhân bản và tùy biến hệ điều hành máy ảo
    └── cluster_rules/              # Module cấu hình quy tắc DRS Anti-Affinity
```

---

## 3. Đặc tả thông số hạ tầng mục tiêu

### Ánh xạ tài nguyên vSphere

| Loại tài nguyên | Tên đối tượng vSphere | Định danh / MOID |
| :--- | :--- | :--- |
| **vCenter Server** | `<VCENTER_IP>` | vCenter Server Appliance |
| **Datacenter** | `Datacenter` | `datacenter-3` |
| **Compute Cluster** | `Cluster1` | `domain-c2113` |
| **Datastore** | `DS_100_3` | `datastore-2006` |
| **Content Library** | `Content Lib DS_100_3_1` | `a0bc3584-8b7c-40cc-b2fd-bae7a6b9bf6c` |
| **Golden Template nguồn** | `tpl-ubuntu-2404-golden` | `421cf3ab-92d7-1036-2a5e-2f3e8e410d0a` |
| **Máy chủ ESXi 01** | `<ESXI_HOST_01>` | `host-2001` |
| **Máy chủ ESXi 02** | `<ESXI_HOST_02>` | `host-10009` |
| **Switch ảo chuẩn** | `vSwitch0` | Standard vSwitch |

### Hồ sơ cấu hình các máy ảo mục tiêu (Workload Profiles)

| Tham số | srv-elastic-01 | srv-elastic-02 | srv-elastic-03 | srv-kibana-gw |
| :--- | :--- | :--- | :--- | :--- |
| **Tên đối tượng VM** | `srv-elastic-01` | `srv-elastic-02` | `srv-elastic-03` | `srv-kibana-gw` |
| **Tên máy (Hostname)**| `elastic-01` | `elastic-02` | `elastic-03` | `kibana-gw` |
| **Thư mục mục tiêu** | `App_Workloads` | `App_Workloads` | `App_Workloads` | `App_Workloads` |
| **Định danh (`guestinfo.node.id`)** | `101` | `102` | `103` | `104` |
| **Số lượng vCPU** | `2` vCPU | `2` vCPU | `2` vCPU | `2` vCPU |
| **Dung lượng RAM** | `6144` MB (6 GB) | `6144` MB (6 GB) | `6144` MB (6 GB) | `4096` MB (4 GB) |
| **Dung lượng ổ đĩa gốc**| `50` GB | `50` GB | `50` GB | `40` GB |
| **Port Group mạng** | `VM Network 3` | `VM Network 3` | `VM Network 3` | `VM Network 3` |
| **Địa chỉ IPv4 tĩnh** | `<IP_NODE_01>/24` | `<IP_NODE_02>/24` | `<IP_NODE_03>/24` | `<IP_KIBANA>/24` |
| **Cổng mặc định (Gateway)** | `<GATEWAY_IP>` | `<GATEWAY_IP>` | `<GATEWAY_IP>` | `<GATEWAY_IP>` |
| **Vai trò cụm (`role`)** | `master_data_ingest` | `master_data_ingest` | `master_data_ingest` | `kibana_fleet_gateway` |

---

## 4. Quy trình vận hành và thực thi an toàn

Thực hiện từ môi trường dòng lệnh WSL Ubuntu:

### Bước 1: Điều hướng vào thư mục dự án

```bash
cd /mnt/d/neit_ng/prjs_i/auto_provision_configuration/terraform/profiles/elastic-stack
```

### Bước 2: Khởi chạy kịch bản triển khai bảo mật

```bash
./run.sh
```

Tiến trình yêu cầu nhập ẩn mật khẩu tài khoản vCenter (`<VCENTER_USER>`). Mật khẩu được nạp vào biến môi trường `TF_VAR_vsphere_password` trong bộ nhớ RAM và tự động hủy sau khi lệnh hoàn tất.

### Bước 3: Đánh giá kế hoạch (Plan Review) và xác nhận

Kịch bản thực hiện `terraform plan`, hiển thị tổng số tài nguyên cần tạo mới hoặc cập nhật. Khi hệ thống yêu cầu xác nhận:
- Nhập `yes` để tiến hành nhân bản máy ảo và cấu hình mạng.
- Nhập `no` để hủy tiến trình nếu phát hiện bất thường.

### Bước 4: Kiểm tra kết quả đầu ra

Sau khi hoàn tất, Terraform xuất ra danh sách địa chỉ IP phục vụ trực tiếp cho tệp inventory của Ansible:

```text
Outputs:
ansible_inventory_hosts = [
  "<IP_NODE_01>",
  "<IP_NODE_02>",
  "<IP_NODE_03>",
  "<IP_KIBANA>"
]
```
