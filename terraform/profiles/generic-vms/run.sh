#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Terraform Provisioning Wrapper (Generic VMs Profile)
# - Run directly from inside terraform/profiles/generic-vms: ./run.sh
# - Reads target topology directly from ./terraform.tfvars
# - Prompts for password interactively via masked input (RAM only)
# - Validates vCenter connectivity via govc API pre-flight check
# - Runs terraform apply with -parallelism=1 to prevent vCenter concurrency issues
# - Automatically clears in-memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TFVARS="${SCRIPT_DIR}/terraform.tfvars"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
[[ -f "${REPO_ROOT}/lib/vsphere.sh" ]] && source "${REPO_ROOT}/lib/vsphere.sh"

trap cleanup_secrets EXIT INT TERM

log_banner "CẤP PHÁT HẠ TẦNG TÙY CHỈNH (TERRAFORM - GENERIC VMS)"

# Tự động khởi tạo terraform.tfvars từ example nếu chưa tồn tại
if [[ ! -f "${TFVARS}" ]]; then
    if [[ -f "${TFVARS}.example" ]]; then
        log_info "Không tìm thấy ${TFVARS}. Khởi tạo từ tệp mẫu .example..."
        cp "${TFVARS}.example" "${TFVARS}"
        log_warn "Vui lòng kiểm tra và điền thông số hạ tầng trong: ${TFVARS}"
    else
        log_error "Không tìm thấy tệp cấu hình: ${TFVARS}"
        exit 1
    fi
fi

# 1. Kiểm tra liên tục các thông số chưa điền (placeholder) trong terraform.tfvars
while true; do
    placeholders=()
    mapfile -t placeholders < <(grep -v '^\s*#' "${TFVARS}" | grep -o -E '<[A-Z0-9_]+>' | sort -u || true)
    
    if [[ ${#placeholders[@]} -gt 0 ]]; then
        echo ""
        log_warn "Tệp ${TFVARS} vẫn còn các trường thông số mẫu chưa được điền:"
        for p in "${placeholders[@]}"; do
            echo "  - ${p}"
        done
        echo ""
        echo "Vui lòng mở tệp sau để cập nhật thông số hạ tầng thực tế:"
        echo "  ${TFVARS}"
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
            exit 1
        fi
    else
        log_success "Đã xác nhận cấu hình ${TFVARS} hợp lệ (không còn biến placeholder)."
        break
    fi
done

# 2. Trích xuất thông số vCenter từ terraform.tfvars
VSPHERE_SERVER=$(grep -E '^\s*vsphere_server\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2 || true)
VSPHERE_USER=$(grep -E '^\s*vsphere_user\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2 || true)

log_info "Máy chủ vCenter: ${VSPHERE_SERVER}"
log_info "Tài khoản:       ${VSPHERE_USER}"

# 3. Thu thập mật khẩu vCenter vào bộ nhớ RAM
VSPHERE_PASSWORD="${VCENTER_PASS:-${VSPHERE_PASSWORD:-}}"
if [[ -z "${VSPHERE_PASSWORD}" ]]; then
    prompt_password "VSPHERE_PASSWORD" "Nhập mật khẩu vCenter" || exit 1
fi

export TF_VAR_vsphere_password="${VSPHERE_PASSWORD}"
export_govc_env "${VSPHERE_SERVER}" "${VSPHERE_USER}" "${VSPHERE_PASSWORD}"

# 4. Pre-flight check kiểm tra kết nối vCenter
if command -v govc &>/dev/null; then
    log_info "Đang kiểm tra kết nối tới vCenter qua govc API..."
    if ! check_vsphere_connectivity; then
        log_error "Xác thực vCenter thất bại. Vui lòng kiểm tra lại mật khẩu hoặc mạng."
        exit 1
    fi
    log_success "Xác thực kết nối vCenter thành công."
fi

cd "${SCRIPT_DIR}"

log_banner "KHỞI CHẠY TERRAFORM INIT"
terraform init

log_banner "KHỞI CHẠY TERRAFORM APPLY (-parallelism=1)"
terraform apply -parallelism=1
log_success "Hoàn tất cấp phát hạ tầng tùy chỉnh (generic-vms)."
