#!/usr/bin/env bash
# ==============================================================================
# Zabbix Monitoring Configuration Scaffold Module
# ==============================================================================
[[ -n "${_ZABBIX_CONFIGURE_LOADED:-}" ]] && return 0
_ZABBIX_CONFIGURE_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"

PRODUCT_CONF="${PRODUCT_DIR}/product.conf"

init_zabbix_config_files() {
    if [[ ! -f "${PRODUCT_CONF}" && -f "${PRODUCT_CONF}.example" ]]; then
        cp "${PRODUCT_CONF}.example" "${PRODUCT_CONF}"
        log_info "Đã khởi tạo: ${PRODUCT_CONF}"
    fi
}

gather_zabbix_vars() {
    init_zabbix_config_files
    if [[ ! -f "${PRODUCT_CONF}" ]]; then
        log_error "Không tìm thấy tệp cấu hình: ${PRODUCT_CONF}"
        return 1
    fi

    # shellcheck source=/dev/null
    source "${PRODUCT_CONF}"

    log_banner "THIẾT LẬP THÔNG SỐ HẠ TẦNG ZABBIX"
    prompt_if_placeholder "SITE_VCSA_IP" "Nhập IP của vCenter Server" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "VCENTER_USER" "Nhập tài khoản đăng nhập vCenter" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "SSH_USER" "Nhập tài khoản SSH cho máy ảo Zabbix" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "IP_ZBX" "Nhập IP tĩnh cho Zabbix Server" "${PRODUCT_CONF}" || return 1

    prompt_password "VCENTER_PASS" "Mật khẩu quản trị vCenter" || return 1
    prompt_password "SSH_PASS" "Mật khẩu SSH (${SSH_USER})" || return 1

    export VCENTER_PASS SSH_PASS
    export_govc_env "${SITE_VCSA_IP}" "${VCENTER_USER}" "${VCENTER_PASS}"
    return 0
}
