#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator Script for One-Click Deployment (Version 4 - Interactive)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
PKR_FILE="${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
TF_FILE="${SCRIPT_DIR}/terraform_test/terraform.tfvars"
ANS_FILE="${SCRIPT_DIR}/ansible_test/inventories/lab/hosts.yml"
ANS_VARS_FILE="${SCRIPT_DIR}/ansible_test/inventories/lab/group_vars/all/main.yml"
USER_DATA_FILE="${SCRIPT_DIR}/packer_test/http/user-data"
VARS_CONF="${SCRIPT_DIR}/vars.conf"

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
        exec tmux new-session -s deploy_session \
            "bash -c 'bash \"$0\" \"$@\" 2>&1 | tee \"${LOG_FILE}\"; EXIT_CODE=\${PIPESTATUS[0]}; echo \"\"; echo \"=== Script kết thúc với exit code: \${EXIT_CODE} ===\"; echo \"Bạn đang ở trong tmux. Gõ exit để đóng, hoặc nhấn Ctrl+B rồi ấn D để thoát ẩn (detach).\"; exec bash'"
    else
        echo "CẢNH BÁO: tmux chưa được cài đặt. Nếu đứt SSH sẽ bị gián đoạn."
        exec > >(tee -a "${LOG_FILE}") 2>&1
    fi
else
    exec > >(tee -a "${LOG_FILE}") 2>&1
fi

echo "=============================================================================="
echo "HỆ THỐNG ĐIỀU PHỐI TỰ ĐỘNG - INTERACTIVE DEPLOYMENT (v4)"
echo "Log file: ${LOG_FILE}"
echo "=============================================================================="

# ==============================================================================
# HÀM HỖ TRỢ
# ==============================================================================

init_config_files() {
    echo "--- KIỂM TRA VÀ KHỞI TẠO TỆP CẤU HÌNH ---"
    [[ ! -f "${PKR_FILE}" ]] && cp "${PKR_FILE}.example" "${PKR_FILE}" && echo "Đã tạo: packer.pkrvars.hcl"
    [[ ! -f "${TF_FILE}" ]] && cp "${TF_FILE}.example" "${TF_FILE}" && echo "Đã tạo: terraform.tfvars"
    [[ ! -f "${ANS_FILE}" ]] && cp "${ANS_FILE}.example" "${ANS_FILE}" && echo "Đã tạo: hosts.yml"
    [[ ! -f "${ANS_VARS_FILE}" ]] && cp "${ANS_VARS_FILE}.example" "${ANS_VARS_FILE}" && echo "Đã tạo: main.yml"
    [[ ! -f "${USER_DATA_FILE}" && -f "${USER_DATA_FILE}.example" ]] && cp "${USER_DATA_FILE}.example" "${USER_DATA_FILE}" && echo "Đã tạo: user-data"
    return 0
}

prompt_if_placeholder() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"

    # Cờ đánh dấu nếu biến đang rỗng hoặc là placeholder (chứa cặp ngoặc <...>)
    if [[ -z "${current_val}" || "${current_val}" == *"<"*">"* ]]; then
        local new_val=""
        while [[ -z "${new_val}" || "${new_val}" == *"<"*">"* ]]; do
            read -p "${prompt_msg} [hiện tại: ${current_val}]: " new_val
            # Nếu người dùng bấm Enter mà current_val vẫn là placeholder, bắt nhập lại
            if [[ -z "${new_val}" ]]; then
                if [[ "${current_val}" == *"<"*">"* || -z "${current_val}" ]]; then
                    echo "=> Giá trị không được để trống hoặc chứa <PLACEHOLDER>!"
                    new_val=""
                else
                    new_val="${current_val}"
                fi
            fi
        done
        # Cập nhật giá trị mới vào biến và lưu vào vars.conf
        eval "${var_name}=\"${new_val}\""
        sed -i -E "s|^${var_name}=.*|${var_name}=\"${new_val}\"|" "${VARS_CONF}"
    fi
}

