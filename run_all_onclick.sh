#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator Script for One-Click Deployment (Version 2)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# 1. Mở tmux session nếu chưa ở trong tmux
if [[ -z "${TMUX:-}" ]]; then
    echo "Đang kiểm tra môi trường tmux..."
    if command -v tmux &> /dev/null; then
        echo "Khởi tạo phiên tmux (deploy_session) để chống đứt kết nối SSH..."
        exec tmux new-session -s deploy_session "bash \"$0\" \"$@\" 2>&1 | tee \"${LOG_FILE}\""
    else
        echo "CẢNH BÁO: tmux chưa được cài đặt. Tiến trình vẫn tiếp tục nhưng nếu đứt SSH sẽ bị gián đoạn."
        exec > >(tee -a "${LOG_FILE}") 2>&1
    fi
else
    exec > >(tee -a "${LOG_FILE}") 2>&1
fi

echo "=============================================================================="
echo "HỆ THỐNG ĐIỀU PHỐI TỰ ĐỘNG - ONE CLICK DEPLOYMENT"
echo "Log file: ${LOG_FILE}"
echo "=============================================================================="

# 2. Khởi tạo tệp cấu hình từ mẫu (.example) nếu chưa có
echo ""
echo "--- KIỂM TRA VÀ KHỞI TẠO TỆP CẤU HÌNH ---"

if [[ ! -f "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl" ]]; then
    cp "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl.example" "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
    echo "Đã tạo: packer_test/packer.pkrvars.hcl"
fi

if [[ ! -f "${SCRIPT_DIR}/terraform_test/terraform.tfvars" ]]; then
    cp "${SCRIPT_DIR}/terraform_test/terraform.tfvars.example" "${SCRIPT_DIR}/terraform_test/terraform.tfvars"
    echo "Đã tạo: terraform_test/terraform.tfvars"
fi

if [[ ! -f "${SCRIPT_DIR}/ansible_test/inventories/lab/hosts.yml" ]]; then
    cp "${SCRIPT_DIR}/ansible_test/inventories/lab/hosts.yml.example" "${SCRIPT_DIR}/ansible_test/inventories/lab/hosts.yml"
    echo "Đã tạo: ansible_test/inventories/lab/hosts.yml"
fi

# 3. Thu thập thông tin động để tự cấu hình
echo ""
echo "--- CẤU HÌNH HẠ TẦNG CƠ BẢN ---"
read -p "Nhập IP hoặc FQDN của vCenter (ví dụ: 10.0.6.30): " SITE_VCSA_IP
if [[ -z "${SITE_VCSA_IP}" ]]; then
    echo "Lỗi: IP vCenter không được để trống." >&2
    exit 1
fi

read -p "Nhập tên Datastore để lưu ISO cài đặt (ví dụ: DS_100_3): " ISO_DATASTORE
if [[ -z "${ISO_DATASTORE}" ]]; then
    echo "Lỗi: Datastore không được để trống." >&2
    exit 1
fi

echo "Đang cập nhật địa chỉ vCenter và Datastore vào tệp cấu hình..."
sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
sed -i -E "s/(vsphere_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${SCRIPT_DIR}/terraform_test/terraform.tfvars"
sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"

# Dùng sed thay thế toàn bộ block iso_paths đa dòng
sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "['"${ISO_DATASTORE}"'] iso/ubuntu-24.04.1-live-server-amd64.iso"\
]' "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
echo "Đã cập nhật xong."

