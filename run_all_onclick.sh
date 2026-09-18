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
         "${SCRIPT_DIR}/automation_seed/setup_automation_env.sh" \
         "${SCRIPT_DIR}/automation_seed/manage_vsphere_observability.sh"

# ==============================================================================
# 0. Mở tmux session nếu chưa ở trong tmux
# ==============================================================================
if [[ -z "${TMUX:-}" ]]; then
    if command -v tmux &> /dev/null; then
        echo "Khởi tạo phiên tmux (deploy_session) để chống đứt kết nối SSH..."
        exec tmux new-session -s deploy_session \
            "bash -c 'trap \":\" SIGINT; bash \"$0\" \"$@\" 2>&1 | tee \"${LOG_FILE}\"; EXIT_CODE=\${PIPESTATUS[0]}; echo \"\"; echo \"=== Script kết thúc với exit code: \${EXIT_CODE} ===\"; echo \"Bạn đang ở trong tmux. Gõ exit để đóng, hoặc nhấn Ctrl+B rồi ấn D để thoát ẩn (detach).\"; exec bash'"
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
        printf -v "${var_name}" "%s" "${new_val}"
        sed -i -E "s|^${var_name}=.*|${var_name}=\"${new_val}\"|" "${VARS_CONF}"
    fi
}

prompt_password() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"
    local new_val=""

    if [[ -n "${current_val}" ]]; then
        read -s -p "${prompt_msg} [Đã lưu trong phiên, Enter để giữ nguyên]: " new_val
        echo ""
        [[ -n "${new_val}" ]] && printf -v "${var_name}" "%s" "${new_val}"
    else
        read -s -p "${prompt_msg}: " new_val
        echo ""
        printf -v "${var_name}" "%s" "${new_val}"
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
DNS_SERVER="<DNS_SERVER>"
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
    prompt_if_placeholder "DNS_SERVER" "Nhập IP của DNS Server nội bộ (cách nhau bởi dấu phẩy nếu nhiều hơn 1, vd: 10.0.6.1, 8.8.8.8)"

    echo "------------------------------------------------------------------------------"
    echo "THU THẬP MẬT KHẨU BẢO MẬT (Chỉ hỏi 1 lần và lưu trong RAM)"
    echo "------------------------------------------------------------------------------"
    prompt_password "VCENTER_PASS" "Mật khẩu vCenter"
    prompt_password "SSH_PASS" "Mật khẩu SSH (${SSH_USER})"
    prompt_password "SUDO_PASS" "Mật khẩu Sudo (nếu cần đổi quyền gốc)"
    prompt_password "ELASTIC_PASS" "Mật khẩu Elastic (elastic)"
    prompt_password "KIBANA_PASS" "Mật khẩu Kibana (kibana_system)"

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

    # Khởi tạo hoặc tái sử dụng SSH Key tiêu chuẩn (~/.ssh/id_ed25519)
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    local SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
        echo "Chưa tìm thấy SSH key tiêu chuẩn, đang tự động tạo: ${SSH_KEY_PATH}..."
        ssh-keygen -t ed25519 -N "" -f "${SSH_KEY_PATH}" -C ""
        chmod 600 "${SSH_KEY_PATH}"
        chmod 644 "${SSH_KEY_PATH}.pub"
    else
        echo "Tái sử dụng SSH key tiêu chuẩn hiện có: ${SSH_KEY_PATH}"
    fi
    local SSH_PUB_KEY
    SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

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

    if grep -q "ssh_username" "${TF_FILE}"; then
        sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${TF_FILE}"
    else
        echo "ssh_username   = \"${SSH_USER}\"" >> "${TF_FILE}"
    fi

    if grep -q "ssh_public_key" "${TF_FILE}"; then
        sed -i -E "s|(ssh_public_key\s*=\s*\")[^\"]+(\")|\1${SSH_PUB_KEY}\2|" "${TF_FILE}"
    else
        echo "ssh_public_key = \"${SSH_PUB_KEY}\"" >> "${TF_FILE}"
    fi

    if [[ -f "${SCRIPT_DIR}/ansible_test/ansible.cfg" ]]; then
        sed -i -E "s/(remote_user\s*=\s*).*/\1${SSH_USER}/" "${SCRIPT_DIR}/ansible_test/ansible.cfg"
    fi

    if [[ -f "${ANS_FILE}" ]]; then
        sed -i -E "s/(ansible_user\s*:\s*).*/\1${SSH_USER}/" "${ANS_FILE}"
        if ! grep -q "ansible_ssh_private_key_file" "${ANS_FILE}"; then
            sed -i "/ansible_user:/a \    ansible_ssh_private_key_file: ~/.ssh/id_ed25519" "${ANS_FILE}"
        fi
    fi

    # Xử lý chuỗi DNS_SERVER (có thể chứa nhiều IP cách nhau bởi dấu phẩy hoặc khoảng trắng)
    FORMATTED_DNS=""
    for ip in $(echo "${DNS_SERVER}" | tr ',' ' '); do
        if [[ -z "${FORMATTED_DNS}" ]]; then
            FORMATTED_DNS="\"${ip}\""
        else
            FORMATTED_DNS="${FORMATTED_DNS}, \"${ip}\""
        fi
    done
    # Thay thế list DNS trong TF_FILE (bắt cả placeholder lẫn mảng đã có giá trị)
    sed -i -E "s/(default_dns_servers\s*=\s*).*/\1\[${FORMATTED_DNS}\]/" "${TF_FILE}"
    if [[ -f "${USER_DATA_FILE}" ]]; then
        SSH_PASS_HASH=$(python3 -c "import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" "${SSH_PASS}" 2>/dev/null || openssl passwd -6 "${SSH_PASS}")
        sed -i -E "s|(password:\s*\").*(\")|\1${SSH_PASS_HASH}\2|" "${USER_DATA_FILE}"
        sed -i -E "s/(username:\s*).*/\1${SSH_USER}/" "${USER_DATA_FILE}"
        sed -i "s|<SSH_USER>|${SSH_USER}|g" "${USER_DATA_FILE}"
        sed -i "s|<SSH_PUB_KEY>|${SSH_PUB_KEY}|g" "${USER_DATA_FILE}"
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

