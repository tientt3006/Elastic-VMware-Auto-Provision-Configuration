#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Packer Golden Image Build Wrapper (Generalized Component)
# - Run directly from inside packer directory: ./build.sh [--template <os_name>]
# - Dynamically scans and supports multiple OS templates in packer/templates/
# - Interactively prompts for OS template selection if no argument is provided
# - Extracts target vCenter topology directly from template's packer.pkrvars.hcl
# - Manages credentials strictly in RAM via lib/common.sh & lib/secrets.sh
# - Executes pre-flight check via govc and prompts for duplicate VM overwrite
# - Automatically clears in-memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Nạp các thư viện nền tảng nếu có sẵn
# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
[[ -f "${REPO_ROOT}/lib/vsphere.sh" ]] && source "${REPO_ROOT}/lib/vsphere.sh"

trap cleanup_secrets EXIT INT TERM

show_usage() {
    echo "Sử dụng: $0 [TÙY CHỌN]"
    echo ""
    echo "Tùy chọn:"
    echo "  -t, --template <tên_os>   Chỉ định tên template OS (ví dụ: ubuntu-24.04)"
    echo "  -h, --help                Hiển thị hướng dẫn này"
    echo ""
    echo "Danh sách template có sẵn:"
    local tmpls=()
    mapfile -t tmpls < <(find "${SCRIPT_DIR}/templates" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort || true)
    for t in "${tmpls[@]}"; do
        echo "  - ${t}"
    done
}

# 1. Xử lý tham số dòng lệnh
TEMPLATE_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--template)
            TEMPLATE_NAME="${2:-}"
            shift 2 || true
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [[ -z "${TEMPLATE_NAME}" ]]; then
                TEMPLATE_NAME="$1"
            fi
            shift
            ;;
    esac
done

# 2. Tự động phát hiện hoặc hiển thị menu chọn template nếu chưa chỉ định
AVAILABLE_TEMPLATES=()
mapfile -t AVAILABLE_TEMPLATES < <(find "${SCRIPT_DIR}/templates" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort || true)

