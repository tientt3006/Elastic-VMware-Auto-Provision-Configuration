# Kế hoạch tái cấu trúc kho mã nguồn: Từ Elastic-Only sang nền tảng quản lý hạ tầng VMware đa mục đích

## 1. Bối cảnh và mục tiêu

### 1.1. Hiện trạng

Kho mã nguồn hiện tại (`auto_provision_configuration`) được thiết kế theo mô hình **nguyên khối chuyên dụng** (monolithic single-purpose), trong đó toàn bộ luồng điều phối, cấu hình biến, cấu trúc thư mục và kịch bản điều phối đều gắn chặt vào một mục đích duy nhất: triển khai Elastic Stack HA.

**Các vấn đề cấu trúc cần giải quyết:**

| Vấn đề | Chi tiết |
| :--- | :--- |
| Tên thư mục mang tính tạm thời | `packer_test`, `terraform_test`, `ansible_test` -- hậu tố `_test` không phản ánh bản chất sản phẩm đã ổn định. |
| Kịch bản điều phối nguyên khối | `run_all_onclick.sh` (631 dòng) chứa toàn bộ logic: thu thập biến, cấu hình template, quản lý ISO, menu điều phối, gọi Packer/Terraform/Ansible. Không thể mở rộng mà không phá vỡ cấu trúc hiện tại. |
| Biến cứng dành riêng cho Elastic | `vars.conf` và hàm `gather_vars()` khai báo cứng các biến `IP_E01`, `IP_E02`, `IP_E03`, `IP_KBN`, `ELASTIC_PASS`, `KIBANA_PASS` -- không dùng lại được cho sản phẩm khác. |
| Ghép nối chặt Terraform-Ansible | Template `hosts.yml.tpl` của Terraform sinh trực tiếp inventory Ansible với các nhóm `elastic_cluster`, `kibana_gateway`, `fleet_server` cố định. Không tái sử dụng được cho sản phẩm khác (Zabbix, HAProxy,...). |
| Hàm `configure_templates()` liên kết cứng | Dùng `sed` ghi trực tiếp IP Elastic vào `terraform.tfvars` và `group_vars/all/main.yml`. Mỗi sản phẩm mới phải sửa trực tiếp vào hàm này. |
| Thiếu tầng trừu tượng chung | Terraform modules (`compute`, `network`, `folder`, `cluster_rules`) thực tế là module dùng chung cho mọi sản phẩm nhưng bị đặt bên trong thư mục `terraform_test` cùng cấp với cấu hình riêng Elastic. |

### 1.2. Mục tiêu tái cấu trúc

Chuyển đổi kho mã nguồn sang mô hình **nền tảng đa mục đích (Multi-Product Platform)** với các mục tiêu:

1. **Tách rời tầng nền tảng (Platform) và tầng sản phẩm (Products)**: Module Terraform dùng chung, Packer template dùng chung, thư viện shell dùng chung nằm tại tầng nền tảng. Mỗi sản phẩm (Elastic, Zabbix, HAProxy,...) là một thư mục độc lập chứa cấu hình và playbook riêng.
2. **Kịch bản điều phối phân tầng (Layered Orchestration)**: Menu chính gọi vào menu con của từng sản phẩm. Thêm sản phẩm mới chỉ cần tạo thư mục và đăng ký vào menu, không sửa logic lõi.
3. **Tên thư mục và tệp phản ánh đúng bản chất kiến trúc**: Loại bỏ hậu tố `_test`, đặt tên theo chức năng kỹ thuật.
4. **Tái sử dụng tối đa**: Các script wrapper (`build_packer_secure.sh`, `run_provision_secure.sh`) và Terraform modules hoạt động độc lập, bất kỳ sản phẩm nào cũng gọi được.

---

## 2. Kiến trúc cấu trúc thư mục mới

### 2.1. Sơ đồ tổng quan

