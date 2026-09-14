# Khung tự động hóa hạ tầng và cấu hình dịch vụ tiêu chuẩn doanh nghiệp

Dự án này là kho mã nguồn tự động hóa hạ tầng dưới dạng mã (Infrastructure as Code - IaC) và quản lý cấu hình (Configuration Management - CM) đạt chuẩn doanh nghiệp, tích hợp toàn diện quy trình khởi tạo tài nguyên ảo hóa trên VMware vSphere, chuẩn hóa hệ điều hành qua Packer, triển khai cụm dịch vụ Elastic Stack HA và tự động hóa giải pháp quan sát tập trung với Fleet Server.

---

## 1. Mục lục tài liệu kỹ thuật

Toàn bộ tài liệu kiến trúc, hướng dẫn vận hành và sổ tay kỹ thuật được tổ chức trực tiếp tại thư mục gốc:

| Tài liệu | Nội dung và trọng tâm kỹ thuật |
| :--- | :--- |
| [00_toolchain_installation_guide_windows_wsl.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/00_toolchain_installation_guide_windows_wsl.md) | Cài đặt và chuẩn hóa môi trường làm việc: Terraform, Ansible, govc, Packer trên Windows và WSL. |
| [01_master_architecture_and_repo_design.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/01_master_architecture_and_repo_design.md) | Kiến trúc tổng thể, chiến lược phân tách module và khả năng mở rộng đa nền tảng. |
| [02_vmware_infrastructure_baseline_checklist.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/02_vmware_infrastructure_baseline_checklist.md) | Danh mục kiểm toán hạ tầng vSphere: RBAC, DRS Anti-Affinity, vSphere HA và vSwitch. |
| [03_team_collaboration_and_git_workflow.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/03_team_collaboration_and_git_workflow.md) | Quy chuẩn phối hợp Git: Phân nhánh, khóa trạng thái State Lock, bảo mật bí mật và PR Review. |
| [04_elastic_stack_observability_blueprint.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/04_elastic_stack_observability_blueprint.md) | Bản thiết kế kiến trúc Elastic Stack HA, Fleet Server, FortiGate Syslog (UDP 9004) và ILM 15 ngày. |
| [05_backup_and_rollback_runbook.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/05_backup_and_rollback_runbook.md) | Sổ tay quy trình sao lưu tự động (VM Snapshot, cấu hình) và phục hồi khi xảy ra sự cố khẩn cấp. |
| [06_client_handover_and_day2_operations.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/06_client_handover_and_day2_operations.md) | Hướng dẫn vận hành Day-2: Điều chỉnh tài nguyên máy ảo, bảo trì định kỳ và danh mục nghiệm thu. |
| [07_advanced_automation_packer_maas_roadmap.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/07_advanced_automation_packer_maas_roadmap.md) | Lộ trình tự động hóa nâng cao: Đóng gói Golden Image với Packer và cài đặt Bare-metal qua MAAS. |
| [08_quy_tac_drs_anti_affinity_va_van_hanh_cluster.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/08_quy_tac_drs_anti_affinity_va_van_hanh_cluster.md) | Quy tắc phân tán tải DRS Anti-Affinity và hướng dẫn vận hành cụm trong điều kiện tài nguyên giới hạn. |
| [09_chuan_hoa_quy_trinh_trien_khai_onpremise_si_thuc_te.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/09_chuan_hoa_quy_trinh_trien_khai_onpremise_si_thuc_te.md) | Chuẩn hóa quy trình triển khai On-Premise thực tế của SI và cấu trúc kho mã nguồn dùng chung đa dự án. |

---

## 2. Cấu trúc thư mục kho mã nguồn

