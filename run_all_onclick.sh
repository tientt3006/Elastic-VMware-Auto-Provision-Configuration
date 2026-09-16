#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator Script for One-Click Deployment (Version 3)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
PKR_FILE="${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
TF_FILE="${SCRIPT_DIR}/terraform_test/terraform.tfvars"
ANS_FILE="${SCRIPT_DIR}/ansible_test/inventories/lab/hosts.yml"

# Cấp quyền thực thi cho toàn bộ script con
chmod +x "${SCRIPT_DIR}/packer_test/build_packer_secure.sh" \
         "${SCRIPT_DIR}/terraform_test/run_provision_secure.sh" \
         "${SCRIPT_DIR}/ansible_test/run_ansible_secure.sh" \
         "${SCRIPT_DIR}/ansible_test/run_observability_setup.sh" \
         "${SCRIPT_DIR}/automation_seed/download_iso.sh" \
         "${SCRIPT_DIR}/automation_seed/upload_iso_to_vcenter.sh" \
         "${SCRIPT_DIR}/automation_seed/setup_automation_env.sh"

# ==============================================================================
# 0. Mở tmux session nếu chưa ở trong tmux
# ==============================================================================
if [[ -z "${TMUX:-}" ]]; then
    if command -v tmux &> /dev/null; then
        echo "Khởi tạo phiên tmux (deploy_session) để chống đứt kết nối SSH..."
        # Giữ terminal mở sau khi script kết thúc (dù thành công hay lỗi) để đọc log
        exec tmux new-session -s deploy_session \
            "bash \"$0\" \"$@\" 2>&1 | tee \"${LOG_FILE}\"; echo ''; echo '=== Script kết thúc với exit code: '\$?' ==='; echo 'Nhấn Enter để đóng tmux session...'; read"
    else
        echo "CẢNH BÁO: tmux chưa được cài đặt. Nếu đứt SSH sẽ bị gián đoạn."
        exec > >(tee -a "${LOG_FILE}") 2>&1
    fi
else
    exec > >(tee -a "${LOG_FILE}") 2>&1
fi

echo "=============================================================================="
echo "HỆ THỐNG ĐIỀU PHỐI TỰ ĐỘNG - ONE CLICK DEPLOYMENT (v3)"
echo "Log file: ${LOG_FILE}"
echo "=============================================================================="

# ==============================================================================
# 1. Khởi tạo tệp cấu hình từ mẫu (.example) nếu chưa có
# ==============================================================================
echo ""
echo "--- KIỂM TRA VÀ KHỞI TẠO TỆP CẤU HÌNH ---"

if [[ ! -f "${PKR_FILE}" ]]; then
    cp "${PKR_FILE}.example" "${PKR_FILE}"
    echo "Đã tạo: packer_test/packer.pkrvars.hcl"
fi

if [[ ! -f "${TF_FILE}" ]]; then
    cp "${TF_FILE}.example" "${TF_FILE}"
    echo "Đã tạo: terraform_test/terraform.tfvars"
fi

if [[ ! -f "${ANS_FILE}" ]]; then
    cp "${ANS_FILE}.example" "${ANS_FILE}"
    echo "Đã tạo: ansible_test/inventories/lab/hosts.yml"
fi

# ==============================================================================
# 2. Thu thập thông tin dùng chung và tự động điền vào cả 3 tệp cấu hình
# ==============================================================================
echo ""
echo "=============================================================================="
echo "CẤU HÌNH HẠ TẦNG DÙNG CHUNG (TỰ ĐỘNG ĐIỀN VÀO CẢ 3 TỆP)"
echo "=============================================================================="

# --- vCenter Server ---
read -p "IP hoặc FQDN của vCenter (ví dụ: 10.0.6.30 hoặc vcsa.bvnttwhcm.int): " SITE_VCSA_IP
[[ -z "${SITE_VCSA_IP}" ]] && echo "Lỗi: Không được để trống." >&2 && exit 1
sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${TF_FILE}"

# --- vCenter User ---
read -p "Tài khoản vCenter [Enter = administrator@vsphere.local]: " VCENTER_USER
VCENTER_USER="${VCENTER_USER:-administrator@vsphere.local}"
sed -i -E "s/(vcenter_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${TF_FILE}"

# --- Datacenter ---
read -p "Tên Datacenter trên vCenter [Enter = Datacenter]: " VCENTER_DC
VCENTER_DC="${VCENTER_DC:-Datacenter}"
sed -i -E "s/(vcenter_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${TF_FILE}"

# --- Cluster ---
read -p "Tên Compute Cluster [Enter = Cluster1]: " VCENTER_CLUSTER
VCENTER_CLUSTER="${VCENTER_CLUSTER:-Cluster1}"
sed -i -E "s/(vcenter_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${TF_FILE}"