# 4. Tạm dừng để người dùng sửa các tham số chi tiết khác
echo ""
echo "=============================================================================="
echo "CẢNH BÁO TRƯỚC KHI CHẠY (PRE-FLIGHT WARNING)"
echo "=============================================================================="
echo "Hệ thống đã tự động điền: vcenter_server, vcenter_datastore, iso_paths."
echo "Bạn CẦN MỞ TERMINAL KHÁC (hoặc dùng nano/vim) để chỉnh sửa các biến còn lại."
echo ""
echo "--- [1/3] packer_test/packer.pkrvars.hcl ---"
echo "  vcenter_user          : Tài khoản vCenter (mặc định: administrator@vsphere.local)"
echo "  vcenter_datacenter    : Tên Datacenter trên vCenter"
echo "  vcenter_cluster       : Tên Compute Cluster chứa ESXi Host"
echo "  vcenter_network       : Tên Port Group có DHCP (dùng khi build template)"
echo "  vcenter_folder        : Thư mục lưu template trên vCenter (ví dụ: VM Template)"
echo "  vm_name               : Tên template sẽ tạo (ví dụ: tpl-ubuntu-2404-golden)"
echo "  vm_cpu_cores          : Số CPU core cho template VM"
echo "  vm_mem_size           : RAM cho template VM (đơn vị MB)"
echo "  vm_disk_size          : Dung lượng ổ đĩa cho template VM (đơn vị MB)"
echo "  ssh_username          : Tài khoản SSH tạo trên template (mặc định: svc_admin)"
echo ""
echo "--- [2/3] terraform_test/terraform.tfvars ---"
echo "  vsphere_user              : Tài khoản vCenter"
echo "  vsphere_datacenter        : Tên Datacenter"
echo "  vsphere_cluster           : Tên Cluster"
echo "  vsphere_datastore         : Tên Datastore lưu VM"
echo "  content_library_name      : Tên Content Library (nếu dùng)"
echo "  content_library_item_name : Tên item trong Content Library"
echo "  vm_folders                : Danh sách thư mục VM cần tạo"
echo "  vm_target_folder          : Thư mục đích đặt VM"
echo "  esxi_hosts                : Danh sách IP các ESXi Host"
echo "  virtual_switch_name       : Tên vSwitch trên ESXi (ví dụ: vSwitch0)"
echo "  port_groups               : Tên Port Group và VLAN ID cần tạo"
echo "  default_domain_name       : Tên miền nội bộ (ví dụ: bvnttwhcm.int)"
echo "  default_dns_servers       : Danh sách DNS Server"
echo "  vms -> name               : Tên hiển thị của từng VM (ví dụ: srv-elastic-01)"
echo "  vms -> hostname           : Hostname gán cho từng VM"
echo "  vms -> cpu_count          : Số CPU cho từng VM"
echo "  vms -> memory_mb          : RAM cho từng VM (đơn vị MB)"
echo "  vms -> disk_size_gb       : Dung lượng ổ đĩa cho từng VM (đơn vị GB)"
echo "  vms -> network_name       : Port Group gán cho từng VM"
echo "  vms -> ip_address         : Địa chỉ IP tĩnh của từng VM"
echo "  vms -> netmask            : Subnet mask (ví dụ: 24)"
echo "  vms -> gateway            : Default gateway"
echo ""
echo "--- [3/3] ansible_test/inventories/lab/hosts.yml ---"
echo "  ansible_user                   : Tài khoản SSH (phải trùng ssh_username ở Packer)"
echo "  elastic_cluster -> ansible_host: IP tĩnh của srv-elastic-01, 02, 03 (trùng vms -> ip_address)"
echo "  kibana_gateway  -> ansible_host: IP tĩnh của srv-kibana-gw (trùng vms -> ip_address)"
echo ""
echo "LƯU Ý: Các biến vcenter_server, vsphere_server, vcenter_datastore, iso_paths,"
echo "        vsphere_template_name ĐÃ ĐƯỢC TỰ ĐỘNG CẬP NHẬT. KHÔNG cần sửa thủ công."
echo "=============================================================================="
read -p "Sau khi bạn ĐÃ CẤU HÌNH XONG 3 tệp trên, hãy nhấn Enter để tiếp tục..." IGNORE_VAR