```text
auto_provision_configuration/
├── README.md                               # Tài liệu tổng quan nền tảng
├── run.sh                                  # Kịch bản điều phối chính (Main Orchestrator)
├── lib/                                    # Thư viện hàm shell dùng chung
│   ├── common.sh                           # Hàm tiện ích: log, prompt, validate, tmux
│   ├── secrets.sh                          # Hàm thu thập mật khẩu in-memory
│   └── vsphere.sh                          # Hàm tương tác vSphere: govc, ISO, template check
│
├── seed/                                   # Bộ khởi tạo trạm điều khiển (đổi tên từ automation_seed)
│   ├── setup_env.sh                        # Cài đặt Packer, Terraform, Ansible, govc
│   ├── download_iso.sh                     # Tải ISO Ubuntu/CentOS
│   └── upload_iso.sh                       # Đẩy ISO lên vCenter Datastore
│
├── packer/                                 # Tầng nền tảng: Golden Image Templates
│   ├── build.sh                            # Kịch bản build an toàn (tổng quát hóa)
│   ├── templates/                          # Thư mục chứa các HCL template theo hệ điều hành
│   │   ├── ubuntu-24.04/                   # Template Ubuntu 24.04
│   │   │   ├── ubuntu-24.04.pkr.hcl
│   │   │   ├── variables.pkr.hcl
│   │   │   ├── packer.pkrvars.hcl.example
│   │   │   ├── http/                       # Tệp Autoinstall (user-data, meta-data)
│   │   │   └── scripts/                    # Script hardening OS
│   │   ├── ubuntu-22.04/                   # (mở rộng sau)
│   │   ├── rocky-9/                        # (mở rộng sau)
│   │   └── windows-2022/                   # (mở rộng sau)
│   └── ansible/                            # Packer Ansible provisioner (nếu cần)
│       ├── ansible.cfg
│       └── playbook.yml
│
├── terraform/                              # Tầng nền tảng: IaC Modules & Profiles
│   ├── modules/                            # Terraform modules dùng chung
│   │   ├── compute/
│   │   ├── network/
│   │   ├── folder/
│   │   ├── cluster_rules/
│   │   └── content_library/
│   └── profiles/                           # Hồ sơ triển khai theo sản phẩm
│       ├── elastic-stack/                  # Profile cho Elastic Stack
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── versions.tf
│       │   ├── terraform.tfvars.example
│       │   ├── run.sh
│       │   └── templates/
│       ├── generic-vms/                    # Profile đa mục đích (mở rộng sau)
│       ├── zabbix/                         # (mở rộng sau)
│       └── haproxy/                        # (mở rộng sau)
│
├── ansible/                                # Tầng nền tảng: Ansible Configuration
│   ├── ansible.cfg
│   ├── requirements.yml
│   └── products/                           # Playbook và role theo sản phẩm
│       ├── elastic-stack/
│       │   ├── inventories/lab/
│       │   ├── playbooks/
│       │   ├── roles/
│       │   ├── run_deploy.sh
│       │   ├── run_observability.sh
│       │   └── run_backup.sh
│       ├── zabbix/                         # (mở rộng sau)
│       ├── haproxy/                        # (mở rộng sau)
│       └── infra-services/                 # (mở rộng sau)
│
├── products/                               # Tầng sản phẩm: Cấu hình điều phối
│   └── elastic-stack/
│       ├── product.conf                    # Biến đặc thù sản phẩm
│       ├── product.conf.example
│       ├── menu.sh                         # Menu con của sản phẩm
│       └── configure.sh                    # Logic điền biến vào Terraform/Ansible
│
├── vcsa_deploy/                            # Bộ cài đặt VCSA (giữ nguyên)
│
└── docs/                                   # Tài liệu kỹ thuật (tập trung)
    ├── 00_toolchain_installation.md
    ├── 01_architecture_and_design.md
    └── packer_issues_and_solutions.md
```

### 2.2. Giải thích nguyên tắc thiết kế

**Tầng nền tảng (Platform Layer)** gồm `lib/`, `seed/`, `packer/`, `terraform/modules/`:
- Chứa các thành phần tái sử dụng cho mọi sản phẩm.
- Terraform modules (`compute`, `network`, `folder`) hoạt động như thư viện hạ tầng -- bất kỳ profile nào cũng `source = "../../modules/compute"`.
- Packer templates phân theo hệ điều hành, không theo sản phẩm. Template `ubuntu-24.04` dùng chung cho Elastic, Zabbix hay bất kỳ dịch vụ nào cần Ubuntu.

**Tầng sản phẩm (Product Layer)** gồm `products/`, `terraform/profiles/`, `ansible/products/`:
- Mỗi sản phẩm là một bộ ba: `products/<name>/` (biến + menu) + `terraform/profiles/<name>/` (hạ tầng) + `ansible/products/<name>/` (cấu hình).
- Thêm sản phẩm mới chỉ cần tạo 3 thư mục tương ứng và đăng ký vào `run.sh`.

