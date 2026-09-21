# Trạm điều khiển tự động hóa và quản lý ISO (Seed Appliance)

Thư mục này chứa các kịch bản nền tảng khởi tạo môi trường công cụ tự động hóa và quản lý tệp ISO trên hạ tầng VMware vSphere.

## 1. Danh mục kịch bản

| Kịch bản | Mô tả chức năng |
| :--- | :--- |
| [`setup_env.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/setup_env.sh) | Cài đặt toàn bộ bộ công cụ IaC: Packer, Terraform, Ansible, govc, pyVmomi trên Ubuntu. |
| [`download_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/download_iso.sh) | Tự động tải tệp ISO Ubuntu Server / VCSA kèm kiểm tra mã băm SHA256. |
| [`upload_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/upload_iso.sh) | Đẩy tệp ISO lên Datastore của ESXi hoặc import vào VMware Content Library. |

## 2. Tài liệu kỹ thuật chi tiết

Quy trình vận hành, tham số dòng lệnh và hướng dẫn từng bước được trình bày chi tiết tại:
- [docs/00_seed_and_iso_management_guide.md](file:///d:/neit_ng/prjs_i/auto_provision_configuration/docs/00_seed_and_iso_management_guide.md)