gather_vars() {
    if [[ ! -f "${VARS_CONF}" ]]; then
        cat << 'EOF' > "${VARS_CONF}"
# ==============================================================================
# TỆP CẤU HÌNH BIẾN CHUNG (Tự động điền vào Packer, Terraform, Ansible)
# ==============================================================================

# --- vCenter Server ---
SITE_VCSA_IP="<VCENTER_IP>"
VCENTER_USER="<VCENTER_USER>"

# --- Hạ tầng vSphere ---
VCENTER_DC="Datacenter"
VCENTER_CLUSTER="Cluster1"
ISO_DATASTORE="<DATASTORE_NAME>"
PKR_NETWORK="VM Network"
VM_FOLDER="App_Workloads"
TPL_NAME="tpl-ubuntu-2404-golden"

# --- Tài khoản OS ---
SSH_USER="<SSH_USER>"

# --- IP tĩnh 4 VM ---
IP_E01="<IP_NODE_01>"
IP_E02="<IP_NODE_02>"
IP_E03="<IP_NODE_03>"
IP_KBN="<IP_KIBANA>"
GW="<GATEWAY>"
NETMASK="24"
EOF
        echo "CHÚ Ý: Lần chạy đầu tiên, hệ thống đã tạo tệp cấu hình '${VARS_CONF}'."
    fi

    source "${VARS_CONF}"

    echo ""
    echo "------------------------------------------------------------------------------"
    echo "CẤU HÌNH SETUP WIZARD (Kiểm tra và điền các thông số còn thiếu)"
    echo "------------------------------------------------------------------------------"
    prompt_if_placeholder "SITE_VCSA_IP" "Nhập IP của vCenter Server"
    prompt_if_placeholder "VCENTER_USER" "Nhập tài khoản đăng nhập vCenter (vd: administrator@vsphere.local)"
    prompt_if_placeholder "ISO_DATASTORE" "Nhập tên Datastore lưu ISO"
    prompt_if_placeholder "SSH_USER" "Nhập tài khoản SSH cho máy ảo (vd: ubuntu, sysops)"
    prompt_if_placeholder "IP_E01" "Nhập IP tĩnh cho Elasticsearch Node 1 (srv-elastic-01)"
    prompt_if_placeholder "IP_E02" "Nhập IP tĩnh cho Elasticsearch Node 2 (srv-elastic-02)"
    prompt_if_placeholder "IP_E03" "Nhập IP tĩnh cho Elasticsearch Node 3 (srv-elastic-03)"
    prompt_if_placeholder "IP_KBN" "Nhập IP tĩnh cho Kibana/Fleet Server (srv-kibana-gw)"
    prompt_if_placeholder "GW" "Nhập Default Gateway (vd: 10.0.6.1)"

    echo "------------------------------------------------------------------------------"
    echo "THU THẬP MẬT KHẨU BẢO MẬT (Chỉ hỏi 1 lần và lưu trong RAM)"
    echo "------------------------------------------------------------------------------"
    [[ -z "${VCENTER_PASS:-}" ]] && read -s -p "Mật khẩu vCenter: " VCENTER_PASS && echo ""
    [[ -z "${SSH_PASS:-}" ]] && read -s -p "Mật khẩu SSH (${SSH_USER}): " SSH_PASS && echo ""
    [[ -z "${SUDO_PASS:-}" ]] && read -s -p "Mật khẩu Sudo (nếu cần đổi quyền gốc): " SUDO_PASS && echo ""
    [[ -z "${ELASTIC_PASS:-}" ]] && read -s -p "Mật khẩu Elastic (elastic): " ELASTIC_PASS && echo ""
    [[ -z "${KIBANA_PASS:-}" ]] && read -s -p "Mật khẩu Kibana (kibana_system): " KIBANA_PASS && echo ""

    export VCENTER_PASS SSH_PASS SUDO_PASS ELASTIC_PASS KIBANA_PASS
    export VSPHERE_PASSWORD="${VCENTER_PASS}"
    export GOVC_URL="https://${SITE_VCSA_IP}"
    export GOVC_USERNAME="${VCENTER_USER}"
    export GOVC_PASSWORD="${VCENTER_PASS}"
    export GOVC_INSECURE="1"

    for var in SITE_VCSA_IP VCENTER_PASS ISO_DATASTORE SSH_PASS; do
        if [[ -z "${!var:-}" ]]; then
            echo "Lỗi: Biến $var trong vars.conf không được để trống! Hãy sửa file và chạy lại." >&2
            exit 1
        fi
    done
}

