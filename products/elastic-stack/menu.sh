#!/usr/bin/env bash
# ==============================================================================
# Elastic Stack Product Orchestration Menu
# ==============================================================================
[[ -n "${_ELASTIC_MENU_LOADED:-}" ]] && return 0
_ELASTIC_MENU_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=products/elastic-stack/configure.sh
source "${PRODUCT_DIR}/configure.sh"

run_elastic_packer() {
    log_banner "TIẾN TRÌNH: ĐÓNG GÓI GOLDEN TEMPLATE (PACKER)"

    local current_iso=""
    if [[ -f "${PKR_FILE}" ]]; then
        current_iso=$(grep -A 2 -E '^\s*iso_paths\s*=' "${PKR_FILE}" | grep -E '"[^"]+"' | head -n 1 | sed -E 's/^\s*"([^"]+)".*/\1/' || true)
    fi

    local need_iso=0
    if [[ -z "${current_iso}" || "${current_iso}" == *"<"*">"* ]]; then
        need_iso=1
    else
        echo ""
        echo "Cấu hình tệp ISO hiện tại: ${current_iso}"
        if confirm_action "Xác nhận thay đổi cấu hình tệp ISO này?" "N"; then
            need_iso=1
        fi
    fi

    if [[ ${need_iso} -eq 1 ]]; then
        if ! run_iso_menu "${ISO_DATASTORE}" "${PKR_FILE}" "${PRODUCT_CONF}" "${REPO_ROOT}/seed"; then
            local check_iso=""
            if [[ -f "${PKR_FILE}" ]]; then
                check_iso=$(grep -A 2 -E '^\s*iso_paths\s*=' "${PKR_FILE}" | grep -E '"[^"]+"' | head -n 1 | sed -E 's/^\s*"([^"]+)".*/\1/' || true)
            fi
            if [[ -z "${check_iso}" || "${check_iso}" == *"<"*">"* ]]; then
                log_error "Chưa thiết lập tệp ISO hợp lệ. Dừng quy trình đóng gói Packer."
                return 1
            fi
            if ! confirm_action "Bạn đã hủy thay đổi ISO. Tiếp tục đóng gói với ISO hiện tại [${check_iso}]?" "N"; then
                log_info "Đã hủy đóng gói template theo yêu cầu."
                return 1
            fi
        fi
    fi

    local template_name
    template_name=$(grep -E '^\s*vm_name\s*=' "${PKR_FILE}" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
    if [[ -z "${template_name}" && -f "${PRODUCT_CONF}" ]]; then
        template_name=$(grep -E '^\s*TPL_NAME\s*=' "${PRODUCT_CONF}" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
    fi
    [[ -z "${template_name}" ]] && template_name="ubuntu-24.04"

    if ! confirm_action "Xác nhận bắt đầu đóng gói VM Template '${template_name}' (ubuntu-24.04)?" "Y"; then
        log_info "Đã hủy tiến trình Packer theo yêu cầu."
        return 1
    fi

    if ! (cd "${REPO_ROOT}/packer" && ./build.sh --template ubuntu-24.04); then
        log_warn "Tiến trình đóng gói Packer không thành công hoặc bị hủy."
        return 1
    fi

    # Đồng bộ tên template sang Terraform
    if [[ -z "${template_name}" || "${template_name}" == "ubuntu-24.04" ]]; then
        template_name=$(grep -E '^\s*vm_name\s*=' "${PKR_FILE}" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
    fi
    if [[ -n "${template_name}" && -f "${TF_FILE}" ]]; then
        sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${template_name}\2/" "${TF_FILE}"
        sed -i -E "s/(content_library_item_name\s*=\s*\")[^\"]+(\")/\1${template_name}\2/" "${TF_FILE}"
        log_success "Đã đồng bộ tên template '${template_name}' sang cấu hình Terraform."
    fi
    return 0
}

run_elastic_terraform() {
    log_banner "PRE-FLIGHT CHECK: KIỂM TRA TEMPLATE TRƯỚC KHI CẤP PHÁT (TERRAFORM)"

    local current_tpl
    current_tpl=$(grep -E '^\s*vsphere_template_name\s*=' "${TF_FILE}" | head -n 1 | cut -d'"' -f2 || true)
    if ! check_vsphere_template "${current_tpl}"; then
        log_warn "Không tìm thấy template '${current_tpl}' trên vCenter."
        if ! confirm_action "Tiếp tục chạy Terraform mà không cần kiểm tra template?" "N"; then
            log_info "Đã hủy chạy Terraform theo yêu cầu."
            return 1
        fi
    fi

    log_banner "PRE-FLIGHT CHECK: KIỂM TRA FILE CẤU HÌNH (TERRAFORM)"
    if grep -v '^\s*#' "${TF_FILE}" | grep -q -E '<[A-Z0-9_]+>'; then
        log_warn "Tệp ${TF_FILE} vẫn còn chứa biến chưa được gán giá trị (ví dụ: <ESXI_HOST_01>)."
        echo "Vui lòng mở tệp terraform/profiles/elastic-stack/terraform.tfvars để hoàn thiện thông số vật lý nếu cần."
        read -r -p "Nhấn Enter để tiếp tục chạy Terraform sau khi kiểm tra xong..." || true
    else
        log_success "Cấu hình Terraform hợp lệ, không còn chuỗi <PLACEHOLDER>."
    fi

    log_banner "TIẾN TRÌNH: KHỞI TẠO HẠ TẦNG VSPHERE (TERRAFORM)"
    if ! (cd "${REPO_ROOT}/terraform/profiles/elastic-stack" && ./run.sh); then
        log_warn "Tiến trình Terraform không thành công hoặc bị hủy."
        return 1
    fi
    return 0
}

run_elastic_ansible() {
    log_banner "PRE-FLIGHT CHECK: KIỂM TRA KẾT NỐI MÁY ẢO TRƯỚC KHI CẤU HÌNH (ANSIBLE)"

    local all_ips=("${IP_E01}" "${IP_E02}" "${IP_E03}" "${IP_KBN}")
    local failed_ips=0
    for ip in "${all_ips[@]}"; do
        if ! ping -c 1 -W 2 "${ip}" &> /dev/null; then
            log_warn "Máy ảo tại địa chỉ ${ip} chưa phản hồi ping."
            failed_ips=$((failed_ips + 1))
        fi
    done

    if [[ ${failed_ips} -gt 0 ]]; then
        log_warn "Một số máy ảo chưa sẵn sàng phản hồi mạng."
        if ! confirm_action "Vẫn tiếp tục thực thi Ansible?" "N"; then
            log_info "Đã hủy chạy Ansible theo yêu cầu."
            return 1
        fi
    else
        log_success "Toàn bộ 4 máy ảo mục tiêu đều có thể kết nối mạng (Ping OK)."
    fi

    log_banner "TIẾN TRÌNH: CẤU HÌNH CỤM ELASTICSEARCH VÀ KIBANA (ANSIBLE)"
    if ! (cd "${REPO_ROOT}/ansible/products/elastic-stack" && ./run_deploy.sh); then
        log_warn "Tiến trình cấu hình Ansible không thành công hoặc bị hủy."
        return 1
    fi

    log_banner "TIẾN TRÌNH: KÍCH HOẠT QUAN SÁT TẬP TRUNG (OBSERVABILITY)"
    if ! (cd "${REPO_ROOT}/ansible/products/elastic-stack" && ./run_observability.sh); then
        log_warn "Tiến trình thiết lập Observability không thành công hoặc bị hủy."
        return 1
    fi
    return 0
}

run_elastic_vsphere_observability() {
    log_banner "TIẾN TRÌNH: TÍCH HỢP GIÁM SÁT HẠ TẦNG VMWARE VSPHERE"
    if ! confirm_action "Xác nhận kích hoạt tích hợp giám sát vCenter & ESXi Host?" "Y"; then
        log_info "Đã bỏ qua tích hợp giám sát VMware vSphere."
        return 1
    fi

    "${PRODUCT_DIR}/scripts/manage_vsphere_observability.sh" apply
}

run_elastic_vsphere_rollback() {
    log_banner "TIẾN TRÌNH: HOÀN TÁC GIÁM SÁT HẠ TẦNG VMWARE VSPHERE (ROLLBACK)"
    if ! confirm_action "Xác nhận gỡ bỏ tích hợp giám sát vSphere?" "N"; then
        log_info "Hủy thao tác hoàn tác giám sát."
        return 1
    fi

    "${PRODUCT_DIR}/scripts/manage_vsphere_observability.sh" rollback
}

ensure_elastic_configured() {
    init_elastic_config_files
    if [[ -z "${VCENTER_PASS:-}" || -z "${SSH_PASS:-}" ]]; then
        log_info "Kiểm tra và chuẩn bị thông số cấu hình Elastic Stack..."
        if ! gather_elastic_vars; then
            log_error "Chưa hoàn tất thu thập thông số cấu hình Elastic Stack."
            return 1
        fi
        configure_elastic_templates
    fi
    return 0
}

run_elastic_menu() {
    init_elastic_config_files

    while true; do
        echo ""
        echo "=============================================================================="
        echo "TRIỂN KHAI ELASTIC STACK - MENU ĐIỀU PHỐI SẢN PHẨM"
        echo "=============================================================================="
        echo "1) Chạy toàn bộ quy trình (Đầu - Cuối: Packer -> Terraform -> Ansible -> Observability)"
        echo "2) Chỉ tạo Golden Template (Packer)"
        echo "3) Chỉ cấp phát hạ tầng (Terraform Provisioning)"
        echo "4) Chỉ cấu hình ứng dụng (Ansible Configuration)"
        echo "5) Tích hợp giám sát hạ tầng VMware vSphere"
        echo "6) Hoàn tác giám sát hạ tầng VMware vSphere"
        echo "7) Cấu hình tham số & đồng bộ các tệp cấu hình"
        echo "0) Quay lại / Thoát"
        if ! read -r -p "Vui lòng chọn (0-7) [1]: " ELASTIC_CHOICE; then
            echo ""
            return 0
        fi
        ELASTIC_CHOICE="${ELASTIC_CHOICE%$'\r'}"
        ELASTIC_CHOICE=${ELASTIC_CHOICE:-1}

        case "${ELASTIC_CHOICE}" in
            1)
                ensure_elastic_configured || continue
                if ! run_elastic_packer; then
                    log_warn "Tiến trình Packer bị dừng. Quay lại menu."
                    continue
                fi
                if ! run_elastic_terraform; then
                    log_warn "Tiến trình Terraform bị dừng. Quay lại menu."
                    continue
                fi
                if ! run_elastic_ansible; then
                    log_warn "Tiến trình Ansible bị dừng. Quay lại menu."
                    continue
                fi
                run_elastic_vsphere_observability || true
                log_success "HOÀN TẤT TOÀN BỘ QUY TRÌNH TRIỂN KHAI ELASTIC STACK."
                break
                ;;
            2)
                ensure_elastic_configured || continue
                if run_elastic_packer; then
                    log_success "HOÀN TẤT TIẾN TRÌNH TẠO TEMPLATE PACKER."
                fi
                ;;
            3)
                ensure_elastic_configured || continue
                if run_elastic_terraform; then
                    log_success "HOÀN TẤT TIẾN TRÌNH CẤP PHÁT HẠ TẦNG TERRAFORM."
                fi
                ;;
            4)
                ensure_elastic_configured || continue
                if run_elastic_ansible; then
                    log_success "HOÀN TẤT TIẾN TRÌNH CẤU HÌNH ANSIBLE."
                fi
                ;;
            5)
                ensure_elastic_configured || continue
                if run_elastic_vsphere_observability; then
                    log_success "HOÀN TẤT TÍCH HỢP GIÁM SÁT VSPHERE."
                fi
                ;;
            6)
                ensure_elastic_configured || continue
                if run_elastic_vsphere_rollback; then
                    log_success "HOÀN TẤT HOÀN TÁC GIÁM SÁT VSPHERE."
                fi
                ;;
            7)
                init_elastic_config_files force
                if gather_elastic_vars; then
                    configure_elastic_templates
                    log_success "Đã cập nhật và đồng bộ cấu hình Elastic Stack thành công."
                else
                    log_warn "Quá trình nhập thông số chưa hoàn tất."
                fi
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
