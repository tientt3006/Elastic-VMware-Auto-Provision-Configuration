#!/usr/bin/env bash
# ==============================================================================
# vSphere Infrastructure Interaction and ISO Management Module
# ==============================================================================
[[ -n "${_LIB_VSPHERE_LOADED:-}" ]] && return 0
_LIB_VSPHERE_LOADED=1

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_LIB_DIR}/common.sh"
# shellcheck source=lib/secrets.sh
source "${SCRIPT_LIB_DIR}/secrets.sh"

check_vsphere_connectivity() {
    if ! command -v govc &> /dev/null; then
        log_warn "govc chưa được cài đặt. Bỏ qua kiểm tra kết nối tự động."
        return 0
    fi

    log_info "Đang kiểm tra kết nối và xác thực vCenter qua govc API..."
    if govc about &> /dev/null; then
        log_success "Xác thực vCenter Server thành công."
        govc about
        return 0
    else
        log_error "Không thể xác thực tới vCenter Server. Vui lòng kiểm tra địa chỉ và mật khẩu."
        return 1
    fi
}

check_vsphere_template() {
    local template_name="$1"
    if ! command -v govc &> /dev/null; then
        log_warn "govc chưa được cài đặt, không thể tự động kiểm tra template '${template_name}'."
        return 0
    fi

    log_info "Đang tìm kiếm template '${template_name}' trên vCenter..."
    local found_path
    found_path=$(govc find -type m -name "${template_name}" 2>/dev/null | head -n 1 || true)
    if [[ -n "${found_path}" ]]; then
        log_success "Tìm thấy template hợp lệ: ${found_path}"
        return 0
    else
        log_warn "Không tìm thấy template '${template_name}' trên vCenter."
        return 1
    fi
}

upload_iso_to_datastore() {
    local datastore="$1"
    local local_path="$2"
    local remote_name="$3"

    if ! command -v govc &> /dev/null; then
        log_error "Lệnh govc không tồn tại. Không thể upload ISO lên Datastore."
        return 1
    fi

    if govc datastore.ls -ds="${datastore}" "${remote_name}" &> /dev/null; then
        log_info "Tệp ISO đã tồn tại trên Datastore [${datastore}]: ${remote_name}. Bỏ qua upload."
    else
        log_info "Đang chuẩn bị thư mục và tải tệp lên Datastore [${datastore}]..."
        local remote_dir
        remote_dir=$(dirname "${remote_name}")
        [[ "${remote_dir}" != "." && -n "${remote_dir}" ]] && govc datastore.mkdir -ds="${datastore}" "${remote_dir}" 2>/dev/null || true
        govc datastore.upload -ds="${datastore}" "${local_path}" "${remote_name}"
        log_success "Upload hoàn tất: [${datastore}] ${remote_name}"
    fi
}

update_iso_in_packer() {
    local pkr_file="$1"
    local datastore="$2"
    local iso_remote_path="$3"

    if [[ ! -f "${pkr_file}" ]]; then
        log_warn "Không tìm thấy file cấu hình Packer: ${pkr_file}"
        return 1
    fi

    # Cập nhật danh sách iso_paths trong file HCL/pkrvars
    if grep -q "^iso_paths" "${pkr_file}"; then
        sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "['"${datastore}"'] '"${iso_remote_path}"'"\
]' "${pkr_file}"
        log_success "Đã cập nhật iso_paths trong ${pkr_file} thành: [${datastore}] ${iso_remote_path}"
    else
        log_warn "Cấu trúc iso_paths không tìm thấy trong ${pkr_file} để cập nhật."
    fi
}

save_last_used_iso() {
    local config_file="$1"
    local iso_remote_name="$2"

    if [[ -f "${config_file}" ]]; then
        if ! grep -q "^LAST_USED_ISO=" "${config_file}"; then
            echo "LAST_USED_ISO=\"${iso_remote_name}\"" >> "${config_file}"
        else
            sed -i "s|^LAST_USED_ISO=.*|LAST_USED_ISO=\"${iso_remote_name}\"|" "${config_file}"
        fi
    fi
}

