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
         "${REPO_ROOT}/products/elastic-stack/scripts/manage_vsphere_observability.sh" 2>/dev/null || true

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
        echo "3) Quản lý kho ISO & Content Library"
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
                local os_templates=()
                mapfile -t os_templates < <(find "${REPO_ROOT}/packer/templates" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort || true)
                local default_os="ubuntu-24.04"
                if [[ ${#os_templates[@]} -eq 0 ]]; then
                    log_error "Không tìm thấy thư mục template hệ điều hành nào trong packer/templates/."
                    continue
                fi

                local chosen_os=""
                if [[ ${#os_templates[@]} -eq 1 ]]; then
                    chosen_os="${os_templates[0]}"
                    echo "Hệ điều hành template khả dụng: ${chosen_os}"
                    local input_os=""
                    if ! read -r -p "Nhấn [Enter] để tiếp tục (hoặc nhập tên OS khác) [${chosen_os}]: " input_os; then
                        echo ""
                        return 0
                    fi
                    input_os="${input_os%$'\r'}"
                    chosen_os="${input_os:-${chosen_os}}"
                else
                    echo "Danh sách hệ điều hành (OS) hỗ trợ đóng gói template:"
                    for idx in "${!os_templates[@]}"; do
                        echo "  $((idx+1))) ${os_templates[$idx]}"
                    done
                    echo "  0) Hủy và quay lại"
                    local sel=""
                    if ! read -r -p "Vui lòng chọn hệ điều hành cần tạo template (0-${#os_templates[@]}) [${#os_templates[@]}]: " sel; then
                        echo ""
                        return 0
                    fi
                    sel="${sel%$'\r'}"
                    sel="${sel:-${#os_templates[@]}}"
                    if [[ "${sel}" == "0" || "${sel}" == "q" || "${sel}" == "Q" ]]; then
                        log_info "Hủy tạo template theo yêu cầu."
                        continue
                    fi
                    if ! [[ "${sel}" =~ ^[0-9]+$ ]] || [ "${sel}" -lt 1 ] || [ "${sel}" -gt "${#os_templates[@]}" ]; then
                        log_error "Lựa chọn không hợp lệ."
                        continue
                    fi
                    chosen_os="${os_templates[$((sel-1))]}"
                fi

                # Nếu người dùng nhập tên OS không tồn tại trong thư mục templates/:
                if [[ ! -d "${REPO_ROOT}/packer/templates/${chosen_os}" ]]; then
                    log_warn "Thư mục template '${chosen_os}' không tồn tại trong packer/templates/."
                    log_info "Tự động sử dụng thư mục hệ điều hành mặc định: ${default_os}."
                    echo "Nhấn [Enter] để đồng ý sử dụng [${default_os}] (hoặc nhập 'q' để hủy)..."
                    local confirm=""
                    if ! read -r confirm; then
                        echo ""
                        return 0
                    fi
                    confirm="${confirm%$'\r'}"
                    if [[ "${confirm}" == "q" || "${confirm}" == "Q" ]]; then
                        continue
                    fi
                    chosen_os="${default_os}"
                fi

                # Tự động khởi tạo tệp cấu hình nếu chưa có
                local pkr_file="${REPO_ROOT}/packer/templates/${chosen_os}/packer.pkrvars.hcl"
                [[ ! -f "${pkr_file}" && -f "${pkr_file}.example" ]] && cp "${pkr_file}.example" "${pkr_file}"

                # Xác định tên máy ảo VM Template sẽ hiển thị trên vCenter
                local current_vm_name="tpl-${chosen_os}-golden"
                if [[ -f "${pkr_file}" ]]; then
                    local v
                    v=$(grep -E '^\s*vm_name\s*=' "${pkr_file}" | head -n 1 | cut -d'"' -f2 || true)
                    [[ -n "${v}" && "${v}" != *"<"*">"* ]] && current_vm_name="${v}"
                fi

                echo ""
                echo "Thiết lập định danh máy ảo VM Template trên vCenter:"
                local input_vm_name=""
                if ! read -r -p "Nhập tên máy ảo trên vCenter [${current_vm_name}] (hoặc 'q' để hủy): " input_vm_name; then
                    echo ""
                    return 0
                fi
                input_vm_name="${input_vm_name%$'\r'}"
                if [[ "${input_vm_name}" == "q" || "${input_vm_name}" == "Q" ]]; then
                    log_info "Hủy tạo template theo yêu cầu."
                    continue
                fi
                input_vm_name="${input_vm_name:-${current_vm_name}}"

                if [[ -n "${input_vm_name}" && -f "${pkr_file}" ]]; then
                    sed -i -E "s/^\s*vm_name\s*=.*/vm_name                     = \"${input_vm_name}\"/" "${pkr_file}"
                    log_success "Đã lưu tên máy ảo VM Template: ${input_vm_name}"
                fi

                # Kiểm tra và thiết lập đường dẫn ISO cho Golden Template
                local current_iso=""
                if [[ -f "${pkr_file}" ]]; then
                    current_iso=$(grep -A 2 -E '^\s*iso_paths\s*=' "${pkr_file}" | grep -E '"[^"]+"' | head -n 1 | sed -E 's/^\s*"([^"]+)".*/\1/' || true)
                fi

                local default_ds=""
                if [[ -f "${pkr_file}" ]]; then
                    default_ds=$(grep -E '^\s*vcenter_datastore\s*=' "${pkr_file}" | head -n 1 | cut -d'"' -f2 || true)
                fi
                if [[ -z "${default_ds}" || "${default_ds}" == *"<"*">"* ]]; then
                    if [[ -f "${REPO_ROOT}/terraform/profiles/generic-vms/terraform.tfvars" ]]; then
                        default_ds=$(grep -E '^\s*vsphere_datastore\s*=' "${REPO_ROOT}/terraform/profiles/generic-vms/terraform.tfvars" | head -n 1 | cut -d'"' -f2 || true)
                    fi
                fi
                if [[ -z "${default_ds}" || "${default_ds}" == *"<"*">"* ]]; then
                    if [[ -f "${REPO_ROOT}/products/elastic-stack/product.conf" ]]; then
                        default_ds=$(grep -E '^\s*ISO_DATASTORE=' "${REPO_ROOT}/products/elastic-stack/product.conf" | cut -d'"' -f2 || true)
                    fi
                fi

                local need_select_iso=0
                if [[ -z "${current_iso}" || "${current_iso}" == *"<"*">"* ]]; then
                    need_select_iso=1
                else
                    echo ""
                    echo "Cấu hình tệp ISO hiện tại: ${current_iso}"
                    if [[ "${current_iso}" =~ ^\[([^]]+)\][[:space:]]*([^/]+)$ ]]; then
                        log_warn "Lưu ý: Tệp ISO đang trỏ trực tiếp vào thư mục gốc của Datastore [${BASH_REMATCH[1]}]."
                        log_warn "Nếu tệp thực tế nằm trong thư mục con (ví dụ: [${BASH_REMATCH[1]}] iso/${BASH_REMATCH[2]}), hãy chọn 'Y' để chọn lại."
                    fi
                    if confirm_action "Xác nhận thay đổi cấu hình tệp ISO này?" "N"; then
                        need_select_iso=1
                    fi
                fi

                if [[ ${need_select_iso} -eq 1 ]]; then
                    if ! run_iso_menu "${default_ds}" "${pkr_file}" "${REPO_ROOT}/products/elastic-stack/product.conf" "${REPO_ROOT}/seed"; then
                        local check_iso=""
                        if [[ -f "${pkr_file}" ]]; then
                            check_iso=$(grep -A 2 -E '^\s*iso_paths\s*=' "${pkr_file}" | grep -E '"[^"]+"' | head -n 1 | sed -E 's/^\s*"([^"]+)".*/\1/' || true)
                        fi
                        if [[ -z "${check_iso}" || "${check_iso}" == *"<"*">"* ]]; then
                            log_error "Chưa thiết lập tệp ISO hợp lệ. Dừng quy trình đóng gói template."
                            continue
                        fi
                        if ! confirm_action "Bạn đã hủy thay đổi ISO. Tiếp tục đóng gói với ISO hiện tại [${check_iso}]?" "N"; then
                            log_info "Đã hủy đóng gói template theo yêu cầu."
                            continue
                        fi
                    fi
                fi

                local tpl_name=""
                if [[ -f "${pkr_file}" ]]; then
                    tpl_name=$(grep -E '^\s*vm_name\s*=' "${pkr_file}" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
                fi
                [[ -z "${tpl_name}" ]] && tpl_name="${chosen_os}"

                if ! confirm_action "Xác nhận bắt đầu đóng gói VM Template '${tpl_name}' (Hệ điều hành: ${chosen_os})?" "Y"; then
                    log_info "Đã hủy đóng gói template theo yêu cầu."
                    continue
                fi

                log_info "Khởi chạy quy trình đóng gói Golden Template cho: ${chosen_os}..."
                if ! (cd "${REPO_ROOT}/packer" && ./build.sh --template "${chosen_os}"); then
                    log_warn "Tiến trình đóng gói Packer đã bị dừng hoặc không thành công."
                fi
                ;;
            2)
                log_banner "CẤP PHÁT HẠ TẦNG (TERRAFORM)"
                local profiles=()
                mapfile -t profiles < <(find "${REPO_ROOT}/terraform/profiles" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort || true)
                if [[ ${#profiles[@]} -eq 0 ]]; then
                    log_error "Không tìm thấy profile Terraform nào trong terraform/profiles/."
                    continue
                fi
                echo "Danh sách profile Terraform có sẵn:"
                for idx in "${!profiles[@]}"; do
                    echo "  $((idx+1))) ${profiles[$idx]}"
                done
                echo "  0) Quay lại"
                local PROF_IDX=""
                if ! read -r -p "Vui lòng chọn profile cần triển khai (0-${#profiles[@]}) [1]: " PROF_IDX; then
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
                if ! confirm_action "Xác nhận khởi chạy Terraform profile '${selected_profile}'?" "Y"; then
                    log_info "Đã hủy khởi chạy Terraform theo yêu cầu."
                    continue
                fi
                log_info "Khởi chạy profile: ${selected_profile}..."
                if ! (cd "${REPO_ROOT}/terraform/profiles/${selected_profile}" && ./run.sh); then
                    log_warn "Tiến trình Terraform đã bị dừng hoặc không thành công."
                fi
                ;;
            3)
                run_content_library_menu "${REPO_ROOT}/products/elastic-stack/product.conf"
                ;;
            4)
                log_banner "CÀI ĐẶT MÔI TRƯỜNG CÔNG CỤ (SEED SETUP)"
                if ! confirm_action "Xác nhận cài đặt môi trường công cụ tự động hóa (Seed Setup)?" "Y"; then
                    log_info "Đã hủy cài đặt môi trường theo yêu cầu."
                    continue
                fi
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
    echo "3) Triển khai Zabbix Server             [Khung mở rộng]"
    echo "4) Triển khai HAProxy / Load Balancer   [Khung mở rộng]"
    echo "5) Triển khai dịch vụ hạ tầng mạng     [Khung mở rộng]"
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
            # Nạp và khởi chạy menu Zabbix
            # shellcheck source=products/zabbix/menu.sh
            source "${REPO_ROOT}/products/zabbix/menu.sh"
            run_zabbix_menu
            ;;
        4)
            # Nạp và khởi chạy menu HAProxy
            # shellcheck source=products/haproxy/menu.sh
            source "${REPO_ROOT}/products/haproxy/menu.sh"
            run_haproxy_menu
            ;;
        5)
            # Nạp và khởi chạy menu Dịch vụ hạ tầng mạng
            # shellcheck source=products/infra-services/menu.sh
            source "${REPO_ROOT}/products/infra-services/menu.sh"
            run_infra_services_menu
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
