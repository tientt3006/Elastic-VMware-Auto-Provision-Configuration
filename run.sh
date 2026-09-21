#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator for VMware Multi-Product Automation Platform
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${REPO_ROOT}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Cấp quyền thực thi cho toàn bộ script
chmod +x "${REPO_ROOT}/packer/build.sh" \
         "${REPO_ROOT}/terraform/profiles/elastic-stack/run.sh" \
         "${REPO_ROOT}/ansible/products/elastic-stack/run_deploy.sh" \
         "${REPO_ROOT}/ansible/products/elastic-stack/run_observability.sh" \
         "${REPO_ROOT}/ansible/products/elastic-stack/run_backup.sh" \
         "${REPO_ROOT}/seed/download_iso.sh" \
         "${REPO_ROOT}/seed/upload_iso.sh" \
         "${REPO_ROOT}/seed/setup_env.sh" \
         "${REPO_ROOT}/seed/manage_vsphere_observability.sh" 2>/dev/null || true

# Nạp các thư viện dùng chung
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
source "${REPO_ROOT}/lib/vsphere.sh"

# Bảo vệ phiên thực thi bằng tmux chống gián đoạn SSH
init_tmux_session "platform_deploy" "${LOG_FILE}" "$@"

# Thiết lập bẫy dọn dẹp bộ nhớ RAM khi kết thúc
trap cleanup_secrets EXIT INT TERM

log_banner "HỆ THỐNG QUẢN LÝ HẠ TẦNG VMWARE - NỀN TẢNG TỰ ĐỘNG HÓA"
log_info "Nhật ký phiên thực thi: ${LOG_FILE}"

