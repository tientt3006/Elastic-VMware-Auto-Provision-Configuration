# Module tự động hóa cài đặt VMware vCenter Server Appliance (VCSA)

Thư mục này chứa toàn bộ mã nguồn, tệp đặc tả cấu hình và sổ tay hướng dẫn quy trình cài đặt tự động vCenter Server Appliance (VCSA) trên máy chủ VMware ESXi Host thông qua công cụ dòng lệnh chính thức `vcsa-deploy`.

## 1. Danh mục tài nguyên trong thư mục

| Tệp tin | Chức năng kỹ thuật |
| :--- | :--- |
| [`deploy_vcsa_unattended.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/deploy_vcsa_unattended.sh) | Kịch bản điều phối tự động: mount ISO VCSA, nhận mật khẩu qua RAM, chạy pre-check và thực thi cài đặt không giám sát. |
| [`templates/embedded_vcs_on_esxi.json.tpl`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/templates/embedded_vcs_on_esxi.json.tpl) | Bản mẫu đặc tả cấu hình JSON chuẩn VMware cho mô hình Embedded VCSA trên standalone ESXi. |
| [`vcsa_vars.env.example`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/vcsa_vars.env.example) | Tệp mẫu khai báo biến hạ tầng không nhạy cảm (IP, FQDN, Datastore, Gateway, DNS). |
| [`01_vcsa_unattended_deployment_runbook.md`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/vcsa_deploy/01_vcsa_unattended_deployment_runbook.md) | Sổ tay quy trình kỹ thuật toàn diện: nguyên lý, checklist hạ tầng, thao tác CLI, giải thích output và troubleshooting. |

---

## 2. Quy trình khởi chạy nhanh (Quick Start)

### Bước 1: Chuẩn bị tệp cấu hình biến
```bash
cd vcsa_deploy
cp vcsa_vars.env.example vcsa_vars.env
```
Chỉnh sửa các thông số: `ESXI_HOSTNAME`, `DATASTORE_NAME`, `VCSA_STATIC_IP`, `VCSA_FQDN`, và đường dẫn `VCSA_ISO_PATH`.

### Bước 2: Kích hoạt cài đặt tự động
Thực thi kịch bản với quyền root:
```bash
sudo ./deploy_vcsa_unattended.sh
```

### Bước 3: Nhập mật khẩu ẩn theo yêu cầu trên màn hình
- Mật khẩu root của ESXi Host đích.
- Mật khẩu root của hệ điều hành VCSA.
- Mật khẩu quản trị Single Sign-On (`<VCENTER_USER>`).

Kịch bản tự động thực thi pre-check, yêu cầu xác nhận `yes`, tiến hành cài đặt và tự động xóa sạch mật khẩu khỏi RAM khi hoàn tất.
