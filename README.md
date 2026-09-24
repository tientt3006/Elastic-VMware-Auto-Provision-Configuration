# Khung tự động hóa hạ tầng và cấu hình dịch vụ tiêu chuẩn doanh nghiệp

Dự án này là kho mã nguồn tự động hóa hạ tầng dưới dạng mã (Infrastructure as Code - IaC) và quản lý cấu hình (Configuration Management - CM) đạt chuẩn doanh nghiệp, tích hợp toàn diện quy trình khởi tạo tài nguyên ảo hóa trên VMware vSphere, chuẩn hóa hệ điều hành qua Packer, triển khai cụm dịch vụ Elastic Stack HA và tự động hóa giải pháp quan sát tập trung với Fleet Server.

---

## 1. Mục lục tài liệu kỹ thuật

Hệ thống tài liệu kỹ thuật được phân chia thành tài liệu vận hành trực tiếp trong kho mã nguồn (`docs/`) và bộ tài liệu kiến trúc chuyên sâu trong kho tri thức Obsidian:

### 1.1. Tài liệu vận hành kỹ thuật (`docs/`)

| Tài liệu | Nội dung và trọng tâm kỹ thuật |
| :--- | :--- |
| [00_seed_and_iso_management_guide.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/00_seed_and_iso_management_guide.md) | Thiết lập môi trường trạm điều khiển Automation Seed và quản lý tệp ISO trên hạ tầng vSphere. |
| [01_packer_golden_image_guide.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/01_packer_golden_image_guide.md) | Quy trình đóng gói bản mẫu máy ảo Ubuntu 24.04 LTS tự động qua Subiquity autoinstall và cidata. |
| [01_packer_troubleshooting_runbook.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/01_packer_troubleshooting_runbook.md) | Sổ tay điều tra và xử lý 11 tình huống sự cố thực tế khi đóng gói template Packer trên vSphere. |
| [02_terraform_infrastructure_guide.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/02_terraform_infrastructure_guide.md) | Cung ứng hạ tầng vSphere: Port Group, Folder, DRS Anti-Affinity, nhân bản VM và sinh inventory. |
| [03_ansible_configuration_guide.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/03_ansible_configuration_guide.md) | Cấu hình cụm Elastic Stack HA, Fleet Server, tích hợp quan sát Observability và sao lưu SLM. |
| [04_system_deployment_checklist.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/04_system_deployment_checklist.md) | Kế hoạch triển khai toàn trình, ma trận cổng tường lửa, checklist nghiệm thu và xử lý sự cố. |
| [01_vcsa_unattended_deployment_runbook.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/01_vcsa_unattended_deployment_runbook.md) | Quy trình cài đặt vCenter Server Appliance (VCSA) tự động không giám sát qua vcsa-deploy. |

### 1.2. Bộ tài liệu thiết kế và tiêu chuẩn kiến trúc (Kho tri thức Obsidian)