# --- Datastore ---
read -p "Tên Datastore lưu ISO và VM (ví dụ: DS-LD01-SSD): " ISO_DATASTORE
[[ -z "${ISO_DATASTORE}" ]] && echo "Lỗi: Không được để trống." >&2 && exit 1
sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${TF_FILE}"
# Cập nhật iso_paths
sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "['"${ISO_DATASTORE}"'] iso/ubuntu-24.04.1-live-server-amd64.iso"\
]' "${PKR_FILE}"

# --- VM Network cho Packer (Port Group có DHCP) ---
read -p "Tên Port Group có DHCP cho Packer build template [Enter = VM Network]: " PKR_NETWORK
PKR_NETWORK="${PKR_NETWORK:-VM Network}"
sed -i -E "s/(vcenter_network\s*=\s*\")[^\"]+(\")/\1${PKR_NETWORK}\2/" "${PKR_FILE}"

# --- Folder ---
read -p "Thư mục VM trên vCenter (ví dụ: App_Workloads) [Enter = App_Workloads]: " VM_FOLDER
VM_FOLDER="${VM_FOLDER:-App_Workloads}"
sed -i -E "s/(vcenter_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${PKR_FILE}"
sed -i -E "s/(vm_target_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${TF_FILE}"

# --- Template Name ---
read -p "Tên VM Template Packer sẽ tạo [Enter = tpl-ubuntu-2404-golden]: " TPL_NAME
TPL_NAME="${TPL_NAME:-tpl-ubuntu-2404-golden}"
sed -i -E "s/(vm_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${PKR_FILE}"
sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"
sed -i -E "s/(content_library_item_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"

# --- SSH Username ---
read -p "Tài khoản SSH trên VM (dùng cho Packer + Ansible) [Enter = svc_admin]: " SSH_USER
SSH_USER="${SSH_USER:-svc_admin}"
sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${PKR_FILE}"
sed -i -E "s/(ansible_user:\s*).*/\1${SSH_USER}/" "${ANS_FILE}"

# --- IP tĩnh 4 VM (điền vào cả Terraform và Ansible) ---
echo ""
echo "--- ĐỊA CHỈ IP TĨNH CHO 4 MÁY ẢO ---"
read -p "IP tĩnh srv-elastic-01 [Enter = 10.0.6.101]: " IP_E01
IP_E01="${IP_E01:-10.0.6.101}"
read -p "IP tĩnh srv-elastic-02 [Enter = 10.0.6.102]: " IP_E02
IP_E02="${IP_E02:-10.0.6.102}"
read -p "IP tĩnh srv-elastic-03 [Enter = 10.0.6.103]: " IP_E03
IP_E03="${IP_E03:-10.0.6.103}"
read -p "IP tĩnh srv-kibana-gw  [Enter = 10.0.6.104]: " IP_KBN
IP_KBN="${IP_KBN:-10.0.6.104}"
read -p "Default Gateway        [Enter = 10.0.6.1]: " GW
GW="${GW:-10.0.6.1}"
read -p "Subnet Mask (CIDR)     [Enter = 24]: " NETMASK
NETMASK="${NETMASK:-24}"

# Điền IP vào Terraform (sed từng block elastic_01 -> elastic_03, kibana_gw)
# Sử dụng cơ chế tìm block theo key rồi thay ip_address và gateway trong block đó
python3 - "${TF_FILE}" "${IP_E01}" "${IP_E02}" "${IP_E03}" "${IP_KBN}" "${GW}" "${NETMASK}" << 'PYEOF'
import sys, re
tf_file = sys.argv[1]
ips = {"elastic_01": sys.argv[2], "elastic_02": sys.argv[3], "elastic_03": sys.argv[4], "kibana_gw": sys.argv[5]}
gw = sys.argv[6]
netmask = sys.argv[7]

with open(tf_file, 'r') as f:
    content = f.read()

for key, ip in ips.items():
    # Match the block for this key and replace ip_address, gateway, netmask inside it
    pattern = r'("' + key + r'"\s*=\s*\{)(.*?)(\n\s*\})'
    def replacer(m):
        block = m.group(2)
        block = re.sub(r'(ip_address\s*=\s*")[^"]+(")', r'\g<1>' + ip + r'\2', block)
        block = re.sub(r'(gateway\s*=\s*")[^"]+(")', r'\g<1>' + gw + r'\2', block)
        block = re.sub(r'(netmask\s*=\s*)\d+', r'\g<1>' + netmask, block)
        return m.group(1) + block + m.group(3)
    content = re.sub(pattern, replacer, content, flags=re.DOTALL)

with open(tf_file, 'w') as f:
    f.write(content)
PYEOF

# Điền IP vào Ansible hosts.yml
sed -i -E "/srv-elastic-01/{n;s/(ansible_host:\s*).*/\1${IP_E01}/}" "${ANS_FILE}"
sed -i -E "/srv-elastic-02/{n;s/(ansible_host:\s*).*/\1${IP_E02}/}" "${ANS_FILE}"
sed -i -E "/srv-elastic-03/{n;s/(ansible_host:\s*).*/\1${IP_E03}/}" "${ANS_FILE}"
sed -i -E "/srv-kibana-gw/{n;s/(ansible_host:\s*).*/\1${IP_KBN}/}" "${ANS_FILE}"