if [[ ${#AVAILABLE_TEMPLATES[@]} -eq 0 ]]; then
    log_error "Không tìm thấy thư mục template nào trong ${SCRIPT_DIR}/templates."
    exit 1
fi

if [[ -z "${TEMPLATE_NAME}" ]]; then
    if [[ ${#AVAILABLE_TEMPLATES[@]} -eq 1 ]]; then
        TEMPLATE_NAME="${AVAILABLE_TEMPLATES[0]}"
        log_info "Tự động chọn template khả dụng duy nhất: ${TEMPLATE_NAME}"
    else
        log_banner "LỰA CHỌN HỆ ĐIỀU HÀNH CHO GOLDEN TEMPLATE (PACKER)"
        echo "Danh sách template hệ điều hành có sẵn:"
        for idx in "${!AVAILABLE_TEMPLATES[@]}"; do
            echo "  $((idx+1))) ${AVAILABLE_TEMPLATES[$idx]}"
        done
        echo "  0) Hủy và thoát"
        SEL_IDX=""
        if ! read -r -p "Vui lòng chọn hệ điều hành (0-${#AVAILABLE_TEMPLATES[@]}) [1]: " SEL_IDX; then
            echo ""
            exit 0
        fi
        SEL_IDX="${SEL_IDX%$'\r'}"
        SEL_IDX=${SEL_IDX:-1}
        if [[ "${SEL_IDX}" == "0" ]]; then
            log_info "Hủy thao tác tạo template."
            exit 0
        fi
        if ! [[ "${SEL_IDX}" =~ ^[0-9]+$ ]] || [ "${SEL_IDX}" -lt 1 ] || [ "${SEL_IDX}" -gt "${#AVAILABLE_TEMPLATES[@]}" ]; then
            log_error "Lựa chọn số thứ tự không hợp lệ."
            exit 1
        fi
        TEMPLATE_NAME="${AVAILABLE_TEMPLATES[$((SEL_IDX-1))]}"
    fi
fi

TEMPLATE_DIR="${SCRIPT_DIR}/templates/${TEMPLATE_NAME}"
if [[ ! -d "${TEMPLATE_DIR}" ]]; then
    log_warn "Thư mục template '${TEMPLATE_NAME}' không tồn tại trong packer/templates/."
    local default_os="ubuntu-24.04"
    if [[ -d "${SCRIPT_DIR}/templates/${default_os}" ]]; then
        log_info "Tự động sử dụng thư mục template mặc định: ${default_os}."
        echo "Nhấn [Enter] để đồng ý sử dụng [${default_os}] (hoặc nhập 'q' để hủy)..."
        local confirm=""
        read -r confirm || true
        confirm="${confirm%$'\r'}"
        if [[ "${confirm}" == "q" || "${confirm}" == "Q" ]]; then
            exit 0
        fi
        local original_name="${TEMPLATE_NAME}"
        TEMPLATE_NAME="${default_os}"
        TEMPLATE_DIR="${SCRIPT_DIR}/templates/${TEMPLATE_NAME}"
        PKRVARS="${TEMPLATE_DIR}/packer.pkrvars.hcl"

        # Tự động khởi tạo packer.pkrvars.hcl từ example nếu chưa tồn tại
        if [[ ! -f "${PKRVARS}" && -f "${PKRVARS}.example" ]]; then
            log_info "Khởi tạo tệp biến cấu hình từ ${PKRVARS}.example..."
            cp "${PKRVARS}.example" "${PKRVARS}"
        fi

        # Cung cấp tùy chọn đặt vm_name nếu người dùng đã nhập tên VM
        if [[ -n "${original_name}" && "${original_name}" != "${default_os}" && -f "${PKRVARS}" ]]; then
            echo "Bạn đã chỉ định tên: '${original_name}'."
            if confirm_action "Bạn có muốn đặt tên VM Template trên vCenter là '${original_name}' không?" "Y"; then
                sed -i -E "s/^\s*vm_name\s*=.*/vm_name                     = \"${original_name}\"/" "${PKRVARS}"
                log_success "Đã cập nhật vm_name thành '${original_name}' trong packer.pkrvars.hcl."
            fi
        fi
    else
        log_error "Không tìm thấy thư mục template nào khả dụng trong ${SCRIPT_DIR}/templates."
        exit 1
    fi
fi

PKRVARS="${TEMPLATE_DIR}/packer.pkrvars.hcl"

log_banner "ĐÓNG GÓI GOLDEN TEMPLATE (PACKER) - IN-MEMORY"
log_info "Hệ điều hành mục tiêu: ${TEMPLATE_NAME}"
log_info "Thư mục làm việc:      ${TEMPLATE_DIR}"

# Tự động khởi tạo packer.pkrvars.hcl từ example nếu chưa tồn tại
if [[ ! -f "${PKRVARS}" && -f "${PKRVARS}.example" ]]; then
    log_info "Khởi tạo tệp biến cấu hình từ ${PKRVARS}.example..."
    cp "${PKRVARS}.example" "${PKRVARS}"
fi

# Tự động khởi tạo user-data từ example nếu chưa tồn tại
if [[ ! -f "${TEMPLATE_DIR}/http/user-data" && -f "${TEMPLATE_DIR}/http/user-data.example" ]]; then
    log_info "Khởi tạo tệp user-data autoinstall từ example..."
    cp "${TEMPLATE_DIR}/http/user-data.example" "${TEMPLATE_DIR}/http/user-data"
fi

if [[ ! -f "${PKRVARS}" ]]; then
    log_error "Không tìm thấy tệp biến cấu hình: ${PKRVARS}"
    exit 1
fi

# Tự động đồng bộ thông số hạ tầng từ Terraform nếu có sẵn
sync_packer_vars_from_terraform() {
    local pkr_file="$1"
    local tmpl_dir
    tmpl_dir="$(dirname "${pkr_file}")"

    [[ ! -f "${pkr_file}" ]] && return 0

    local tf_file=""
    for candidate in "${REPO_ROOT}/terraform/profiles/generic-vms/terraform.tfvars" \
                     "${REPO_ROOT}/terraform/profiles/elastic-stack/terraform.tfvars"; do
        if [[ -f "${candidate}" ]]; then
            local test_server
            test_server=$(grep -E '^\s*vsphere_server\s*=' "${candidate}" | head -n 1 | cut -d'"' -f2 || true)
            if [[ -n "${test_server}" && "${test_server}" != *"<"*">"* ]]; then
                tf_file="${candidate}"
                break
            fi
        fi
    done

    [[ -z "${tf_file}" ]] && return 0

    local tf_server tf_user tf_dc tf_cluster tf_ds tf_net tf_ssh
    tf_server=$(grep -E '^\s*vsphere_server\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_user=$(grep -E '^\s*vsphere_user\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_dc=$(grep -E '^\s*vsphere_datacenter\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_cluster=$(grep -E '^\s*vsphere_cluster\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_ds=$(grep -E '^\s*vsphere_datastore\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_net=$(grep -E '^\s*vsphere_network\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)
    tf_ssh=$(grep -E '^\s*ssh_username\s*=' "${tf_file}" | head -n 1 | cut -d'"' -f2 || true)

    local updated=0
    if [[ -n "${tf_server}" && "${tf_server}" != *"<"*">"* ]] && grep -q -E 'vcenter_server\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${tf_server}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_user}" && "${tf_user}" != *"<"*">"* ]] && grep -q -E 'vcenter_user\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_user\s*=\s*\")[^\"]+(\")/\1${tf_user}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_dc}" && "${tf_dc}" != *"<"*">"* ]] && grep -q -E 'vcenter_datacenter\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_datacenter\s*=\s*\")[^\"]+(\")/\1${tf_dc}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_cluster}" && "${tf_cluster}" != *"<"*">"* ]] && grep -q -E 'vcenter_cluster\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_cluster\s*=\s*\")[^\"]+(\")/\1${tf_cluster}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_ds}" && "${tf_ds}" != *"<"*">"* ]] && grep -q -E 'vcenter_datastore\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${tf_ds}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_net}" && "${tf_net}" != *"<"*">"* ]] && grep -q -E 'vcenter_network\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_network\s*=\s*\")[^\"]+(\")/\1${tf_net}\2/" "${pkr_file}"
        updated=1
    fi
    if [[ -n "${tf_ssh}" && "${tf_ssh}" != *"<"*">"* ]] && grep -q -E 'ssh_username\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${tf_ssh}\2/" "${pkr_file}"
        updated=1
    fi

    local user_data="${tmpl_dir}/http/user-data"
    if [[ -f "${user_data}" && -n "${tf_ssh}" && "${tf_ssh}" != *"<"*">"* ]]; then
        sed -i "s/<SSH_USER>/${tf_ssh}/g" "${user_data}"
    fi

    if [[ ${updated} -eq 1 ]]; then
        log_success "Đã tự động đồng bộ thông số hạ tầng từ Terraform sang Packer (${pkr_file})."
    fi
}
sync_packer_vars_from_terraform "${PKRVARS}"

# 3. Kiểm tra liên tục các thông số chưa điền (placeholder) trong packer.pkrvars.hcl
while true; do
    placeholders=()
    mapfile -t placeholders < <(grep -v '^\s*#' "${PKRVARS}" | grep -o -E '<[A-Z0-9_]+>' | sort -u || true)
    
    if [[ ${#placeholders[@]} -gt 0 ]]; then
        echo ""
        log_warn "Tệp ${PKRVARS} vẫn còn các trường thông số mẫu chưa được điền:"
        for p in "${placeholders[@]}"; do
            echo "  - ${p}"
        done
        echo ""
        echo "Vui lòng mở tệp sau để cập nhật thông số hạ tầng thực tế:"
        echo "  ${PKRVARS}"
        echo ""
        echo "Hướng dẫn:"
        echo "  - Mở tệp trên trong trình soạn thảo, hoàn thiện thông số và lưu lại."
        echo "  - Quay lại terminal này và nhấn [Enter] để hệ thống kiểm tra lại."
        echo "  - Nhập 'q' hoặc '0' và nhấn [Enter] nếu muốn hủy và quay lại menu."
        echo ""
        WAIT_INPUT=""
        if ! read -r -p "Nhấn Enter để kiểm tra lại (hoặc 'q' để hủy): " WAIT_INPUT; then
            echo ""
            exit 0
        fi
        WAIT_INPUT="${WAIT_INPUT%$'\r'}"
        if [[ "${WAIT_INPUT}" == "q" || "${WAIT_INPUT}" == "Q" || "${WAIT_INPUT}" == "0" ]]; then
            log_info "Hủy tiến trình theo yêu cầu của người dùng."
            exit 0
        fi
    else
        log_success "Đã xác nhận cấu hình ${PKRVARS} hợp lệ (không còn biến placeholder)."
        break
    fi
done

# 4. Trích xuất thông số vCenter từ tệp cấu hình
VCENTER_SERVER=$(grep -E '^\s*vcenter_server\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2 || true)
VCENTER_USER=$(grep -E '^\s*vcenter_user\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2 || true)
VM_NAME=$(grep -E '^\s*vm_name\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2 || true)

log_info "Máy chủ vCenter: ${VCENTER_SERVER}"
log_info "Tài khoản:       ${VCENTER_USER}"
log_info "Tên VM Template: ${VM_NAME}"

# 5. Thu thập mật khẩu an toàn vào bộ nhớ RAM
if [[ -z "${VCENTER_PASS:-}" ]]; then
    prompt_password "VCENTER_PASS" "Nhập mật khẩu quản trị vCenter" || exit 1
fi

if [[ -z "${SSH_PASS:-}" ]]; then
    prompt_password "SSH_PASS" "Nhập mật khẩu SSH khởi tạo máy ảo" || exit 1
fi

export PKR_VAR_vcenter_password="${VCENTER_PASS}"
export PKR_VAR_ssh_password="${SSH_PASS}"
export_govc_env "${VCENTER_SERVER}" "${VCENTER_USER}" "${VCENTER_PASS}"

# Đồng bộ tài khoản và mật khẩu vào tệp user-data autoinstall nếu còn chứa placeholder
USER_DATA_PATH="${TEMPLATE_DIR}/http/user-data"
if [[ -f "${USER_DATA_PATH}" ]]; then
    if grep -q "CHANGE_ME_PASSWORD_HASH" "${USER_DATA_PATH}" || grep -q "<SSH_USER>" "${USER_DATA_PATH}"; then
        log_info "Đồng bộ tài khoản và mật khẩu mã hóa vào tệp user-data autoinstall..."
        SSH_TARGET_USER=$(grep -E '^\s*ssh_username\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2 || true)
        SSH_HASH=""
        if command -v openssl &>/dev/null; then
            SSH_HASH=$(openssl passwd -6 "${SSH_PASS}" 2>/dev/null || true)
        fi
        if [[ -z "${SSH_HASH}" ]]; then
            SSH_HASH=$(python3 -c "import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" "${SSH_PASS}" 2>/dev/null || true)
        fi
        if [[ -n "${SSH_HASH}" ]]; then
            sed -i -E "s|(password:\s*\").*(\")|\1${SSH_HASH}\2|" "${USER_DATA_PATH}"
        fi
        if [[ -n "${SSH_TARGET_USER}" && "${SSH_TARGET_USER}" != *"<"*">"* ]]; then
            sed -i -E "s/(username:\s*).*/\1${SSH_TARGET_USER}/" "${USER_DATA_PATH}"
            sed -i "s|<SSH_USER>|${SSH_TARGET_USER}|g" "${USER_DATA_PATH}"
        fi
        PUB_KEY=""
        if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
            PUB_KEY=$(cat "${HOME}/.ssh/id_ed25519.pub")
        elif [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then
            PUB_KEY=$(cat "${HOME}/.ssh/id_rsa.pub")
        fi
        if [[ -n "${PUB_KEY}" ]]; then
            sed -i "s|<SSH_PUB_KEY>|${PUB_KEY}|g" "${USER_DATA_PATH}"
        fi
        log_success "Đã chuẩn bị thông tin xác thực an toàn trong user-data autoinstall."
    fi
fi

# 5. Pre-flight Check và kiểm tra trùng lặp template trên vCenter
if command -v govc &>/dev/null; then
    log_info "Đang xác thực kết nối vCenter qua govc API..."
    if ! check_vsphere_connectivity; then
        log_error "Xác thực vCenter thất bại. Vui lòng kiểm tra lại thông tin đăng nhập hoặc mạng."
        exit 1
    fi
    log_success "Xác thực kết nối vCenter thành công."

    # Kiểm tra máy ảo / template đã tồn tại trên vCenter
    VM_PATH=$(govc find -type m -name "${VM_NAME}" 2>/dev/null | head -n 1 || true)
    if [[ -n "${VM_PATH}" ]]; then
        log_warn "Máy ảo / Template '${VM_NAME}' đã tồn tại trên vCenter tại: ${VM_PATH}"
        log_warn "Mặc định Packer sẽ gặp lỗi duplicate name nếu không xử lý."
        if confirm_action "Bạn có muốn xóa VM/Template cũ để đóng gói lại không?" "N"; then
            log_info "Đang xóa '${VM_PATH}' trên vCenter..."
            if govc vm.destroy "${VM_PATH}"; then
                log_success "Đã xóa VM cũ thành công."
            else
                log_warn "Lệnh xóa qua govc không thành công. Tiến trình Packer có thể gặp lỗi nếu trùng tên."
            fi
        else
            log_info "Dừng tiến trình. Vui lòng đổi tên 'vm_name' trong ${PKRVARS} để đóng gói bản mới."
            exit 0
        fi
    fi
fi

# 6. Kiểm tra cú pháp cấu hình Packer
log_info "Cài đặt plugin và kiểm tra tính hợp lệ của cấu hình Packer..."
(
    cd "${TEMPLATE_DIR}"
    packer init .
    packer validate -var-file="${PKRVARS}" .
)
log_success "Cấu hình Packer hợp lệ."

# 7. Xác nhận trước khi bắt đầu build
if ! confirm_action "Xác nhận bắt đầu đóng gói template '${TEMPLATE_NAME}' bằng Packer?" "Y"; then
    log_info "Hủy tiến trình theo yêu cầu của người dùng."
    exit 0
fi

# 8. Thực thi đóng gói template
log_banner "BẮT ĐẦU ĐÓNG GÓI GOLDEN TEMPLATE: ${TEMPLATE_NAME}"
(
    cd "${TEMPLATE_DIR}"
    packer build -var-file="${PKRVARS}" .
)
log_success "Hoàn tất đóng gói Golden Template: ${TEMPLATE_NAME}"