---

## 3. Luồng điều phối phân tầng (Menu Architecture)

### 3.1. Menu chính (`run.sh`)

```text
==============================================================================
HỆ THỐNG QUẢN LÝ HẠ TẦNG VMWARE - NỀN TẢNG TỰ ĐỘNG HÓA
==============================================================================
1) Công cụ nền tảng (Platform Tools)
   ├── 1.1) Tạo Golden Template (Packer)          --> Chọn hệ điều hành
   ├── 1.2) Cấp phát hạ tầng tùy chỉnh (Terraform) --> Profile chung
   ├── 1.3) Quản lý ISO trên Datastore
   └── 1.4) Cài đặt môi trường công cụ (Seed)
2) Triển khai Elastic Stack
   ├── 2.1) Chạy toàn bộ quy trình (Đầu-Cuối)
   ├── 2.2) Chỉ tạo Golden Template (Packer)
   ├── 2.3) Chỉ cấp phát hạ tầng (Terraform)
   ├── 2.4) Chỉ cấu hình ứng dụng (Ansible)
   ├── 2.5) Tích hợp giám sát VMware vSphere
   └── 2.6) Hoàn tác giám sát VMware vSphere
3) Triển khai Zabbix Server         [Phát triển sau]
4) Triển khai HAProxy / Load Balancer [Phát triển sau]
5) Triển khai dịch vụ hạ tầng (DNS/DHCP/NTP) [Phát triển sau]
0) Thoát
==============================================================================
```

### 3.2. Cơ chế hoạt động

```text
run.sh (Menu chính)
 ├── source lib/common.sh        # Nạp hàm dùng chung
 ├── source lib/secrets.sh       # Nạp hàm thu thập mật khẩu
 ├── source lib/vsphere.sh       # Nạp hàm tương tác vSphere
 │
 ├── [1] Platform Tools
 │    └── Gọi trực tiếp packer/build.sh, terraform/profiles/generic-vms/run.sh,...
 │
 └── [2] Elastic Stack
      └── source products/elastic-stack/menu.sh
           ├── source products/elastic-stack/product.conf
           ├── source products/elastic-stack/configure.sh
           ├── Gọi packer/build.sh
           ├── Gọi terraform/profiles/elastic-stack/run.sh
           └── Gọi ansible/products/elastic-stack/run_deploy.sh
```

---

## 4. Bảng ánh xạ chi tiết: Tên cũ -> Tên mới

### 4.1. Thư mục

| Đường dẫn cũ | Đường dẫn mới | Ghi chú |
| :--- | :--- | :--- |
| `packer_test/` | `packer/templates/ubuntu-24.04/` | Nội dung HCL, scripts, http chuyển vào |
| `packer_test/scripts/` | `packer/templates/ubuntu-24.04/scripts/` | Di chuyển theo |
| `packer_test/http/` | `packer/templates/ubuntu-24.04/http/` | Di chuyển theo |
| `packer_test/ansible/` | `packer/ansible/` | Giữ ở cấp nền tảng |
| `terraform_test/` | `terraform/profiles/elastic-stack/` | Tệp main.tf, variables.tf, outputs.tf,... |
| `terraform_test/modules/` | `terraform/modules/` | Nâng lên cấp nền tảng (dùng chung) |
| `terraform_test/templates/` | `terraform/profiles/elastic-stack/templates/` | Giữ gắn với profile |
| `ansible_test/` | `ansible/` | Bỏ hậu tố `_test` |
| `ansible_test/roles/` | `ansible/products/elastic-stack/roles/` | Chuyển vào thư mục sản phẩm |
| `ansible_test/playbooks/` | `ansible/products/elastic-stack/playbooks/` | Chuyển vào thư mục sản phẩm |
| `ansible_test/inventories/` | `ansible/products/elastic-stack/inventories/` | Chuyển vào thư mục sản phẩm |
| `automation_seed/` | `seed/` | Rút gọn tên |
| `vcsa_deploy/` | `vcsa_deploy/` | Giữ nguyên |
| _(mới)_ | `lib/` | Thư viện hàm shell dùng chung |
| _(mới)_ | `products/elastic-stack/` | Cấu hình điều phối sản phẩm |
| _(mới)_ | `docs/` | Tập trung tài liệu |

### 4.2. Tệp