save_last_used_iso() {
    local iso_remote_name="$1"
    if ! grep -q "^LAST_USED_ISO=" "${VARS_CONF}"; then
        echo "LAST_USED_ISO=\"${iso_remote_name}\"" >> "${VARS_CONF}"
    else
        sed -i "s|^LAST_USED_ISO=.*|LAST_USED_ISO=\"${iso_remote_name}\"|" "${VARS_CONF}"
    fi
}

upload_iso_to_datastore() {
    local local_path="$1"
    local remote_name="$2"
    if govc datastore.ls -ds="${ISO_DATASTORE}" "${remote_name}" &> /dev/null; then
        echo "ISO đã tồn tại trên Datastore, bỏ qua việc upload."
    else
        govc datastore.mkdir -ds="${ISO_DATASTORE}" iso || true
        govc datastore.upload -ds="${ISO_DATASTORE}" "${local_path}" "${remote_name}"
    fi
}

run_iso_menu() {
    echo ""
    echo "=============================================================================="
    echo "XỬ LÝ FILE ISO OS CHO QUÁ TRÌNH TẠO TEMPLATE"
    echo "=============================================================================="
    
    # Kiểm tra ISO đã dùng lần trước
    if [[ -n "${LAST_USED_ISO:-}" ]]; then
        echo "Phát hiện bạn đã từng sử dụng file ISO trên Datastore [${ISO_DATASTORE}]: ${LAST_USED_ISO}"
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
                upload_iso_to_datastore "${ISO_LOCAL_FILE}" "${ISO_REMOTE_NAME}"
                
                update_iso_in_packer "${ISO_REMOTE_NAME}"
                save_last_used_iso "${ISO_REMOTE_NAME}"
                
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
                upload_iso_to_datastore "${CHOSEN_LOCAL_ISO}" "${ISO_REMOTE_NAME}"
                
                update_iso_in_packer "${ISO_REMOTE_NAME}"
                save_last_used_iso "${ISO_REMOTE_NAME}"
                
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
                save_last_used_iso "${CHOSEN_REMOTE_ISO}"
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
    echo "PRE-FLIGHT CHECK: KIỂM TRA FILE CẤU HÌNH (TERRAFORM)"
    echo "=============================================================================="
    if grep -v '^\s*#' "${TF_FILE}" | grep -q -E '<[A-Z0-9_]+>'; then
        echo "CẢNH BÁO: File ${TF_FILE} vẫn còn chứa biến chưa được gán giá trị (ví dụ: <ESXI_HOST_01>)."
        echo "Vì bạn muốn cấu hình thủ công cho các tham số mở rộng (như IP host vật lý), vui lòng:"
        echo "  1. Mở file: terraform_test/terraform.tfvars"
        echo "  2. Tìm và thay thế các chuỗi <...> bằng giá trị thực tế của bạn."
        echo "  3. Lưu file lại."
        read -p "Sau khi sửa xong file, nhấn Enter tại đây để tiếp tục chạy Terraform..."
    else
        echo "File cấu hình Terraform hợp lệ, không còn biến <PLACEHOLDER>."
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

run_vsphere_observability() {
    echo ""
    echo "=============================================================================="
    echo "PRE-FLIGHT CHECK: TÍCH HỢP GIÁM SÁT VMWARE VSPHERE (GIAI ĐOẠN 5)"
    echo "=============================================================================="
    read -p "Bạn có muốn tiếp tục chạy Giai đoạn 5 (Tích hợp giám sát vCenter & ESXi) không? (Y/n): " CONFIRM_VSPHERE
    CONFIRM_VSPHERE=${CONFIRM_VSPHERE:-Y}
    if [[ ! "${CONFIRM_VSPHERE}" =~ ^[yY]$ ]]; then
        echo "Đã bỏ qua tích hợp giám sát VMware vSphere."
        return 1
    fi

    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: TÍCH HỢP GIÁM SÁT HẠ TẦNG VMWARE VSPHERE"
    echo "=============================================================================="
    "${SCRIPT_DIR}/automation_seed/manage_vsphere_observability.sh" apply
}

run_vsphere_rollback() {
    echo ""
    echo "=============================================================================="
    echo "TIẾN TRÌNH: HOÀN TÁC GIÁM SÁT HẠ TẦNG VMWARE VSPHERE (ROLLBACK)"
    echo "=============================================================================="
    "${SCRIPT_DIR}/automation_seed/manage_vsphere_observability.sh" rollback
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
    echo "5) Tích hợp giám sát hạ tầng VMware vSphere (vCenter & ESXi Observability)"
    echo "6) Hoàn tác giám sát hạ tầng VMware vSphere (Rollback vSphere Configuration)"
    echo "0) Thoát"
    read -p "Vui lòng chọn (0-6) [1]: " MAIN_CHOICE
    MAIN_CHOICE=${MAIN_CHOICE:-1}

    case "${MAIN_CHOICE}" in
        1)
            if ! run_packer; then
                echo "Đã hủy luồng chạy toàn bộ. Quay lại menu chính."
                continue
            fi
            if ! run_terraform; then
                echo "Đã hủy luồng chạy toàn bộ. Quay lại menu chính."
                continue
            fi
            if ! run_ansible; then
                echo "Đã hủy luồng chạy toàn bộ. Quay lại menu chính."
                continue
            fi
            run_vsphere_observability || true
            echo ""
            echo "HOÀN TẤT QUÁ TRÌNH TRIỂN KHAI TOÀN BỘ."
            break
            ;;
        2)
            if run_packer; then
                echo "HOÀN TẤT QUÁ TRÌNH TẠO TEMPLATE."
            fi
            ;;
        3)
            if run_terraform; then
                echo "HOÀN TẤT QUÁ TRÌNH TẠO HẠ TẦNG."
            fi
            ;;
        4)
            if run_ansible; then
                echo "HOÀN TẤT QUÁ TRÌNH CẤU HÌNH ỨNG DỤNG."
            fi
            ;;
        5)
            if run_vsphere_observability; then
                echo "HOÀN TẤT QUÁ TRÌNH TÍCH HỢP GIÁM SÁT VSPHERE."
            fi
            ;;
        6)
            if run_vsphere_rollback; then
                echo "HOÀN TẤT QUÁ TRÌNH HOÀN TÁC GIÁM SÁT VSPHERE."
            fi
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