```text
auto_provision_configuration/
├── 00_... đến 09_...                           # Các tài liệu đặc tả kiến trúc và sổ tay vận hành
├── README.md                                   # Tài liệu tổng quan và hướng dẫn khởi động nhanh
├── terraform_test/                             # Bộ mã nguồn Terraform khởi tạo hạ tầng vSphere
│   ├── main.tf, variables.tf, outputs.tf       # Khối khai báo tài nguyên trung tâm
│   ├── terraform.tfvars                        # Khai báo thông số cụm máy ảo và mạng
│   ├── run_provision_secure.sh                 # Kịch bản triển khai hạ tầng với cơ chế tiêm mật khẩu RAM
│   └── modules/                                # Các module: folder, content_library, network, compute, cluster_rules
├── ansible_test/                               # Bộ mã nguồn Ansible cấu hình dịch vụ
│   ├── ansible.cfg, inventories/lab/           # Cấu hình môi trường và định nghĩa danh sách host
│   ├── run_ansible_secure.sh                   # Kịch bản cài đặt cụm Elasticsearch HA và Kibana Gateway
│   ├── run_observability_setup.sh              # Kịch bản tự động hóa 100% hệ thống quan sát Day-2 (Fleet & Agents)
│   ├── playbooks/                              # Các playbook triển khai, cấu hình policy và teardown
│   └── roles/                                  # Các role: elastic_cluster, kibana_fleet_gateway, elastic_stack_config, fleet_server, elastic_agent
└── packer_test/                                # Bộ mã nguồn đóng gói mẫu máy ảo Ubuntu 24.04 Golden Image
    ├── ubuntu-24.04.pkr.hcl                    # Định nghĩa Packer HCL template cho vSphere
    ├── build_packer_secure.sh                  # Kịch bản khởi tạo template an toàn
    └── http/user-data                          # Tệp cấu hình tự động cài đặt Cloud-Init / Autoinstall
```

---

## 3. Quy trình thực thi nhanh đầu-cuối (End-to-end workflow)

Toàn bộ quy trình được thực hiện từ môi trường WSL Ubuntu:

### Giai đoạn 1: Đóng gói mẫu máy ảo chuẩn (Golden Image)

```bash
cd /mnt/d/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/packer_test
./build_packer_secure.sh
```
Tiến trình tự động cài đặt hệ điều hành Ubuntu 24.04 LTS, cấu hình mạng Netplan, kích hoạt `open-vm-tools` và chuyển đổi máy ảo thành template `tpl-ubuntu-2404-golden` trên vCenter.

### Giai đoạn 2: Khởi tạo hạ tầng máy ảo và mạng (Terraform)

```bash
cd /mnt/d/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/terraform_test
./run_provision_secure.sh
```
Tiến trình thực hiện:
- Tạo thư mục đối tượng `App_Workloads`, `Infra_Services`.
- Tạo standard port group `VM Network 3` trên switch chuẩn `vSwitch0`.
- Nhân bản 4 máy ảo (`srv-elastic-01`, `srv-elastic-02`, `srv-elastic-03`, `srv-kibana-gw`) từ template chuẩn.
- Cấu hình mạng tĩnh, hostname và tiêm siêu dữ liệu `guestinfo`.
- Thiết lập quy tắc DRS Anti-Affinity phân tách tải các máy ảo dữ liệu.

### Giai đoạn 3: Cài đặt cụm Elastic Stack HA (Ansible Day-1)

```bash
cd /mnt/d/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/ansible_test
./run_ansible_secure.sh
```
Tiến trình tự động cài đặt Elasticsearch Native trên 3 node, thiết lập mã hóa liên node mTLS, cấu hình mật khẩu quản trị và khởi chạy Kibana Gateway.

### Giai đoạn 4: Kích hoạt hệ thống quan sát tập trung (Ansible Day-2)

```bash
./run_observability_setup.sh
```
Tiến trình tự động kích hoạt:
- Chính sách vòng đời chỉ mục ILM 15 ngày.
- Cổng hứng nhật ký tường lửa FortiGate Syslog (UDP 9004).
- 18 luồng chỉ số tài nguyên và nhật ký hệ điều hành (System Integration).
- Luồng giám sát cụm chuyên sâu (Elasticsearch Stack Monitoring).
- Tự động sinh Service Token, triển khai Fleet Server HTTPS và ghi danh Elastic Agent trên toàn bộ các máy chủ.

---

## 4. Quản trị bí mật và kiểm soát trạng thái (Secrets & State Governance)

- **Nguyên tắc không lưu mật khẩu thô (Zero Plaintext Secrets)**: Tất cả mật khẩu vCenter, SSH, sudo và tài khoản Elastic đều được nhắc nhập ẩn qua thiết bị đầu cuối (`read -s -p`) và tiêm trực tiếp vào RAM trong phiên thực thi.
- **Tính lũy nghiệm (Idempotency)**: Toàn bộ kịch bản và playbook đều hỗ trợ thực thi lại nhiều lần một cách an toàn mà không làm thay đổi trạng thái hạ tầng đang hoạt động bình thường.