| Tệp cũ | Tệp mới | Ghi chú |
| :--- | :--- | :--- |
| `run_all_onclick.sh` | `run.sh` | Viết lại, chỉ giữ menu chính + nạp lib |
| `packer_test/build_packer_secure.sh` | `packer/build.sh` | Tổng quát hóa, nhận tham số OS template |
| `terraform_test/run_provision_secure.sh` | `terraform/profiles/elastic-stack/run.sh` | Giữ logic, đổi đường dẫn |
| `ansible_test/run_ansible_secure.sh` | `ansible/products/elastic-stack/run_deploy.sh` | Giữ logic, đổi đường dẫn |
| `ansible_test/run_observability_setup.sh` | `ansible/products/elastic-stack/run_observability.sh` | Giữ logic, đổi đường dẫn |
| `ansible_test/run_backup_restore.sh` | `ansible/products/elastic-stack/run_backup.sh` | Giữ logic, đổi đường dẫn |
| `ansible_test/ansible.cfg` | `ansible/ansible.cfg` | Nâng lên cấp nền tảng |
| `vars.conf` (runtime) | `products/elastic-stack/product.conf` | Chuyên biệt cho sản phẩm |
| _(mới)_ | `lib/common.sh` | Tách từ `run_all_onclick.sh` |
| _(mới)_ | `lib/secrets.sh` | Tách từ `run_all_onclick.sh` |
| _(mới)_ | `lib/vsphere.sh` | Tách từ `run_all_onclick.sh` |
| _(mới)_ | `products/elastic-stack/menu.sh` | Tách menu Elastic từ `run_all_onclick.sh` |
| _(mới)_ | `products/elastic-stack/configure.sh` | Tách hàm `configure_templates()` |

---

## 5. Kế hoạch thực thi theo giai đoạn

### Giai đoạn 1: Tái cấu trúc thư mục và đổi tên (Structural Refactoring)

> Phạm vi: Di chuyển tệp, đổi tên thư mục, cập nhật đường dẫn tham chiếu.
> Nguyên tắc: Không thay đổi logic nghiệp vụ bên trong tệp. Chỉ sửa đường dẫn `source`, `cd`, `path` cho khớp vị trí mới.

**Các bước chi tiết:**

1. **Tạo khung thư mục mới**
   - Tạo: `lib/`, `packer/templates/ubuntu-24.04/`, `terraform/modules/`, `terraform/profiles/elastic-stack/`, `ansible/products/elastic-stack/`, `products/elastic-stack/`, `docs/`, `seed/`
   - Không xóa thư mục cũ cho đến khi kiểm tra xong toàn bộ đường dẫn.

2. **Di chuyển Terraform modules lên tầng nền tảng**
   - `terraform_test/modules/*` -> `terraform/modules/`
   - Cập nhật `source = "./modules/..."` trong `main.tf` thành `source = "../../modules/..."`.

