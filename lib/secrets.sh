#!/usr/bin/env bash
# ==============================================================================
# In-Memory Secrets and Credential Governance Module
# ==============================================================================
[[ -n "${_LIB_SECRETS_LOADED:-}" ]] && return 0
_LIB_SECRETS_LOADED=1

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_LIB_DIR}/common.sh"

gather_vcenter_credentials() {
    local default_server="${1:-}"
    local default_user="${2:-}"

    log_banner "XÁC THỰC VCENTER SERVER (IN-MEMORY)"
    [[ -n "${default_server}" ]] && echo "Máy chủ vCenter: ${default_server}"
    [[ -n "${default_user}" ]] && echo "Tài khoản:       ${default_user}"

    prompt_password "VCENTER_PASS" "Mật khẩu quản trị vCenter"
    export VCENTER_PASS
    export VSPHERE_PASSWORD="${VCENTER_PASS}"
    export TF_VAR_vsphere_password="${VCENTER_PASS}"
    export PKR_VAR_vcenter_password="${VCENTER_PASS}"

    if [[ -n "${default_server}" && -n "${default_user}" ]]; then
        export_govc_env "${default_server}" "${default_user}" "${VCENTER_PASS}"
    fi
}

gather_ssh_credentials() {
    local ssh_user="${1:-}"
    local prompt_suffix=""
    [[ -n "${ssh_user}" ]] && prompt_suffix=" (${ssh_user})"

    log_banner "XÁC THỰC MÁY ẢO LINUX (IN-MEMORY)"
    prompt_password "SSH_PASS" "Mật khẩu SSH${prompt_suffix}"
    prompt_password "SUDO_PASS" "Mật khẩu Sudo (đặc quyền root)"

    export SSH_PASS SUDO_PASS
    export PKR_VAR_ssh_password="${SSH_PASS}"
}

export_govc_env() {
    local server="$1"
    local user="$2"
    local pass="$3"

    # Chuẩn hóa URL vCenter (loại bỏ https:// nếu đã có để tránh lặp)
    local clean_server="${server#https://}"
    clean_server="${clean_server%/}"

    export GOVC_URL="https://${clean_server}"
    export GOVC_USERNAME="${user}"
    export GOVC_PASSWORD="${pass}"
    export GOVC_INSECURE="1"
}

cleanup_secrets() {
    echo ""
    log_info "Xóa thông tin bí mật và mật khẩu khỏi bộ nhớ RAM..."
    unset VCENTER_PASS || true
    unset VSPHERE_PASSWORD || true
    unset TF_VAR_vsphere_password || true
    unset PKR_VAR_vcenter_password || true
    unset PKR_VAR_ssh_password || true
    unset SSH_PASS || true
    unset SUDO_PASS || true
    unset ELASTIC_PASS || true
    unset KIBANA_PASS || true
    unset GOVC_PASSWORD || true
    unset ESXI_PASS || true
    log_success "Hoàn tất giải phóng bộ nhớ RAM."
}