run_iso_menu() {
    local datastore="$1"
    local pkr_file="$2"
    local config_file="$3"
    local seed_dir="${4:-seed}"

    log_banner "QUẢN LÝ TỆP TIN ISO HỆ ĐIỀU HÀNH CHO PACKER"

    # Kiểm tra ISO đã lưu lần trước
    local last_iso=""
    if [[ -f "${config_file}" ]]; then
        last_iso=$(grep -E '^LAST_USED_ISO=' "${config_file}" | cut -d'"' -f2 || true)
    fi

    if [[ -n "${last_iso}" ]]; then
        log_info "Phát hiện tệp ISO đã dùng trong cấu hình gần nhất: ${last_iso}"
        if confirm_action "Tiếp tục sử dụng tệp ISO này trên Datastore [${datastore}]?" "Y"; then
            update_iso_in_packer "${pkr_file}" "${datastore}" "${last_iso}"
            return 0
        fi
    fi

    while true; do
        echo ""
        echo "Phương thức thiết lập ISO cài đặt hệ điều hành:"
        echo "  1) Tải ISO tự động từ Internet (Ubuntu 24.04 LTS Live Server) & upload lên Datastore"
        echo "  2) Chọn tệp ISO từ đĩa cục bộ & upload lên Datastore"
        echo "  3) Chọn tệp ISO đã có sẵn trên Datastore vCenter"
        echo "  0) Hủy và quay lại"
        if ! read -r -p "Nhập lựa chọn (0-3) [1]: " ISO_CHOICE; then
            echo ""
            return 1
        fi
        ISO_CHOICE="${ISO_CHOICE%$'\r'}"
        ISO_CHOICE=${ISO_CHOICE:-1}

        case "${ISO_CHOICE}" in
            0)
                log_info "Đã hủy thao tác chọn ISO."
                return 1
                ;;
            1)
                log_info "Bắt đầu tải ISO từ nguồn phát hành Ubuntu..."
                if [[ -x "${seed_dir}/download_iso.sh" ]]; then
                    (cd "${seed_dir}" && ./download_iso.sh --ubuntu)
                else
                    log_error "Không tìm thấy script ${seed_dir}/download_iso.sh."
                    return 1
                fi

                local iso_local="${seed_dir}/iso_cache/ubuntu-24.04.5-live-server-amd64.iso"
                if [[ ! -f "${iso_local}" ]]; then
                    # Kiểm tra thư mục ./iso_cache nếu download vào thư mục làm việc
                    if [[ -f "iso_cache/ubuntu-24.04.5-live-server-amd64.iso" ]]; then
                        iso_local="iso_cache/ubuntu-24.04.5-live-server-amd64.iso"
                    else
                        log_error "Tệp ISO không tồn tại sau khi tải: ${iso_local}"
                        return 1
                    fi
                fi

                local iso_remote="iso/ubuntu-24.04.5-live-server-amd64.iso"
                upload_iso_to_datastore "${datastore}" "${iso_local}" "${iso_remote}"
                update_iso_in_packer "${pkr_file}" "${datastore}" "${iso_remote}"
                save_last_used_iso "${config_file}" "${iso_remote}"
                break
                ;;
            2)
                if ! read -r -p "Nhập đường dẫn thư mục chứa ISO cục bộ (ví dụ: /mnt/d/ISO hoặc .): " LOCAL_DIR; then
                    echo ""
                    return 1
                fi
                LOCAL_DIR="${LOCAL_DIR%$'\r'}"
                if [[ ! -d "${LOCAL_DIR}" ]]; then
                    log_error "Thư mục '${LOCAL_DIR}' không tồn tại."
                    continue
                fi

                log_info "Đang quét các tệp .iso trong ${LOCAL_DIR}..."
                mapfile -t ISO_FILES < <(find "${LOCAL_DIR}" -maxdepth 2 -type f -name "*.iso")
                if [[ ${#ISO_FILES[@]} -eq 0 ]]; then
                    log_warn "Không tìm thấy tệp .iso nào trong ${LOCAL_DIR}."
                    continue
                fi

                echo "Danh sách tệp ISO tìm thấy:"
                for idx in "${!ISO_FILES[@]}"; do
                    echo "  $((idx+1))) ${ISO_FILES[$idx]}"
                done
                if ! read -r -p "Nhập số thứ tự tệp ISO muốn chọn: " SEL_INDEX; then
                    echo ""
                    return 1
                fi
                SEL_INDEX="${SEL_INDEX%$'\r'}"
                if ! [[ "${SEL_INDEX}" =~ ^[0-9]+$ ]] || [ "${SEL_INDEX}" -lt 1 ] || [ "${SEL_INDEX}" -gt "${#ISO_FILES[@]}" ]; then
                    log_error "Lựa chọn số thứ tự không hợp lệ."
                    continue
                fi

                local chosen_iso="${ISO_FILES[$((SEL_INDEX-1))]}"
                local base_iso_name
                base_iso_name=$(basename "${chosen_iso}")
                local target_remote_iso="iso/${base_iso_name}"

                upload_iso_to_datastore "${datastore}" "${chosen_iso}" "${target_remote_iso}"
                update_iso_in_packer "${pkr_file}" "${datastore}" "${target_remote_iso}"
                save_last_used_iso "${config_file}" "${target_remote_iso}"
                break
                ;;
            3)
                if ! command -v govc &> /dev/null; then
                    log_error "Lệnh govc chưa được cài đặt để duyệt Datastore."
                    continue
                fi

                log_info "Đang quét danh sách tệp .iso trên Datastore [${datastore}]..."
                mapfile -t REMOTE_ISOS < <(govc datastore.ls -R -ds="${datastore}" 2>/dev/null | grep -i "\.iso$" || true)
                if [[ ${#REMOTE_ISOS[@]} -eq 0 ]]; then
                    log_warn "Không tìm thấy tệp .iso nào trên Datastore [${datastore}]."
                    continue
                fi

                echo "Danh sách ISO có sẵn trên Datastore:"
                for idx in "${!REMOTE_ISOS[@]}"; do
                    echo "  $((idx+1))) ${REMOTE_ISOS[$idx]}"
                done
                if ! read -r -p "Nhập số thứ tự tệp ISO: " SEL_INDEX; then
                    echo ""
                    return 1
                fi
                SEL_INDEX="${SEL_INDEX%$'\r'}"
                if ! [[ "${SEL_INDEX}" =~ ^[0-9]+$ ]] || [ "${SEL_INDEX}" -lt 1 ] || [ "${SEL_INDEX}" -gt "${#REMOTE_ISOS[@]}" ]; then
                    log_error "Lựa chọn số thứ tự không hợp lệ."
                    continue
                fi

                local chosen_remote="${REMOTE_ISOS[$((SEL_INDEX-1))]}"
                log_success "Đã chọn: ${chosen_remote}"
                update_iso_in_packer "${pkr_file}" "${datastore}" "${chosen_remote}"
                save_last_used_iso "${config_file}" "${chosen_remote}"
                break
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done

    return 0
}