3. **Di chuyển Terraform profile Elastic Stack**
   - `terraform_test/main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `terraform.tfvars.example`, `run_provision_secure.sh`, `templates/` -> `terraform/profiles/elastic-stack/`
   - Đổi tên `run_provision_secure.sh` -> `run.sh`.
   - Lưu ý quan trọng: Không di chuyển `terraform.tfstate` và `.terraform/` (chứa trạng thái hạ tầng thực). Xử lý trạng thái Terraform hiện tại xem Mục 6.

4. **Di chuyển Packer template**
   - `packer_test/ubuntu-24.04.pkr.hcl`, `variables.pkr.hcl`, `packer.pkrvars.hcl.example`, `scripts/`, `http/` -> `packer/templates/ubuntu-24.04/`
   - `packer_test/ansible/` -> `packer/ansible/`
   - `packer_test/build_packer_secure.sh` -> `packer/build.sh`

5. **Di chuyển Ansible vào cấu trúc sản phẩm**
   - `ansible_test/ansible.cfg` -> `ansible/ansible.cfg`
   - `ansible_test/requirements.yml` -> `ansible/requirements.yml`
   - `ansible_test/roles/` -> `ansible/products/elastic-stack/roles/`
   - `ansible_test/playbooks/` -> `ansible/products/elastic-stack/playbooks/`
   - `ansible_test/inventories/` -> `ansible/products/elastic-stack/inventories/`
   - Đổi tên wrapper scripts:
     - `run_ansible_secure.sh` -> `run_deploy.sh`
     - `run_observability_setup.sh` -> `run_observability.sh`
     - `run_backup_restore.sh` -> `run_backup.sh`
   - Cập nhật `ansible.cfg`: thay `inventory` và `roles_path` cho khớp cấu trúc mới.

6. **Di chuyển automation_seed**
   - `automation_seed/setup_automation_env.sh` -> `seed/setup_env.sh`
   - `automation_seed/download_iso.sh` -> `seed/download_iso.sh`
   - `automation_seed/upload_iso_to_vcenter.sh` -> `seed/upload_iso.sh`
   - `automation_seed/manage_vsphere_observability.sh` -> quyết định giữ tại `seed/` hoặc chuyển vào `ansible/products/elastic-stack/`.

7. **Di chuyển tài liệu**
   - `packer_test/packer_issues_and_solutions.md` -> `docs/`
   - `ke_hoach_va_checklist_trien_khai_he_thong.md` -> `docs/`
   - Các `README.md` rải rác -> hợp nhất hoặc di chuyển vào `docs/`.

8. **Cập nhật `.gitignore`**
   - Thay đổi các đường dẫn cho khớp cấu trúc mới.

9. **Cập nhật toàn bộ đường dẫn tham chiếu chéo**
   - Tìm kiếm toàn bộ chuỗi `packer_test`, `terraform_test`, `ansible_test`, `automation_seed` trong mã nguồn và thay thế.

---

### Giai đoạn 2: Tách kịch bản điều phối (Script Decomposition)

> Phạm vi: Phân rã `run_all_onclick.sh` (631 dòng) thành các module shell độc lập.

1. **Tạo `lib/common.sh`**: Tách các hàm tiện ích
   - `prompt_if_placeholder()`, `prompt_password()`
   - Hàm log có mã màu, hàm in banner, hàm kiểm tra lệnh tồn tại
   - Hàm khởi tạo tmux session

2. **Tạo `lib/secrets.sh`**: Tách logic thu thập mật khẩu
   - Hàm `gather_vcenter_credentials()`: Thu thập `VCENTER_PASS`
   - Hàm `gather_ssh_credentials()`: Thu thập `SSH_PASS`, `SUDO_PASS`
   - Hàm `export_govc_env()`: Export biến GOVC_*

3. **Tạo `lib/vsphere.sh`**: Tách logic tương tác vSphere
   - `run_iso_menu()`, `update_iso_in_packer()`, `upload_iso_to_datastore()`, `save_last_used_iso()`
   - Hàm kiểm tra template tồn tại trên vCenter

4. **Tạo `products/elastic-stack/menu.sh`**: Menu con sản phẩm
   - Di chuyển 6 tùy chọn menu hiện tại vào đây
   - Hàm `run_packer()`, `run_terraform()`, `run_ansible()`, `run_vsphere_observability()`, `run_vsphere_rollback()`
   - Hàm `gather_elastic_vars()`: Thu thập `IP_E01-03`, `IP_KBN`, `ELASTIC_PASS`, `KIBANA_PASS`

5. **Tạo `products/elastic-stack/configure.sh`**: Logic điền biến
   - Di chuyển hàm `configure_templates()` vào đây
   - Hàm `init_config_files()` chuyên cho Elastic

6. **Viết lại `run.sh`**: Kịch bản điều phối chính
   - Khoảng 80-100 dòng thay vì 631 dòng
   - Chỉ chứa: nạp thư viện, tmux guard, menu chính, vòng lặp chọn sản phẩm
   - Tự động phát hiện các sản phẩm đã đăng ký trong `products/`

---

### Giai đoạn 3: Tổng quát hóa Terraform và Packer (Generalization)

> Phạm vi: Tạo khả năng sử dụng lại Terraform modules và Packer templates cho nhiều sản phẩm.

1. **Tổng quát hóa `packer/build.sh`**
   - Nhận tham số dòng lệnh: `./build.sh --template ubuntu-24.04`
   - Tự động xác định thư mục `packer/templates/<os>/` và tệp HCL tương ứng
   - Menu chọn hệ điều hành nếu không truyền tham số

2. **Tổng quát hóa template sinh inventory Ansible**
   - Tạo template `hosts.yml.tpl` chung (không gắn cứng nhóm `elastic_cluster`)
   - Mỗi Terraform profile có thể tùy biến template riêng hoặc dùng template chung

3. **Tạo Terraform profile `generic-vms`**
   - Profile cho phép tạo bất kỳ tổ hợp VM/Network/Folder nào mà không gắn với sản phẩm cụ thể
   - Phục vụ mục đích "Cấp phát hạ tầng tùy chỉnh" trong menu chính

---

### Giai đoạn 4: Bổ sung sản phẩm mới (Product Expansion)

> Phạm vi: Tạo khung cho Zabbix, HAProxy, Infra Services.

Mỗi sản phẩm mới cần 3 thành phần:

1. `products/<name>/` -- Biến, menu, logic điều phối
2. `terraform/profiles/<name>/` -- Hạ tầng (hoặc tái sử dụng `generic-vms`)
3. `ansible/products/<name>/` -- Playbook và roles cấu hình

---

## 6. Xử lý trạng thái Terraform hiện tại (Terraform State Migration)

Tệp `terraform.tfstate` đang quản lý trạng thái 4 máy ảo thực trên vCenter. Di chuyển sai sẽ khiến Terraform mất nhận diện tài nguyên và có thể xóa hoặc tạo lại máy ảo khi chạy `terraform apply`.

### Phương án A: Di chuyển terraform.tfstate cùng profile (khuyến nghị)

1. Di chuyển toàn bộ thư mục `.terraform/` và `terraform.tfstate*` sang `terraform/profiles/elastic-stack/`.
2. Cập nhật `source = "../../modules/..."` trong `main.tf`.
3. Chạy `terraform init` trong thư mục mới.
4. Chạy `terraform plan` để xác nhận kế hoạch hiển thị `No changes. Infrastructure is up-to-date`.
5. Nếu `plan` hiển thị thay đổi không mong muốn, chạy `terraform state mv` để sửa đường dẫn module.

### Phương án B: Dừng quản lý trạng thái cũ (nếu đây chỉ là môi trường lab)

1. Sao lưu `terraform.tfstate` hiện tại.
2. Tạo cấu hình Terraform mới tại `terraform/profiles/elastic-stack/` với `main.tf` đã cập nhật đường dẫn module.
3. Sử dụng `terraform import` để nhập lại từng tài nguyên hiện có vào trạng thái mới.

---

## 7. Quy trình kiểm tra sau tái cấu trúc (Verification Plan)

### 7.1. Kiểm tra cấu trúc thư mục

```bash
# Xác nhận không còn thư mục cũ
test ! -d packer_test && test ! -d terraform_test && test ! -d ansible_test && echo "OK"