echo ""
echo "Đã tự động điền tất cả thông tin dùng chung vào 3 tệp cấu hình."

# ==============================================================================
# 3. Cảnh báo các biến còn lại cần sửa thủ công (không lặp lại)
# ==============================================================================
echo ""
echo "=============================================================================="
echo "CẢNH BÁO: CÁC BIẾN CÒN LẠI CẦN KIỂM TRA THỦ CÔNG"
echo "=============================================================================="
echo "Hệ thống ĐÃ TỰ ĐỘNG ĐIỀN các biến dùng chung (vcenter_server, user,"
echo "datacenter, cluster, datastore, iso_paths, folder, template_name,"
echo "ssh_username, ansible_user, IP tĩnh 4 VM, gateway, netmask)."
echo ""
echo "Nếu cần, MỞ TERMINAL KHÁC để kiểm tra hoặc sửa các biến RIÊNG sau:"
echo ""
echo "--- packer_test/packer.pkrvars.hcl ---"
echo "  vm_cpu_cores   : Số CPU core cho template VM (mặc định: 2)"
echo "  vm_mem_size    : RAM cho template VM, đơn vị MB (mặc định: 4096)"
echo "  vm_disk_size   : Dung lượng ổ đĩa template, đơn vị MB (mặc định: 40960)"
echo "  ssh_timeout    : Thời gian chờ SSH kết nối, đơn vị phút (mặc định: 30m)"
echo ""
echo "--- terraform_test/terraform.tfvars ---"
echo "  content_library_name  : Tên Content Library trên vCenter"
echo "  vm_folders            : Danh sách thư mục VM cần tạo trước"
echo "  esxi_hosts            : Danh sách IP các ESXi Host vật lý"
echo "  virtual_switch_name   : Tên vSwitch trên ESXi (mặc định: vSwitch0)"
echo "  port_groups           : Port Group và VLAN ID cần tạo trên ESXi"
echo "  default_domain_name   : Tên miền nội bộ (ví dụ: bvnttwhcm.int)"
echo "  default_dns_servers   : Danh sách DNS Server"
echo "  drs_rule_mandatory    : Quy tắc DRS (false = Soft, true = Hard)"
echo "  vms -> cpu_count      : Số CPU cho từng VM"
echo "  vms -> memory_mb      : RAM cho từng VM, đơn vị MB"
echo "  vms -> disk_size_gb   : Dung lượng ổ đĩa từng VM, đơn vị GB"
echo "  vms -> network_name   : Port Group gán cho từng VM"
echo ""
echo "LƯU Ý: Nếu các giá trị mặc định phù hợp, có thể bỏ qua bước này."
echo "=============================================================================="
read -p "Nhấn Enter để tiếp tục..." IGNORE_VAR

# ==============================================================================
# 4. Thu thập Mật khẩu (1 LẦN DUY NHẤT)
# ==============================================================================
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
    read -s -p "Nhập mật khẩu SSH (${SSH_USER}) [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export SSH_PASS="${INPUT_PASS}"
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu SSH (${SSH_USER}): " SSH_PASS
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

# ==============================================================================
# 5. Xử lý ISO tự động (Download & Upload)
# ==============================================================================
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

# ==============================================================================
# 6. Thực thi Packer
# ==============================================================================
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 1/4: ĐÓNG GÓI PACKER TEMPLATE"
echo "=============================================================================="
cd "${SCRIPT_DIR}/packer_test"
./build_packer_secure.sh

# ==============================================================================
# 7. Đồng bộ tên Template từ Packer sang Terraform (lần cuối, đề phòng user sửa)
# ==============================================================================
echo ""
echo "=============================================================================="
echo "ĐỒNG BỘ CẤU HÌNH: PACKER -> TERRAFORM"
echo "=============================================================================="
TEMPLATE_NAME=$(grep -E '^\s*vm_name\s*=' "${PKR_FILE}" | head -n 1 | cut -d'"' -f2)
if [[ -n "${TEMPLATE_NAME}" ]]; then
    echo "Phát hiện tên template từ Packer: ${TEMPLATE_NAME}"
    sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TEMPLATE_NAME}\2/" "${TF_FILE}"
    echo "Đã đồng bộ tên template sang Terraform thành công."
else
    echo "Cảnh báo: Không tìm thấy vm_name trong cấu hình Packer."
fi

# ==============================================================================
# 8. Thực thi Terraform
# ==============================================================================
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 2/4: KHỞI TẠO HẠ TẦNG VSPHERE (TERRAFORM)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/terraform_test"
./run_provision_secure.sh

# ==============================================================================
# 9. Thực thi Ansible Deploy
# ==============================================================================
echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 3/4: CẤU HÌNH ELASTIC STACK (ANSIBLE)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/ansible_test"
./run_ansible_secure.sh

# ==============================================================================
# 10. Thực thi Ansible Observability
# ==============================================================================
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
