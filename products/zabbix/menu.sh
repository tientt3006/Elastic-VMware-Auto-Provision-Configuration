#!/usr/bin/env bash
# ==============================================================================
# Zabbix Monitoring Product Menu Orchestrator
# ==============================================================================
[[ -n "${_ZABBIX_MENU_LOADED:-}" ]] && return 0
_ZABBIX_MENU_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=products/zabbix/configure.sh
source "${PRODUCT_DIR}/configure.sh"

run_zabbix_menu() {
    init_zabbix_config_files

    while true; do
        echo ""
        echo "=============================================================================="
        echo "TRIỂN KHAI ZABBIX MONITORING - MENU ĐIỀU PHỐI SẢN PHẨM"
        echo "=============================================================================="
        echo "1) Khởi tạo hạ tầng ảo hóa (Terraform - Profile generic-vms)"
        echo "2) Cấu hình Zabbix Server & Frontend (Ansible Playbook)"
        echo "3) Kiểm tra trạng thái máy chủ Zabbix"
        echo "4) Cấu hình tham số sản phẩm (product.conf)"
        echo "0) Quay lại menu chính"
        if ! read -r -p "Vui lòng chọn (0-4) [1]: " ZBX_CHOICE; then
            echo ""
            return 0
        fi
        ZBX_CHOICE="${ZBX_CHOICE%$'\r'}"
        ZBX_CHOICE=${ZBX_CHOICE:-1}

        case "${ZBX_CHOICE}" in
            1)
                log_info "Điều hướng tới profile cấp phát hạ tầng generic-vms..."
                (cd "${REPO_ROOT}/terraform/profiles/generic-vms" && ./run.sh)
                ;;
            2)
                log_banner "CẤU HÌNH DỊCH VỤ ZABBIX SERVER (ANSIBLE)"
                local pb="${REPO_ROOT}/ansible/products/zabbix/playbooks/deploy_stack.yml"
                if [[ -f "${pb}" ]]; then
                    log_info "Khởi chạy playbook: ${pb}..."
                    (cd "${REPO_ROOT}/ansible" && ansible-playbook -i "products/zabbix/inventories/lab/hosts.yml" "${pb}") || true
                else
                    log_warn "Playbook Zabbix đang trong giai đoạn hoàn thiện role chi tiết."
                fi
                ;;
            3)
                log_banner "KIỂM TRA TRẠNG THÁI MÁY CHỦ ZABBIX"
                if [[ -f "${PRODUCT_DIR}/product.conf" ]]; then
                    local zbx_ip
                    zbx_ip=$(grep -E '^\s*IP_ZBX=' "${PRODUCT_DIR}/product.conf" | cut -d'"' -f2 || true)
                    if [[ -n "${zbx_ip}" && "${zbx_ip}" != *"<"*">"* ]]; then
                        log_info "Kiểm tra kết nối mạng tới ${zbx_ip}..."
                        ping -c 2 "${zbx_ip}" || log_warn "Không thể ping tới ${zbx_ip}."
                    else
                        log_warn "Địa chỉ IP Zabbix chưa được cấu hình trong product.conf."
                    fi
                fi
                ;;
            4)
                gather_zabbix_vars || log_warn "Quá trình nhập thông số chưa hoàn tất."
                ;;
            0)
                log_info "Quay lại menu chính."
                return 0
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done
}
