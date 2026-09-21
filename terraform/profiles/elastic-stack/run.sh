#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Terraform Provisioning Wrapper (Decentralized Component)
# - Run directly from inside terraform/profiles/elastic-stack directory: ./run.sh
# - Reads target topology directly from ./terraform.tfvars (Zero .env dependency)
# - Prompts for password interactively via masked input (read -s -p)
# - Stores credentials strictly in memory (RAM environment variables)
# - Validates vCenter connectivity via govc pre-flight check in < 1 second
# - Runs terraform apply with -parallelism=1 to eliminate ObjectStatus(0) panic
# - Guarantees ZERO passwords written to disk, auto-unsets variables on exit
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TFVARS="${SCRIPT_DIR}/terraform.tfvars"

# Nạp các thư viện dùng chung
# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
[[ -f "${REPO_ROOT}/lib/vsphere.sh" ]] && source "${REPO_ROOT}/lib/vsphere.sh"

trap cleanup_secrets EXIT INT TERM

log_banner "CẤP PHÁT HẠ TẦNG ELASTIC STACK (TERRAFORM - IN-MEMORY)"

if [[ ! -f "${TFVARS}" ]]; then
    log_error "Không tìm thấy tệp cấu hình tại: ${TFVARS}"
    exit 1
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
            exit 0
        fi
    else
        log_success "Đã xác nhận cấu hình ${TFVARS} hợp lệ (không còn biến placeholder)."
        break
    fi
done

# 2. Trích xuất thông số máy chủ trực tiếp từ terraform.tfvars
VSPHERE_SERVER=$(grep -E '^\s*vsphere_server\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2 || true)
VSPHERE_USER=$(grep -E '^\s*vsphere_user\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2 || true)

log_info "Máy chủ vCenter: ${VSPHERE_SERVER}"
log_info "Tài khoản:       ${VSPHERE_USER}"

# 3. Nhập mật khẩu ẩn từ terminal (Hỗ trợ lưu trong RAM)
VSPHERE_PASSWORD="${VCENTER_PASS:-${VSPHERE_PASSWORD:-}}"

if [[ -n "${VSPHERE_PASSWORD:-}" ]]; then
    log_info "Mật khẩu vCenter đã được nạp từ biến môi trường."
else
    prompt_password "VSPHERE_PASSWORD" "Nhập mật khẩu vCenter" || exit 1
fi

# 3. Nạp biến môi trường vào bộ nhớ RAM
export TF_VAR_vsphere_password="${VSPHERE_PASSWORD}"
export_govc_env "${VSPHERE_SERVER}" "${VSPHERE_USER}" "${VSPHERE_PASSWORD}"

# 4. Kiểm tra trước (Pre-flight Validation) bằng govc
if command -v govc &>/dev/null; then
    log_info "Đang xác thực kết nối tới vCenter qua govc API..."
    if ! check_vsphere_connectivity; then
        log_error "Xác thực vCenter thất bại. Vui lòng kiểm tra lại mật khẩu hoặc kết nối mạng."
        exit 1
    fi
    log_success "Xác thực kết nối vCenter thành công."
fi

# 5. Extract additional variables for auto-import
VCENTER_DC=$(grep -E '^\s*vsphere_datacenter\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)
VM_FOLDER=$(grep -E '^\s*vm_target_folder\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)

cd "${SCRIPT_DIR}"

echo ""
echo "=============================================================================="
echo "Khoi chay Terraform init..."
echo "=============================================================================="
terraform init
echo ""
echo "=============================================================================="
echo "Khoi chay Terraform apply (che do an toan -parallelism=1)..."
echo "=============================================================================="
terraform apply -parallelism=1