run_platform_tools_menu() {
    while true; do
        echo ""
        echo "=============================================================================="
        echo "CÔNG CỤ NỀN TẢNG (PLATFORM TOOLS)"
        echo "=============================================================================="
        echo "1) Tạo Golden Template (Packer)"
        echo "2) Cấp phát hạ tầng (Terraform Profile)"
        echo "3) Quản lý tệp ISO trên Datastore"
        echo "4) Cài đặt môi trường công cụ tự động hóa (Seed Setup)"
        echo "0) Quay lại menu chính"
        if ! read -r -p "Vui lòng chọn (0-4) [1]: " TOOL_CHOICE; then
            echo ""
            return 0
        fi
        TOOL_CHOICE="${TOOL_CHOICE%$'\r'}"
        TOOL_CHOICE=${TOOL_CHOICE:-1}

        case "${TOOL_CHOICE}" in
            1)
                log_banner "TẠO GOLDEN TEMPLATE (PACKER)"
                if ! read -r -p "Nhập tên template OS [ubuntu-24.04]: " OS_TEMPLATE; then
                    echo ""
                    return 0
                fi
                OS_TEMPLATE="${OS_TEMPLATE%$'\r'}"
                OS_TEMPLATE=${OS_TEMPLATE:-ubuntu-24.04}
                (cd "${REPO_ROOT}/packer" && ./build.sh --template "${OS_TEMPLATE}")
                ;;
            2)
                log_banner "CẤP PHÁT HẠ TẦNG (TERRAFORM)"
                local profiles=()
                mapfile -t profiles < <(find "${REPO_ROOT}/terraform/profiles" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
                if [[ ${#profiles[@]} -eq 0 ]]; then
                    log_warn "Không tìm thấy hồ sơ (profile) Terraform nào."
                    continue
                fi
                echo "Danh sách profile Terraform có sẵn:"
                for idx in "${!profiles[@]}"; do
                    echo "  $((idx+1))) ${profiles[$idx]}"
                done
                echo "  0) Quay lại"
                if ! read -r -p "Chọn số thứ tự profile muốn chạy (0-${#profiles[@]}): " PROF_IDX; then
                    echo ""
                    return 0
                fi
                PROF_IDX="${PROF_IDX%$'\r'}"
                if [[ "${PROF_IDX}" == "0" ]]; then
                    continue
                fi
                if ! [[ "${PROF_IDX}" =~ ^[0-9]+$ ]] || [ "${PROF_IDX}" -lt 1 ] || [ "${PROF_IDX}" -gt "${#profiles[@]}" ]; then
                    log_error "Lựa chọn không hợp lệ."
                    continue
                fi
                local selected_profile="${profiles[$((PROF_IDX-1))]}"
                log_info "Khởi chạy profile: ${selected_profile}..."
                (cd "${REPO_ROOT}/terraform/profiles/${selected_profile}" && ./run.sh)
                ;;
            3)
                log_banner "QUẢN LÝ TỆP ISO TRÊN DATASTORE"
                local default_ds=""
                if [[ -f "${REPO_ROOT}/products/elastic-stack/product.conf" ]]; then
                    default_ds=$(grep -E '^\s*ISO_DATASTORE=' "${REPO_ROOT}/products/elastic-stack/product.conf" | cut -d'"' -f2 || true)
                fi
                local ds_prompt="Nhập tên Datastore đích"
                [[ -n "${default_ds}" && "${default_ds}" != *"<"*">"* ]] && ds_prompt="${ds_prompt} [${default_ds}]"
                if ! read -r -p "${ds_prompt}: " TARGET_DS; then
                    echo ""
                    return 0
                fi
                TARGET_DS="${TARGET_DS%$'\r'}"
                TARGET_DS="${TARGET_DS:-${default_ds}}"
                if [[ -z "${TARGET_DS}" || "${TARGET_DS}" == *"<"*">"* ]]; then
                    log_error "Tên Datastore không được để trống hoặc chứa placeholder."
                    continue
                fi
                run_iso_menu "${TARGET_DS}" "${REPO_ROOT}/packer/templates/ubuntu-24.04/packer.pkrvars.hcl" "${REPO_ROOT}/products/elastic-stack/product.conf" "${REPO_ROOT}/seed"
                ;;
            4)
                log_banner "CÀI ĐẶT MÔI TRƯỜNG CÔNG CỤ (SEED SETUP)"
                if [[ -x "${REPO_ROOT}/seed/setup_env.sh" ]]; then
                    (cd "${REPO_ROOT}/seed" && sudo ./setup_env.sh)
                else
                    log_error "Không tìm thấy tệp thực thi seed/setup_env.sh."
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done
}

while true; do
    echo ""
    echo "=============================================================================="
    echo "HỆ THỐNG QUẢN LÝ HẠ TẦNG VMWARE - MENU ĐIỀU PHỐI TỔNG THỂ"
    echo "=============================================================================="
    echo "1) Công cụ nền tảng (Platform Tools: Packer, Terraform, ISO, Seed)"
    echo "2) Triển khai Elastic Stack (SIEM, Observability, Fleet HA)"
    echo "3) Triển khai Zabbix Server             [Dự kiến phát triển]"
    echo "4) Triển khai HAProxy / Load Balancer   [Dự kiến phát triển]"
    echo "5) Triển khai dịch vụ hạ tầng mạng     [Dự kiến phát triển]"
    echo "0) Thoát chương trình"
    if ! read -r -p "Vui lòng chọn (0-5) [2]: " TOP_CHOICE; then
        echo ""
        log_info "Nhận tín hiệu kết thúc đầu vào (EOF). Thoát chương trình."
        exit 0
    fi
    TOP_CHOICE="${TOP_CHOICE%$'\r'}"
    TOP_CHOICE=${TOP_CHOICE:-2}

    case "${TOP_CHOICE}" in
        1)
            run_platform_tools_menu
            ;;
        2)
            # Nạp và khởi chạy menu Elastic Stack
            # shellcheck source=products/elastic-stack/menu.sh
            source "${REPO_ROOT}/products/elastic-stack/menu.sh"
            run_elastic_menu
            ;;
        3)
            log_info "Tính năng triển khai Zabbix Server đang trong lộ trình phát triển."
            ;;
        4)
            log_info "Tính năng triển khai HAProxy đang trong lộ trình phát triển."
            ;;
        5)
            log_info "Tính năng triển khai dịch vụ hạ tầng mạng đang trong lộ trình phát triển."
            ;;
        0)
            log_info "Thoát chương trình."
            exit 0
            ;;
        *)
            log_warn "Lựa chọn không hợp lệ."
            ;;
    esac
done