# Xác nhận cấu trúc mới đầy đủ
ls lib/common.sh lib/secrets.sh lib/vsphere.sh
ls packer/build.sh packer/templates/ubuntu-24.04/ubuntu-24.04.pkr.hcl
ls terraform/modules/compute/main.tf
ls terraform/profiles/elastic-stack/main.tf
ls ansible/products/elastic-stack/playbooks/deploy_cluster.yml
ls products/elastic-stack/menu.sh
```

### 7.2. Kiểm tra Terraform

```bash
cd terraform/profiles/elastic-stack/
terraform init
terraform plan    # Kết quả mong đợi: "No changes"
```

### 7.3. Kiểm tra Packer

```bash
cd packer/templates/ubuntu-24.04/
packer validate -var-file=packer.pkrvars.hcl .
```

### 7.4. Kiểm tra Ansible

```bash
cd ansible/
ANSIBLE_CONFIG=ansible.cfg ansible-inventory --list \
  -i products/elastic-stack/inventories/lab/hosts.yml
```

### 7.5. Kiểm tra điều phối tổng thể

```bash
./run.sh    # Menu chính hiển thị đúng, không lỗi syntax
```

---

## 8. Tóm tắt ưu tiên thực thi

| Giai đoạn | Nội dung | Độ ưu tiên | Rủi ro |
| :--- | :--- | :--- | :--- |
| 1 | Tái cấu trúc thư mục, đổi tên, cập nhật đường dẫn | Cao -- Làm ngay | Trung bình (Terraform state) |
| 2 | Tách kịch bản điều phối thành thư viện | Cao -- Làm ngay sau GD 1 | Thấp |
| 3 | Tổng quát hóa Packer/Terraform | Trung bình -- Làm khi cần sản phẩm mới | Thấp |
| 4 | Bổ sung Zabbix, HAProxy, Infra Services | Thấp -- Phát triển theo nhu cầu | Không có |