# 5. Thu thập Mật khẩu (1 LẦN DUY NHẤT)
echo ""
echo "--- THÔNG TIN BẢO MẬT (PASSWORD PROMPTS) ---"
if [[ -n "${VCENTER_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu quản trị vCenter [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export VCENTER_PASS="${INPUT_PASS}"
else
    while [[ -z "${VCENTER_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu quản trị vCenter: " VCENTER_PASS
        echo ""
        [[ -z "${VCENTER_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export VCENTER_PASS
fi

if [[ -n "${SSH_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu SSH khởi tạo (svc_admin) [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export SSH_PASS="${INPUT_PASS}"
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu SSH khởi tạo (svc_admin): " SSH_PASS
        echo ""
        [[ -z "${SSH_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export SSH_PASS
fi

if [[ -n "${SUDO_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu sudo (sudo/become) [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export SUDO_PASS="${INPUT_PASS}"
else
    while [[ -z "${SUDO_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu sudo (sudo/become): " SUDO_PASS
        echo ""
        [[ -z "${SUDO_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export SUDO_PASS
fi

if [[ -n "${ELASTIC_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu siêu quản trị Elastic [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export ELASTIC_PASS="${INPUT_PASS}"
else
    while [[ -z "${ELASTIC_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu siêu quản trị Elastic: " ELASTIC_PASS
        echo ""
        [[ -z "${ELASTIC_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export ELASTIC_PASS
fi

if [[ -n "${KIBANA_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu hệ thống Kibana [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export KIBANA_PASS="${INPUT_PASS}"
else
    while [[ -z "${KIBANA_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu hệ thống Kibana: " KIBANA_PASS
        echo ""
        [[ -z "${KIBANA_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export KIBANA_PASS
fi

# Map VCENTER_PASS sang VSPHERE_PASSWORD cho Terraform
export VSPHERE_PASSWORD="${VCENTER_PASS}"

# 6. Xử lý ISO tự động (Download & Upload)
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 0/4: XỬ LÝ ISO CÀI ĐẶT UBUNTU"
echo "=============================================================================="
cd "${SCRIPT_DIR}/automation_seed"

echo "-> Tải ISO cục bộ (bỏ qua nếu đã tải)..."
./download_iso.sh --ubuntu

ISO_FILE="./iso_cache/ubuntu-24.04.1-live-server-amd64.iso"
if [[ ! -f "${ISO_FILE}" ]]; then
    echo "Lỗi: Tải ISO thất bại." >&2
    exit 1
fi

echo "-> Kiểm tra ISO trên vCenter Datastore [${ISO_DATASTORE}]..."
export GOVC_URL="https://${SITE_VCSA_IP}"
# Cố gắng lấy user vcenter từ packer config, nếu không dùng mặc định
VCENTER_USER=$(grep -E '^\s*vcenter_user\s*=' "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl" | head -n 1 | cut -d'"' -f2 || echo "administrator@vsphere.local")
export GOVC_USERNAME="${VCENTER_USER}"
export GOVC_PASSWORD="${VCENTER_PASS}"
export GOVC_INSECURE="1"

if command -v govc &> /dev/null; then
    if govc datastore.ls -ds="${ISO_DATASTORE}" iso/ubuntu-24.04.1-live-server-amd64.iso &> /dev/null; then
        echo "ISO đã tồn tại trên Datastore [${ISO_DATASTORE}], bỏ qua việc upload."
    else
        echo "ISO chưa tồn tại trên Datastore, tiến hành upload qua govc..."
        govc datastore.mkdir -ds="${ISO_DATASTORE}" iso || true
        govc datastore.upload -ds="${ISO_DATASTORE}" "${ISO_FILE}" iso/ubuntu-24.04.1-live-server-amd64.iso
        echo "Upload thành công."
    fi
else
    echo "CẢNH BÁO: Không tìm thấy công cụ govc. Bỏ qua kiểm tra/tải lên ISO tự động."
    echo "Vui lòng tự đảm bảo ISO đã có trên Datastore trước khi Packer chạy."
fi

# 7. Thực thi Packer
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 1/4: ĐÓNG GÓI PACKER TEMPLATE"
echo "=============================================================================="
cd "${SCRIPT_DIR}/packer_test"
./build_packer_secure.sh

# 8. Đồng bộ tên Template từ Packer sang Terraform
echo ""
echo "=============================================================================="
echo "ĐỒNG BỘ CẤU HÌNH: PACKER -> TERRAFORM"
echo "=============================================================================="
TEMPLATE_NAME=$(grep -E '^\s*vm_name\s*=' "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl" | head -n 1 | cut -d'"' -f2)
if [[ -n "${TEMPLATE_NAME}" ]]; then
    echo "Phát hiện tên template từ Packer: ${TEMPLATE_NAME}"
    sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TEMPLATE_NAME}\2/" "${SCRIPT_DIR}/terraform_test/terraform.tfvars"
    echo "Đã đồng bộ tên template sang Terraform thành công."
else
    echo "Cảnh báo: Không tìm thấy vm_name trong cấu hình Packer để đồng bộ sang Terraform."
fi

# 9. Thực thi Terraform
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 2/4: KHỞI TẠO HẠ TẦNG VSPHERE (TERRAFORM)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/terraform_test"
./run_provision_secure.sh

# 10. Thực thi Ansible Deploy
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 3/4: CẤU HÌNH ELASTIC STACK (ANSIBLE)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/ansible_test"
./run_ansible_secure.sh

# 11. Thực thi Ansible Observability
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 4/4: KÍCH HOẠT QUAN SÁT TẬP TRUNG (OBSERVABILITY)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/ansible_test"
./run_observability_setup.sh

echo ""
echo "=============================================================================="
echo "HOÀN TẤT QUÁ TRÌNH TRIỂN KHAI ONE-CLICK TỰ ĐỘNG."
echo "=============================================================================="
