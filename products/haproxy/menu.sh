#!/usr/bin/env bash
# ==============================================================================
# HAProxy Load Balancer Product Menu Orchestrator
# ==============================================================================
[[ -n "${_HAPROXY_MENU_LOADED:-}" ]] && return 0
_HAPROXY_MENU_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=products/haproxy/configure.sh
source "${PRODUCT_DIR}/configure.sh"

run_haproxy_menu() {
    init_haproxy_config_files

    while true; do
        echo ""
        echo "=============================================================================="
        echo "TRIỂN KHAI HAPROXY & KEEPALIVED - MENU ĐIỀU PHỐI SẢN PHẨM"
        echo "=============================================================================="
        echo "1) Khởi tạo hạ tầng ảo hóa (Terraform - Profile generic-vms)"
        echo "2) Cấu hình HAProxy & Keepalived VIP (Ansible Playbook)"
        echo "3) Kiểm tra trạng thái cụm cân bằng tải (Virtual IP)"
        echo "4) Cấu hình tham số sản phẩm (product.conf)"
        echo "0) Quay lại menu chính"
        if ! read -r -p "Vui lòng chọn (0-4) [1]: " HA_CHOICE; then
            echo ""
            return 0
        fi
        HA_CHOICE="${HA_CHOICE%$'\r'}"
        HA_CHOICE=${HA_CHOICE:-1}

        case "${HA_CHOICE}" in
            1)
                log_info "Điều hướng tới profile cấp phát hạ tầng generic-vms..."
                (cd "${REPO_ROOT}/terraform/profiles/generic-vms" && ./run.sh)
                ;;
            2)
                log_banner "CẤU HÌNH CỤM HAPROXY (ANSIBLE)"
                local pb="${REPO_ROOT}/ansible/products/haproxy/playbooks/deploy_stack.yml"
                if [[ -f "${pb}" ]]; then
                    log_info "Khởi chạy playbook: ${pb}..."
                    (cd "${REPO_ROOT}/ansible" && ansible-playbook -i "products/haproxy/inventories/lab/hosts.yml" "${pb}") || true
                else
                    log_warn "Playbook HAProxy đang trong giai đoạn hoàn thiện role chi tiết."
                fi
                ;;
            3)
                log_banner "KIỂM TRA TRẠNG THÁI CỤM HAPROXY"
                if [[ -f "${PRODUCT_DIR}/product.conf" ]]; then
                    local vip
                    vip=$(grep -E '^\s*VIP_HAPROXY=' "${PRODUCT_DIR}/product.conf" | cut -d'"' -f2 || true)
                    if [[ -n "${vip}" && "${vip}" != *"<"*">"* ]]; then
                        log_info "Kiểm tra kết nối tới Virtual IP: ${vip}..."
                        ping -c 2 "${vip}" || log_warn "Không thể ping tới ${vip}."
                    else
                        log_warn "Địa chỉ VIP chưa được cấu hình trong product.conf."
                    fi
                fi
                ;;
            4)
                gather_haproxy_vars || log_warn "Quá trình nhập thông số chưa hoàn tất."
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