| Tài liệu | Nội dung và trọng tâm kỹ thuật |
| :--- | :--- |
| [00_toolchain_installation_guide_windows_wsl.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/00_toolchain_installation_guide_windows_wsl.md) | Cài đặt và chuẩn hóa môi trường làm việc: Terraform, Ansible, govc, Packer trên Windows và WSL. |
| [01_master_architecture_and_repo_design.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/01_master_architecture_and_repo_design.md) | Kiến trúc tổng thể, chiến lược phân tách module và khả năng mở rộng đa nền tảng. |
| [02_vmware_infrastructure_baseline_checklist.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/02_vmware_infrastructure_baseline_checklist.md) | Danh mục kiểm toán hạ tầng vSphere: RBAC, DRS Anti-Affinity, vSphere HA và vSwitch. |
| [03_team_collaboration_and_git_workflow.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/03_team_collaboration_and_git_workflow.md) | Quy chuẩn phối hợp Git: Phân nhánh, khóa trạng thái State Lock, bảo mật bí mật và PR Review. |
| [04_elastic_stack_observability_blueprint.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/04_elastic_stack_observability_blueprint.md) | Bản thiết kế kiến trúc Elastic Stack HA, Fleet Server, FortiGate Syslog (UDP 9004) và ILM 15 ngày. |
| [05_backup_and_rollback_runbook.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/05_backup_and_rollback_runbook.md) | Sổ tay quy trình sao lưu tự động (VM Snapshot, cấu hình) và phục hồi khi xảy ra sự cố khẩn cấp. |
| [06_client_handover_and_day2_operations.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/06_client_handover_and_day2_operations.md) | Hướng dẫn vận hành và bàn giao: Điều chỉnh tài nguyên máy ảo, bảo trì định kỳ và danh mục nghiệm thu. |
| [07_advanced_automation_packer_maas_roadmap.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/07_advanced_automation_packer_maas_roadmap.md) | Lộ trình tự động hóa nâng cao: Đóng gói Golden Image với Packer và cài đặt Bare-metal qua MAAS. |
| [08_quy_tac_drs_anti_affinity_va_van_hanh_cluster.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/08_quy_tac_drs_anti_affinity_va_van_hanh_cluster.md) | Quy tắc phân tán tải DRS Anti-Affinity và hướng dẫn vận hành cụm trong điều kiện tài nguyên giới hạn. |
| [09_chuan_hoa_quy_trinh_trien_khai_onpremise_si_thuc_te.md](file:///d:/neit_ng/obsidian_vault_neit/IUNI/auto_provision_configuration/09_chuan_hoa_quy_trinh_trien_khai_onpremise_si_thuc_te.md) | Chuẩn hóa quy trình triển khai On-Premise thực tế của SI và cấu trúc kho mã nguồn dùng chung đa dự án. |

---

## 2. Cấu trúc thư mục kho mã nguồn

```text
auto_provision_configuration/
├── run.sh                                  # Kịch bản điều phối chính (Main Orchestrator)
├── run_all_onclick.sh                      # Kịch bản điều phối tương thích ngược
├── lib/                                    # Thư viện hàm shell dùng chung (common, secrets, vsphere)
├── seed/                                   # Bộ công cụ khởi tạo trạm điều khiển Ubuntu và quản lý ISO
│   ├── setup_env.sh                        # Cài đặt tự động Packer, Terraform, Ansible, govc
│   ├── download_iso.sh                     # Tự động tải ISO Ubuntu/VCSA kèm kiểm tra SHA256
│   └── upload_iso.sh                       # Đẩy ISO lên Datastore hoặc VMware Content Library
├── vcsa_deploy/                            # Bộ tự động hóa cài đặt vCenter Server Appliance (VCSA)
│   ├── deploy_vcsa_unattended.sh           # Kịch bản điều phối cài đặt VCSA qua vcsa-deploy
│   ├── templates/embedded_vcs_on_esxi.json.tpl # Bản mẫu đặc tả cấu hình JSON cho VCSA
│   ├── vcsa_vars.env.example               # Tệp khai báo biến hạ tầng mẫu cho VCSA
│   └── 01_vcsa_unattended_deployment_runbook.md# Sổ tay quy trình kỹ thuật cài đặt VCSA không giám sát
├── packer/                                 # Tầng nền tảng: Golden Image Templates
│   ├── build.sh                            # Kịch bản khởi tạo template an toàn (tham số --template)
│   ├── templates/ubuntu-24.04/             # Template Ubuntu 24.04 LTS (HCL, user-data, scripts)
│   └── ansible/                            # Playbook provisioner cho Packer
├── terraform/                              # Tầng nền tảng: IaC Modules & Profiles
│   ├── modules/                            # Các module dùng chung: compute, network, folder, cluster_rules, content_library
│   └── profiles/
│       ├── elastic-stack/                  # Hồ sơ triển khai cụm Elastic Stack HA
│       └── generic-vms/                    # Hồ sơ cấp phát máy ảo tùy biến đa mục đích
├── ansible/                                # Tầng nền tảng: Ansible Configuration
│   ├── ansible.cfg                         # Cấu hình Ansible nền tảng hỗ trợ đa sản phẩm
│   ├── requirements.yml                    # Collection và phụ thuộc
│   └── products/
│       ├── elastic-stack/                  # Triển khai Elastic Stack (roles, playbooks, scripts)
│       ├── zabbix/                         # Khung triển khai Zabbix Monitoring
│       ├── haproxy/                        # Khung triển khai HAProxy & Keepalived
│       └── infra-services/                 # Khung triển khai dịch vụ hạ tầng mạng (DNS/NTP)
├── products/                               # Tầng sản phẩm: Cấu hình điều phối sản phẩm
│   ├── elastic-stack/                      # Cấu hình, menu và script của Elastic Stack
│   │   ├── configure.sh                    # Thu thập tham số và đồng bộ tệp cấu hình
│   │   ├── menu.sh                         # Menu điều phối chuyên biệt Elastic Stack
│   │   └── scripts/
│   │       └── manage_vsphere_observability.sh # Tích hợp giám sát vSphere & Syslog ESXi
│   ├── zabbix/                             # Cấu hình và menu Zabbix
│   ├── haproxy/                            # Cấu hình và menu HAProxy
│   └── infra-services/                     # Cấu hình và menu dịch vụ hạ tầng mạng
└── docs/                                   # Tài liệu kỹ thuật vận hành tập trung
    ├── 00_seed_and_iso_management_guide.md
    ├── 01_packer_golden_image_guide.md
    ├── 01_packer_troubleshooting_runbook.md
    ├── 02_terraform_infrastructure_guide.md
    ├── 03_ansible_configuration_guide.md
    └── 04_system_deployment_checklist.md
```

---

## 3. Quy trình thực thi nhanh đầu-cuối (End-to-end workflow)

Toàn bộ quy trình có thể chạy qua kịch bản điều phối trung tâm:
```bash
./run.sh
```

Hoặc thực thi độc lập từng giai đoạn:

### Giai đoạn 1: Đóng gói mẫu máy ảo chuẩn (Golden Image)

```bash
cd packer
./build.sh --template ubuntu-24.04
```
Tiến trình tự động cài đặt hệ điều hành Ubuntu 24.04 LTS, cấu hình mạng Netplan, kích hoạt `open-vm-tools` và chuyển đổi máy ảo thành template `tpl-ubuntu-2404-golden` trên vCenter.

### Giai đoạn 2: Khởi tạo hạ tầng máy ảo và mạng (Terraform)

```bash
cd terraform/profiles/elastic-stack
./run.sh
```
Tiến trình thực hiện:
- Tạo thư mục đối tượng `App_Workloads`, `Infra_Services`.
- Tạo standard port group `VM Network 3` trên switch chuẩn `vSwitch0`.
- Nhân bản 4 máy ảo (`srv-elastic-01`, `srv-elastic-02`, `srv-elastic-03`, `srv-kibana-gw`) từ template chuẩn.
- Cấu hình mạng tĩnh, hostname và tiêm siêu dữ liệu `guestinfo`.
- Thiết lập quy tắc DRS Anti-Affinity phân tách tải các máy ảo dữ liệu.

### Giai đoạn 3: Cài đặt cụm Elastic Stack HA (Ansible)

```bash
cd ansible/products/elastic-stack
./run_deploy.sh
```
Tiến trình tự động cài đặt Elasticsearch Native trên 3 node, thiết lập mã hóa liên node mTLS, cấu hình mật khẩu quản trị và khởi chạy Kibana Gateway.

### Giai đoạn 4: Kích hoạt hệ thống quan sát tập trung (Ansible)

```bash
cd ansible/products/elastic-stack
./run_observability.sh
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
