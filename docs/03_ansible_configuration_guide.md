# Bộ tự động hóa Ansible: Cụm Elastic Stack HA và hệ thống giám sát Fleet Server

Dự án này cung cấp bộ mã nguồn Ansible thực thi từ môi trường WSL (Windows Subsystem for Linux), tự động hóa toàn diện quy trình triển khai cụm Elastic Stack đạt chuẩn độ sẵn sàng cao (High Availability) và hệ thống quan sát tập trung (Observability) trên các máy ảo Ubuntu 24.04 LTS.

## 1. Kiến trúc cụm máy ảo (Cluster topology)

Hệ thống phân tán trên 4 máy ảo chuyên dụng:

1. **Cụm lưu trữ và xử lý dữ liệu Elasticsearch HA (3 nodes)**:
   - Các nút: `srv-elastic-01` (`<IP_NODE_01>`), `srv-elastic-02` (`<IP_NODE_02>`), `srv-elastic-03` (`<IP_NODE_03>`).
   - Cài đặt trực tiếp từ kho lưu trữ APT chính thức của Elastic (Native Package).
   - Cả 3 nút đều nắm giữ đa vai trò: `master`, `data`, và `ingest`.
   - Giao tiếp liên nút (Transport Port `9300`) được mã hóa mTLS thông qua chứng chỉ `elastic-certificates.p12`.
   - Giao diện REST API (Port `9200`) tiếp nhận yêu cầu từ Kibana và các Elastic Agent.

2. **Máy chủ quản trị Kibana & Fleet Gateway (1 node)**:
   - Nút: `srv-kibana-gw` (`<IP_KIBANA>`).
   - Vận hành giao diện Kibana Web UI (Port `5601`) với cơ chế phân tải đều xuống 3 nút Elasticsearch.
   - Vận hành Fleet Server (Port HTTPS `8220`) điều phối và quản lý tập trung toàn bộ các Elastic Agent.
   - Mở cổng UDP `9004` tiếp nhận trực tiếp luồng nhật ký FortiGate Syslog.

---

## 2. Cấu trúc thư mục dự án

```text
ansible/
├── ansible.cfg                                     # Cấu hình môi trường thực thi Ansible nền tảng
├── requirements.yml                                # Phụ thuộc Galaxy Collections
└── products/
    ├── elastic-stack/                              # Sản phẩm Elastic Stack HA
    │   ├── run_deploy.sh                           # Kịch bản triển khai cụm lõi với cơ chế tiêm mật khẩu RAM
    │   ├── run_observability.sh                    # Kịch bản tự động hóa 100% hệ thống quan sát Day-2
    │   ├── run_backup.sh                           # Kịch bản điều phối sao lưu và phục hồi thảm họa an toàn
    │   ├── inventories/lab/                        # Inventory máy chủ lab (hosts.yml, group_vars)
    │   ├── playbooks/                              # Playbooks: deploy_cluster, site_observability, backup...
    │   └── roles/                                  # Roles: ca_setup, elasticsearch, kibana, fleet_server...
    ├── zabbix/                                     # Khung sản phẩm Zabbix Monitoring
    │   ├── inventories/lab/hosts.yml.example
    │   ├── playbooks/deploy_stack.yml
    │   └── roles/
    ├── haproxy/                                    # Khung sản phẩm HAProxy & Keepalived
    │   ├── inventories/lab/hosts.yml.example
    │   ├── playbooks/deploy_stack.yml
    │   └── roles/
    └── infra-services/                             # Khung sản phẩm dịch vụ hạ tầng mạng (DNS/NTP)
        ├── inventories/lab/hosts.yml.example
        ├── playbooks/deploy_stack.yml
        └── roles/
```

---

## 3. Quy trình triển khai nhanh (Quick start)

### Bước 1: Kích hoạt môi trường thực thi trên WSL

```bash
cd /mnt/d/neit_ng/prjs_i/auto_provision_configuration/ansible/products/elastic-stack
source ~/.venvs/ansible-env/bin/activate
```

### Bước 2: Triển khai cụm nền tảng Elasticsearch và Kibana

Thực thi kịch bản bọc bảo mật để cài đặt cụm dịch vụ lõi:

```bash
./run_deploy.sh
```

Nhập các mật khẩu quản trị ẩn theo yêu cầu trên màn hình. Kịch bản sẽ hoàn tất cài đặt cụm HA trong khoảng 3 đến 5 phút.

### Bước 3: Tự động hóa thiết lập Observability và Elastic Agent

Sau khi Kibana đã sẵn sàng, thực thi kịch bản cấu hình giải pháp quan sát:

```bash
./run_observability_setup.sh
```

Tiến trình sẽ tự động:
- Thiết lập chính sách lưu trữ ILM 15 ngày.
- Kích hoạt các gói tích hợp: Fortinet Syslog (UDP 9004), System Metrics/Logs (18 streams), Elasticsearch Stack Monitoring.
- Tự sinh token bảo mật và kích hoạt Fleet Server HTTPS trên cổng `8220`.
- Cài đặt Elastic Agent trên cả 3 nút Elasticsearch và kết nối về Fleet Server.

---

## 4. Tự động hóa sao lưu và phục hồi dữ liệu (Backup & Disaster Recovery)

Hệ thống cung cấp kịch bản độc lập `run_backup_restore.sh` để quản lý chu trình sao lưu và phục hồi thảm họa:

```bash
./run_backup_restore.sh
```

Menu điều phối cung cấp các tính năng:
1. **Setup Backup Repository & SLM Policy**: Tự động cấu hình `path.repo` trên toàn bộ các nút, tạo thư mục `/mnt/backups/elasticsearch`, đăng ký repository dạng `fs` và kích hoạt chính sách SLM tự động chụp ảnh hàng ngày lúc 01:00 AM.
2. **Take On-Demand Snapshot**: Kích hoạt chụp ngay một bản snapshot tức thời kèm timestamp.
3. **Restore Snapshot**: Đóng các luồng dữ liệu/chỉ mục mục tiêu và phục hồi dữ liệu từ bản snapshot được chỉ định.
4. **List Snapshots & SLM Status**: Liệt kê danh sách các bản snapshot hiện có và trạng thái thực thi của chính sách SLM.

---

## 5. Đặc tả bảo mật và tính lũy nghiệm (Security & Idempotency)

- **Cơ chế bảo mật In-Memory**: Tuyệt đối không lưu mật khẩu thô trong mã nguồn hoặc tệp cấu hình trên đĩa. Các thông tin nhạy cảm được nạp trực tiếp vào bộ nhớ RAM khi chạy kịch bản và tự động giải phóng thông qua cơ chế shell trap khi kết thúc.
- **Tính lũy nghiệm (Idempotency)**: Toàn bộ các tác vụ đều kiểm tra trạng thái thực tế của tệp tin và dịch vụ (thông qua module `stat` và `uri`), cho phép thực thi lại nhiều lần mà không gây đứt kết nối, không làm mới token định danh của Fleet Server và không ghi đè cấu hình đang hoạt động.