configure_templates() {
    echo "Đang cấu hình động các file mẫu..."
    sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${TF_FILE}"
    sed -i -E "s/(vcenter_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${TF_FILE}"
    sed -i -E "s/(vcenter_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${TF_FILE}"
    sed -i -E "s/(vcenter_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${TF_FILE}"
    sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${TF_FILE}"
    sed -i -E "s/(vcenter_network\s*=\s*\")[^\"]+(\")/\1${PKR_NETWORK}\2/" "${PKR_FILE}"
    sed -i -E "s/(vcenter_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${PKR_FILE}"
    sed -i -E "s/(vm_target_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${TF_FILE}"
    sed -i -E "s/(vm_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${PKR_FILE}"
    sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"
    sed -i -E "s/(content_library_item_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"
    sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${PKR_FILE}"
    sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${TF_FILE}"

    if [[ -f "${USER_DATA_FILE}" ]]; then
        SSH_PASS_HASH=$(python3 -c "import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" "${SSH_PASS}")
        sed -i -E "s|(password:\s*\").*(\")|\1${SSH_PASS_HASH}\2|" "${USER_DATA_FILE}"
        sed -i -E "s/(username:\s*).*/\1${SSH_USER}/" "${USER_DATA_FILE}"
        sed -i "s|<SSH_USER>|${SSH_USER}|g" "${USER_DATA_FILE}"
    fi

    python3 - "${TF_FILE}" "${IP_E01}" "${IP_E02}" "${IP_E03}" "${IP_KBN}" "${GW}" "${NETMASK}" << 'PYEOF'
import sys, re
tf_file = sys.argv[1]
ips = {"elastic_01": sys.argv[2], "elastic_02": sys.argv[3], "elastic_03": sys.argv[4], "kibana_gw": sys.argv[5]}
gw = sys.argv[6]
netmask = sys.argv[7]

with open(tf_file, 'r') as f:
    content = f.read()

for key, ip in ips.items():
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

    sed -i -E "s|(fleet_server_url:\s*\").*(\")|\1https://${IP_KBN}:8220\2|" "${ANS_VARS_FILE}"
    sed -i -E "s|(fleet_server_elasticsearch_url:\s*\").*(\")|\1http://${IP_E01}:9200\2|" "${ANS_VARS_FILE}"
}

update_iso_in_packer() {
    local iso_path="$1"
    # Dùng sed thay thế toàn bộ block iso_paths đa dòng
    sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "['"${ISO_DATASTORE}"'] '"${iso_path}"'"\
]' "${PKR_FILE}"
}

