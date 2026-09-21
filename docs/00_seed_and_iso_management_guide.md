# Hướng dẫn vận hành trạm điều khiển Automation Seed và quản lý ISO

Tài liệu này quy định và hướng dẫn chi tiết quy trình thiết lập môi trường công cụ tự động hóa trên máy chủ trạm điều khiển (Automation Seed Appliance) và các thao tác quản lý tệp ISO trên hạ tầng lưu trữ VMware vSphere.

---

## 1. Danh mục công cụ và kịch bản trong thư mục `seed/`

Thư mục `seed/` cung cấp các kịch bản nền tảng phục vụ chuẩn bị môi trường trước khi khởi chạy các công cụ IaC:

| Kịch bản | Chức năng kỹ thuật | Quyền thực thi |
| :--- | :--- | :--- |
| [`seed/setup_env.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/setup_env.sh) | Cài đặt toàn bộ bộ công cụ IaC: HashiCorp Packer, Terraform, Ansible, govc, pyVmomi, git trên hệ điều hành Ubuntu. | `sudo` |
| [`seed/download_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/download_iso.sh) | Tự động tải tệp ISO cài đặt hệ điều hành (Ubuntu Server, VCSA), xác thực mã băm SHA256 và hỗ trợ tiếp tục tải khi đứt đoạn (`curl -C -`). | User |
| [`seed/upload_iso.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/seed/upload_iso.sh) | Đẩy tệp ISO từ trạm điều khiển lên Datastore của ESXi hoặc import vào VMware Content Library qua `govc`. | User |

---

## 2. Quy trình vận hành chi tiết

### Bước 1: Khởi tạo môi trường công cụ IaC trên máy trạm điều khiển

Thực thi kịch bản cài đặt với đặc quyền quản trị:

```bash
cd seed
sudo ./setup_env.sh
```

Tiến trình tự động thực hiện các thao tác:
1. Cập nhật chỉ mục gói và cài đặt các gói hệ thống phụ trợ (`curl`, `gnupg`, `software-properties-common`, `jq`, `xorriso`, `git`).
2. Đăng ký khóa GPG và kho lưu trữ APT chính thức của HashiCorp, cài đặt `terraform` và `packer`.
3. Thiết lập môi trường ảo Python chuyên dụng tại `~/.venvs/ansible-env`, cài đặt `ansible`, `pyvmomi`.
4. Tải và cài đặt binary `govc` phiên bản mới nhất vào `/usr/local/bin/govc`.
5. Kiểm tra và xác nhận phiên bản hoạt động của toàn bộ công cụ.

---

### Bước 2: Tải tệp ISO cài đặt hệ điều hành

Tải bản phân phối chuẩn Ubuntu 24.04 LTS Live Server:

```bash
./download_iso.sh --ubuntu
```

Hoặc tải tệp ISO tùy chỉnh từ URL nội bộ kèm kiểm tra tính toàn vẹn:

```bash
./download_iso.sh --custom "http://mirror.internal/isos/custom.iso" "sha256_checksum_value"
```

Mặc định tệp ISO được lưu trữ trong thư mục đệm cục bộ `./iso_cache/`.

---

### Bước 3: Đẩy tệp ISO lên hạ tầng vSphere

#### Tùy chọn A: Đẩy lên Datastore của ESXi Host (giai đoạn ban đầu trước khi có vCenter)

```bash
./upload_iso.sh \
  -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso \
  -H <ESXI_HOST_IP> \
  -u root \
  -d datastore1 \
  -p iso
```

#### Tùy chọn B: Import vào Content Library trên vCenter Server

```bash
./upload_iso.sh \
  -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso \
  -H vcsa.lab.internal \
  -u <VCENTER_USER> \
  -l "Content-Library-Lab"
```

---

## 3. Điều phối qua giao diện trung tâm (`run.sh`)

Tất cả các chức năng quản lý ISO và cài đặt Seed đều có thể truy cập trực tiếp thông qua menu Công cụ nền tảng trong [`run.sh`](file:///d:/neit_ng/prjs_i/auto_provision_configuration/run.sh):

```text
==============================================================================
CÔNG CỤ NỀN TẢNG (PLATFORM TOOLS)
==============================================================================
1) Tạo Golden Template (Packer)
2) Cấp phát hạ tầng (Terraform Profile)
3) Quản lý tệp ISO trên Datastore
4) Cài đặt môi trường công cụ tự động hóa (Seed Setup)
0) Quay lại menu chính
```
