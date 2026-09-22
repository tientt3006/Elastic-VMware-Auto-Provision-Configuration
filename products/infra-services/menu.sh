#!/usr/bin/env bash
# ==============================================================================
# Infrastructure Services (DNS / NTP / DHCP) Product Menu Orchestrator
# ==============================================================================
[[ -n "${_INFRA_SERVICES_MENU_LOADED:-}" ]] && return 0
_INFRA_SERVICES_MENU_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT}/lib/common.sh" ]] && source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT}/lib/secrets.sh" ]] && source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=products/infra-services/configure.sh
source "${PRODUCT_DIR}/configure.sh"

run_infra_services_menu() {
    init_infra_services_config_files

    while true; do
        echo ""
        echo "=============================================================================="
        echo "DỊCH VỤ HẠ TẦNG (DNS/NTP/DHCP) - MENU ĐIỀU PHỐI SẢN PHẨM"
        echo "=============================================================================="
        echo "1) Khởi tạo hạ tầng ảo hóa (Terraform - Profile generic-vms)"
        echo "2) Cấu hình dịch vụ DNS & NTP Server (Ansible Playbook)"
        echo "3) Kiểm tra kết nối dịch vụ hạ tầng"
        echo "4) Cấu hình tham số sản phẩm (product.conf)"
        echo "0) Quay lại menu chính"
        if ! read -r -p "Vui lòng chọn (0-4) [1]: " INFRA_CHOICE; then
            echo ""
            return 0
        fi
        INFRA_CHOICE="${INFRA_CHOICE%$'\r'}"
        INFRA_CHOICE=${INFRA_CHOICE:-1}

        case "${INFRA_CHOICE}" in
            1)
                log_info "Điều hướng tới profile cấp phát hạ tầng generic-vms..."
                (cd "${REPO_ROOT}/terraform/profiles/generic-vms" && ./run.sh)
                ;;
            2)
                log_banner "CẤU HÌNH DỊCH VỤ HẠ TẦNG DNS/NTP (ANSIBLE)"
                local pb="${REPO_ROOT}/ansible/products/infra-services/playbooks/deploy_stack.yml"
                if [[ -f "${pb}" ]]; then
                    log_info "Khởi chạy playbook: ${pb}..."
                    (cd "${REPO_ROOT}/ansible" && ansible-playbook -i "products/infra-services/inventories/lab/hosts.yml" "${pb}") || true
                else
                    log_warn "Playbook Infra Services đang trong giai đoạn hoàn thiện role chi tiết."
                fi
                ;;
            3)
                log_banner "KIỂM TRA TRẠNG THÁI DỊCH VỤ HẠ TẦNG"
                if [[ -f "${PRODUCT_DIR}/product.conf" ]]; then
                    local infra_ip
                    infra_ip=$(grep -E '^\s*IP_INFRA_01=' "${PRODUCT_DIR}/product.conf" | cut -d'"' -f2 || true)
                    if [[ -n "${infra_ip}" && "${infra_ip}" != *"<"*">"* ]]; then
                        log_info "Kiểm tra kết nối tới: ${infra_ip}..."
                        ping -c 2 "${infra_ip}" || log_warn "Không thể ping tới ${infra_ip}."
                    else
                        log_warn "Địa chỉ IP chưa được cấu hình trong product.conf."
                    fi
                fi
                ;;
            4)
                gather_infra_services_vars || log_warn "Quá trình nhập thông số chưa hoàn tất."
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