run_iso_menu() {
    echo ""
    echo "=============================================================================="
    echo "XỬ LÝ FILE ISO OS CHO QUÁ TRÌNH TẠO TEMPLATE"
    echo "=============================================================================="
    
    # Kiểm tra ISO đã dùng lần trước
    if [[ -n "${LAST_USED_ISO:-}" ]]; then
        echo "Phát hiện bạn đã từng dùng ISO tại: ${LAST_USED_ISO}"
        read -p "Bạn có muốn tiếp tục sử dụng ISO này không? (Y/n): " USE_OLD
        if [[ "${USE_OLD}" != "n" && "${USE_OLD}" != "N" ]]; then
            update_iso_in_packer "${LAST_USED_ISO}"
            return
        fi
    fi

    while true; do
        echo "Bạn muốn xử lý file ISO cài đặt OS như thế nào?"
        echo "1) Tải ISO mới từ Internet (Mặc định: Ubuntu 24.04, sẽ tải và upload lên Datastore)"
        echo "2) Tìm và chọn file ISO đã có sẵn trên máy tính cục bộ (Sẽ tự upload lên Datastore)"
        echo "3) Chọn file ISO đã có sẵn trên vCenter Datastore (Bỏ qua hoàn toàn tải/upload)"
        echo "0) Thoát"
        read -p "Vui lòng chọn (0-3) [1]: " ISO_CHOICE
        ISO_CHOICE=${ISO_CHOICE:-1}

        case "${ISO_CHOICE}" in
            0)
                echo "Thoát chương trình."
                exit 0
                ;;
            1)
                echo "-> Tải ISO từ Internet..."
                cd "${SCRIPT_DIR}/automation_seed"
                ./download_iso.sh --ubuntu
                local ISO_LOCAL_FILE="./iso_cache/ubuntu-24.04.5-live-server-amd64.iso"
                if [[ ! -f "${ISO_LOCAL_FILE}" ]]; then
                    echo "Lỗi: Tải ISO thất bại." >&2
                    exit 1
                fi
                echo "-> Upload lên Datastore [${ISO_DATASTORE}]..."
                local ISO_REMOTE_NAME="iso/ubuntu-24.04.5-live-server-amd64.iso"
                if govc datastore.ls -ds="${ISO_DATASTORE}" "${ISO_REMOTE_NAME}" &> /dev/null; then
                    echo "ISO đã tồn tại trên Datastore, bỏ qua việc upload."
                else
                    govc datastore.mkdir -ds="${ISO_DATASTORE}" iso || true
                    govc datastore.upload -ds="${ISO_DATASTORE}" "${ISO_LOCAL_FILE}" "${ISO_REMOTE_NAME}"
                fi
                update_iso_in_packer "${ISO_REMOTE_NAME}"
                
                # Lưu vào vars.conf
                if ! grep -q "^LAST_USED_ISO=" "${VARS_CONF}"; then
                    echo "LAST_USED_ISO=\"${ISO_REMOTE_NAME}\"" >> "${VARS_CONF}"
                else
                    sed -i "s|^LAST_USED_ISO=.*|LAST_USED_ISO=\"${ISO_REMOTE_NAME}\"|" "${VARS_CONF}"
                fi
                break
                ;;
            2)
                read -p "Nhập đường dẫn thư mục chứa ISO trên máy (ví dụ: /mnt/d/ISO hoặc .): " LOCAL_DIR
                if [[ ! -d "${LOCAL_DIR}" ]]; then
                    echo "Thư mục không tồn tại."
                    continue
                fi
                echo "Đang quét các file .iso trong ${LOCAL_DIR}..."
                # Lấy danh sách file ISO
                mapfile -t ISO_FILES < <(find "${LOCAL_DIR}" -type f -name "*.iso")
                if [[ ${#ISO_FILES[@]} -eq 0 ]]; then
                    echo "Không tìm thấy file ISO nào trong ${LOCAL_DIR}."
                    continue
                fi
                echo "Chọn file ISO muốn dùng:"
                for i in "${!ISO_FILES[@]}"; do
                    echo "$((i+1))) ${ISO_FILES[$i]}"
                done
                read -p "Nhập số thứ tự: " SEL_INDEX
                if ! [[ "${SEL_INDEX}" =~ ^[0-9]+$ ]] || [ "${SEL_INDEX}" -lt 1 ] || [ "${SEL_INDEX}" -gt "${#ISO_FILES[@]}" ]; then
                    echo "Lựa chọn không hợp lệ."
                    continue
                fi
                local CHOSEN_LOCAL_ISO="${ISO_FILES[$((SEL_INDEX-1))]}"
                local BASE_NAME=$(basename "${CHOSEN_LOCAL_ISO}")
                local ISO_REMOTE_NAME="iso/${BASE_NAME}"
                echo "-> Upload ${CHOSEN_LOCAL_ISO} lên Datastore [${ISO_DATASTORE}]..."
                if govc datastore.ls -ds="${ISO_DATASTORE}" "${ISO_REMOTE_NAME}" &> /dev/null; then
                    echo "ISO ${BASE_NAME} đã tồn tại trên Datastore, bỏ qua việc upload."
                else
                    govc datastore.mkdir -ds="${ISO_DATASTORE}" iso || true
                    govc datastore.upload -ds="${ISO_DATASTORE}" "${CHOSEN_LOCAL_ISO}" "${ISO_REMOTE_NAME}"
                fi
                update_iso_in_packer "${ISO_REMOTE_NAME}"
                if ! grep -q "^LAST_USED_ISO=" "${VARS_CONF}"; then
                    echo "LAST_USED_ISO=\"${ISO_REMOTE_NAME}\"" >> "${VARS_CONF}"
                else
                    sed -i "s|^LAST_USED_ISO=.*|LAST_USED_ISO=\"${ISO_REMOTE_NAME}\"|" "${VARS_CONF}"
                fi
                break
                ;;
            3)
                echo "Đang quét các file .iso trên Datastore [${ISO_DATASTORE}]..."
                if ! command -v govc &> /dev/null; then
                    echo "Lỗi: Không tìm thấy lệnh govc để quét Datastore."
                    continue
                fi
                # Quét đệ quy và lọc các file iso
                mapfile -t REMOTE_ISOS < <(govc datastore.ls -R -ds="${ISO_DATASTORE}" | grep -i "\.iso$")
                if [[ ${#REMOTE_ISOS[@]} -eq 0 ]]; then
                    echo "Không tìm thấy file ISO nào trên Datastore [${ISO_DATASTORE}]."
                    continue
                fi
                echo "Chọn file ISO muốn dùng trên Datastore:"
                for i in "${!REMOTE_ISOS[@]}"; do
                    echo "$((i+1))) ${REMOTE_ISOS[$i]}"
                done
                read -p "Nhập số thứ tự: " SEL_INDEX
                if ! [[ "${SEL_INDEX}" =~ ^[0-9]+$ ]] || [ "${SEL_INDEX}" -lt 1 ] || [ "${SEL_INDEX}" -gt "${#REMOTE_ISOS[@]}" ]; then
                    echo "Lựa chọn không hợp lệ."
                    continue
                fi
                local CHOSEN_REMOTE_ISO="${REMOTE_ISOS[$((SEL_INDEX-1))]}"
                echo "Đã chọn: ${CHOSEN_REMOTE_ISO}"
                update_iso_in_packer "${CHOSEN_REMOTE_ISO}"
                if ! grep -q "^LAST_USED_ISO=" "${VARS_CONF}"; then
                    echo "LAST_USED_ISO=\"${CHOSEN_REMOTE_ISO}\"" >> "${VARS_CONF}"
                else
                    sed -i "s|^LAST_USED_ISO=.*|LAST_USED_ISO=\"${CHOSEN_REMOTE_ISO}\"|" "${VARS_CONF}"
                fi
                break
                ;;
            *)
                echo "Lựa chọn không hợp lệ."
                ;;
        esac
    done
}

run_packer() {
    run_iso_menu
    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: ĐÓNG GÓI GOLDEN TEMPLATE (PACKER)"
    echo "=============================================================================="
    cd "${SCRIPT_DIR}/packer_test"
    ./build_packer_secure.sh

    # Đồng bộ tên template sang Terraform
    local TEMPLATE_NAME=$(grep -E '^\s*vm_name\s*=' "${PKR_FILE}" | head -n 1 | cut -d'"' -f2)
    if [[ -n "${TEMPLATE_NAME}" ]]; then
        sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TEMPLATE_NAME}\2/" "${TF_FILE}"
        sed -i -E "s/(content_library_item_name\s*=\s*\")[^\"]+(\")/\1${TEMPLATE_NAME}\2/" "${TF_FILE}"
        echo "Đã đồng bộ tên template sang Terraform."
    fi
}

run_terraform() {
    echo ""
    echo "=============================================================================="
    echo "PRE-FLIGHT CHECK: KIỂM TRA TEMPLATE TRƯỚC KHI CẤP PHÁT (TERRAFORM)"
    echo "=============================================================================="
    local CURRENT_TPL=$(grep -E '^\s*vsphere_template_name\s*=' "${TF_FILE}" | head -n 1 | cut -d'"' -f2)
    echo "Đang tìm kiếm template: ${CURRENT_TPL}..."
    if ! govc find -type m -name "${CURRENT_TPL}" | grep -q "${CURRENT_TPL}"; then
        echo "CẢNH BÁO: Không tìm thấy máy ảo template '${CURRENT_TPL}' trên vCenter!"
        echo "Bạn có thể cần chạy Bước Tạo Template (Packer) trước khi chạy Terraform."
        read -p "Bạn có chắc chắn muốn tiếp tục chạy Terraform? (y/N): " CONFIRM_TF
        if [[ "${CONFIRM_TF}" != "y" && "${CONFIRM_TF}" != "Y" ]]; then
            echo "Đã hủy chạy Terraform."
            return 1
        fi
    else
        echo "Template hợp lệ, đã tìm thấy trên vCenter."
    fi

    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: KHỞI TẠO HẠ TẦNG VSPHERE (TERRAFORM)"
    echo "=============================================================================="
    cd "${SCRIPT_DIR}/terraform_test"
    ./run_provision_secure.sh
}

run_ansible() {
    echo ""
    echo "=============================================================================="
    echo "PRE-FLIGHT CHECK: KIỂM TRA KẾT NỐI MÁY ẢO TRƯỚC KHI CẤU HÌNH (ANSIBLE)"
    echo "=============================================================================="
    local ALL_IPS=("${IP_E01}" "${IP_E02}" "${IP_E03}" "${IP_KBN}")
    local FAILED_IPS=0
    for ip in "${ALL_IPS[@]}"; do
        if ! ping -c 1 -W 2 "$ip" &> /dev/null; then
            echo "LỖI: Máy ảo với IP $ip không phản hồi (Ping timeout)!"
            FAILED_IPS=$((FAILED_IPS + 1))
        fi
    done
    
    if [[ $FAILED_IPS -gt 0 ]]; then
        echo "CẢNH BÁO: Một số máy ảo chưa sẵn sàng. Bạn có chắc chắn hạ tầng đã được tạo bằng Terraform?"
        read -p "Bạn có muốn tiếp tục chạy Ansible không? (y/N): " CONFIRM_ANS
        if [[ "${CONFIRM_ANS}" != "y" && "${CONFIRM_ANS}" != "Y" ]]; then
            echo "Đã hủy chạy Ansible."
            return 1
        fi
    else
        echo "Tất cả máy ảo mục tiêu đều có thể Ping được. Mạng thông suốt."
    fi

    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: CẤU HÌNH ỨNG DỤNG (ANSIBLE ELASTIC STACK)"
    echo "=============================================================================="
    cd "${SCRIPT_DIR}/ansible_test"
    ./run_ansible_secure.sh

    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: KÍCH HOẠT QUAN SÁT TẬP TRUNG (OBSERVABILITY)"
    echo "=============================================================================="
    ./run_observability_setup.sh
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

init_config_files
gather_vars
configure_templates

while true; do
    echo ""
    echo "=============================================================================="
    echo "MENU ĐIỀU PHỐI TRIỂN KHAI HẠ TẦNG & ỨNG DỤNG"
    echo "=============================================================================="
    echo "1) Chạy toàn bộ quy trình (Từ đầu đến cuối)"
    echo "2) Chỉ tạo Golden Template (Packer)"
    echo "3) Chỉ cấp phát hạ tầng (Terraform Provisioning)"
    echo "4) Chỉ cấu hình ứng dụng (Ansible Configuration)"
    echo "0) Thoát"
    read -p "Vui lòng chọn (0-4) [1]: " MAIN_CHOICE
    MAIN_CHOICE=${MAIN_CHOICE:-1}

    case "${MAIN_CHOICE}" in
        1)
            run_packer
            run_terraform
            run_ansible
            echo "HOÀN TẤT QUÁ TRÌNH TRIỂN KHAI TOÀN BỘ."
            break
            ;;
        2)
            run_packer
            echo "HOÀN TẤT QUÁ TRÌNH TẠO TEMPLATE."
            ;;
        3)
            run_terraform
            echo "HOÀN TẤT QUÁ TRÌNH TẠO HẠ TẦNG."
            ;;
        4)
            run_ansible
            echo "HOÀN TẤT QUÁ TRÌNH CẤU HÌNH ỨNG DỤNG."
            ;;
        0)
            echo "Thoát chương trình."
            exit 0
            ;;
        *)
            echo "Lựa chọn không hợp lệ."
            ;;
    esac
done
