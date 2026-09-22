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
# shellcheck source=lib/content_library.sh
[[ -f "${SCRIPT_LIB_DIR}/content_library.sh" ]] && source "${SCRIPT_LIB_DIR}/content_library.sh"

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

ensure_govc_session() {
    local pkr_file="${1:-}"
    local config_file="${2:-}"

    if ! command -v govc &> /dev/null; then
        log_error "Lệnh govc chưa được cài đặt trên hệ thống."
        log_info "Vui lòng chọn mục '4) Cài đặt môi trường công cụ tự động hóa (Seed Setup)' để cài đặt govc."
        return 1
    fi

    # Nếu govc đã xác thực thành công trong session hiện tại thì không hỏi lại
    if [[ -n "${GOVC_URL:-}" && -n "${GOVC_PASSWORD:-}" ]] && govc about &> /dev/null; then
        return 0
    fi

    log_banner "XÁC THỰC KẾT NỐI VCENTER (GOVC)"

    local repo_base
    repo_base="$(cd "${SCRIPT_LIB_DIR}/.." && pwd)"

    local detected_server=""
    local detected_user=""

    # 1. Tra cứu từ tệp Packer pkrvars nếu có
    if [[ -n "${pkr_file}" && -f "${pkr_file}" ]]; then
        detected_server=$(grep -E '^\s*vcenter_server\s*=' "${pkr_file}" | head -n 1 | cut -d'"' -f2 || true)
        detected_user=$(grep -E '^\s*vcenter_user\s*=' "${pkr_file}" | head -n 1 | cut -d'"' -f2 || true)
    fi

    # Tra cứu từ các tệp packer.pkrvars.hcl trong templates nếu chưa có
    if [[ -z "${detected_server}" || "${detected_server}" == *"<"*">"* ]]; then
        for p in "${repo_base}/packer/templates"/*/packer.pkrvars.hcl; do
            if [[ -f "${p}" ]]; then
                local s u
                s=$(grep -E '^\s*vcenter_server\s*=' "${p}" | head -n 1 | cut -d'"' -f2 || true)
                u=$(grep -E '^\s*vcenter_user\s*=' "${p}" | head -n 1 | cut -d'"' -f2 || true)
                if [[ -n "${s}" && "${s}" != *"<"*">"* ]]; then
                    detected_server="${s}"
                    detected_user="${u}"
                    break
                fi
            fi
        done
    fi

    # 2. Tra cứu từ tệp Terraform tfvars nếu chưa có
    if [[ -z "${detected_server}" || "${detected_server}" == *"<"*">"* ]]; then
        for tf_path in "${repo_base}/terraform/profiles/generic-vms/terraform.tfvars" "${repo_base}/terraform/profiles/elastic-stack/terraform.tfvars"; do
            if [[ -f "${tf_path}" ]]; then
                local s u
                s=$(grep -E '^\s*vsphere_server\s*=' "${tf_path}" | head -n 1 | cut -d'"' -f2 || true)
                u=$(grep -E '^\s*vsphere_user\s*=' "${tf_path}" | head -n 1 | cut -d'"' -f2 || true)
                if [[ -n "${s}" && "${s}" != *"<"*">"* ]]; then
                    detected_server="${s}"
                    detected_user="${u}"
                    break
                fi
            fi
        done
    fi

    # 3. Tra cứu từ tệp product.conf nếu chưa có
    if [[ -z "${detected_server}" || "${detected_server}" == *"<"*">"* ]]; then
        if [[ -n "${config_file}" && -f "${config_file}" ]]; then
            local s u
            s=$(grep -E '^\s*SITE_VCSA_IP=' "${config_file}" | head -n 1 | cut -d'"' -f2 || true)
            u=$(grep -E '^\s*VCENTER_USER=' "${config_file}" | head -n 1 | cut -d'"' -f2 || true)
            if [[ -n "${s}" && "${s}" != *"<"*">"* ]]; then
                detected_server="${s}"
                detected_user="${u}"
            fi
        fi
    fi

    local target_server=""
    if [[ -z "${detected_server}" || "${detected_server}" == *"<"*">"* ]]; then
        if ! read -r -p "Nhập địa chỉ IP / FQDN của vCenter Server: " target_server; then
            echo ""
            return 1
        fi
        target_server="${target_server%$'\r'}"
    else
        local s_prompt="Nhập địa chỉ vCenter Server [${detected_server}]"
        local input_server=""
        if ! read -r -p "${s_prompt}: " input_server; then
            echo ""
            return 1
        fi
        input_server="${input_server%$'\r'}"
        target_server="${input_server:-${detected_server}}"
    fi

    if [[ -z "${target_server}" || "${target_server}" == *"<"*">"* ]]; then
        log_error "Địa chỉ vCenter Server không hợp lệ."
        return 1
    fi

    local default_user="${detected_user:-administrator@vsphere.local}"
    [[ "${default_user}" == *"<"*">"* ]] && default_user="administrator@vsphere.local"
    local target_user=""
    local u_prompt="Nhập tài khoản vCenter [${default_user}]"
    local input_user=""
    if ! read -r -p "${u_prompt}: " input_user; then
        echo ""
        return 1
    fi
    input_user="${input_user%$'\r'}"
    target_user="${input_user:-${default_user}}"

    if [[ -z "${VCENTER_PASS:-}" ]]; then
        prompt_password "VCENTER_PASS" "Nhập mật khẩu quản trị vCenter (${target_user})" || return 1
    fi

    export VCENTER_PASS
    export VSPHERE_PASSWORD="${VCENTER_PASS}"
    export PKR_VAR_vcenter_password="${VCENTER_PASS}"
    export TF_VAR_vsphere_password="${VCENTER_PASS}"
    export_govc_env "${target_server}" "${target_user}" "${VCENTER_PASS}"

    log_info "Đang kiểm tra kết nối và xác thực tới vCenter (${target_server})..."
    local about_out
    if about_out=$(govc about 2>&1); then
        log_success "Xác thực vCenter Server thành công."
        if [[ -n "${pkr_file}" && -f "${pkr_file}" ]]; then
            if grep -q -E 'vcenter_server\s*=\s*"<.*>"' "${pkr_file}"; then
                sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${target_server}\2/" "${pkr_file}"
            fi
            if grep -q -E 'vcenter_user\s*=\s*"<.*>"' "${pkr_file}"; then
                sed -i -E "s/(vcenter_user\s*=\s*\")[^\"]+(\")/\1${target_user}\2/" "${pkr_file}"
            fi
        fi
        return 0
    else
        log_error "Không thể xác thực tới vCenter Server:"
        echo "${about_out}"
        unset VCENTER_PASS GOVC_PASSWORD
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
        if [[ -f "${pkr_file}.example" ]]; then
            log_info "Khởi tạo tệp biến cấu hình Packer từ ${pkr_file}.example..."
            cp "${pkr_file}.example" "${pkr_file}"
        else
            log_warn "Không tìm thấy file cấu hình Packer: ${pkr_file}"
            return 1
        fi
    fi

    local pkr_dir
    pkr_dir="$(dirname "${pkr_file}")"
    if [[ ! -f "${pkr_dir}/http/user-data" && -f "${pkr_dir}/http/user-data.example" ]]; then
        cp "${pkr_dir}/http/user-data.example" "${pkr_dir}/http/user-data"
    fi

    # Chuẩn hóa chuỗi iso_paths: hỗ trợ cả Datastore và Content Library
    local formatted_iso_path=""
    if [[ "${iso_remote_path}" =~ ^\[.*\] ]]; then
        formatted_iso_path="${iso_remote_path}"
    elif [[ -n "${datastore}" && "${datastore}" != *"<"*">"* ]]; then
        formatted_iso_path="[${datastore}] ${iso_remote_path}"
    else
        formatted_iso_path="${iso_remote_path}"
    fi

    # Cập nhật danh sách iso_paths trong file HCL/pkrvars
    if grep -q "^iso_paths" "${pkr_file}"; then
        sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "'"${formatted_iso_path}"'"\
]' "${pkr_file}"
        log_success "Đã cập nhật iso_paths trong ${pkr_file} thành: ${formatted_iso_path}"
    else
        log_warn "Cấu trúc iso_paths không tìm thấy trong ${pkr_file} để cập nhật."
    fi

    # Cập nhật vcenter_datastore nếu đang chứa placeholder và datastore hợp lệ
    if [[ -n "${datastore}" && "${datastore}" != *"<"*">"* ]] && grep -q -E 'vcenter_datastore\s*=\s*"<.*>"' "${pkr_file}"; then
        sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${datastore}\2/" "${pkr_file}"
        log_success "Đã cập nhật vcenter_datastore trong ${pkr_file} thành: ${datastore}"
    fi
}

# Liệt kê toàn bộ các tệp ISO trên Datastore kèm đường dẫn tương đối (loại bỏ thư mục tạm/nội bộ)
get_datastore_iso_files() {
    local ds="$1"
    [[ -z "${ds}" ]] && return 0

    local json_output=""
    if json_output=$(govc datastore.ls -json -R -ds="${ds}" 2>/dev/null) && [[ -n "${json_output}" ]]; then
        python3 -c "
import json, re, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    data = [data]
for item in data:
    raw_folder = item.get('folderPath', '')
    folder = re.sub(r'^\[[^\]]+\]\s*', '', raw_folder).strip('/')
    # Loại trừ thư mục tạm packer và thư mục raw của Content Library
    if folder.startswith('packer_cache') or folder.startswith('.packer') or folder.startswith('contentlib-'):
        continue
    for f in item.get('file', []):
        fname = f.get('path', '')
        if fname.lower().endswith('.iso') and not fname.startswith('packer'):
            full_path = f'{folder}/{fname}' if folder else fname
            print(full_path)
" <<< "${json_output}"
        return 0
    fi

    # Phương án dự phòng phân tích văn bản thuần nếu không parse được JSON
    local raw_ls
    raw_ls=$(govc datastore.ls -R -ds="${ds}" 2>/dev/null || true)
    if [[ -n "${raw_ls}" ]]; then
        echo "${raw_ls}" | grep -i "\.iso$" | grep -v -E '^(packer[0-9]+|\.packer)' || true
    fi
}

# Xác minh sự tồn tại của tệp ISO (Datastore hoặc Content Library) trước khi Packer build
validate_packer_iso_path() {
    local pkr_file="$1"
    [[ ! -f "${pkr_file}" ]] && return 0

    if ! command -v govc &>/dev/null; then
        return 0
    fi

    # Trích xuất đường dẫn ISO đầu tiên từ iso_paths trong file HCL
    local raw_iso
    raw_iso=$(grep -A 2 -E '^\s*iso_paths\s*=' "${pkr_file}" | grep -E '"[^"]+"' | head -n 1 | sed -E 's/^\s*"([^"]+)".*/\1/' || true)

    # Nếu rỗng hoặc còn chứa placeholder thì bỏ qua
    [[ -z "${raw_iso}" || "${raw_iso}" == *"<"*">"* ]] && return 0

    log_info "Kiểm tra tính sẵn sàng của tệp ISO cấu hình: ${raw_iso}"

    # 1. Trường hợp ISO nằm trên Datastore: [DatastoreName] path/to/file.iso
    if [[ "${raw_iso}" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
        local target_ds="${BASH_REMATCH[1]}"
        local rel_path="${BASH_REMATCH[2]}"
        rel_path="$(echo "${rel_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if govc datastore.ls -ds="${target_ds}" "${rel_path}" &>/dev/null; then
            log_success "Đã xác nhận tệp ISO tồn tại trên Datastore [${target_ds}]: ${rel_path}"
            return 0
        fi

        log_error "Tệp ISO KHÔNG tồn tại trên Datastore [${target_ds}] tại đường dẫn: '${rel_path}'"
        local iso_base
        iso_base="$(basename "${rel_path}")"

        log_info "Đang quét tìm kiếm tệp '${iso_base}' trên Datastore [${target_ds}]..."
        local found_match=""
        found_match=$(get_datastore_iso_files "${target_ds}" | grep -i -E "(^|/)${iso_base}$" | head -n 1 || true)
        if [[ -z "${found_match}" ]]; then
            found_match=$(get_datastore_iso_files "${target_ds}" | grep -i "${iso_base}" | head -n 1 || true)
        fi

        if [[ -n "${found_match}" ]]; then
            found_match="${found_match#/}"
            log_warn "Phát hiện tệp ISO tại vị trí thực tế: [${target_ds}] ${found_match}"
            if confirm_action "Bạn có muốn tự động sửa đường dẫn thành '[${target_ds}] ${found_match}' không?" "Y"; then
                update_iso_in_packer "${pkr_file}" "${target_ds}" "${found_match}"
                return 0
            fi
        else
            log_warn "Không tìm thấy tệp ISO '${iso_base}' trên Datastore [${target_ds}]."
        fi

        local repo_seed_dir="${SCRIPT_LIB_DIR}/../seed"
        if confirm_action "Khởi chạy menu quản lý ISO để chọn lại tệp ISO hợp lệ?" "Y"; then
            run_iso_menu "${target_ds}" "${pkr_file}" "" "${repo_seed_dir}"
            return $?
        fi
        return 1

    # 2. Trường hợp ISO nằm trong vSphere Content Library: LibraryName/ItemName[/FileName]
    elif [[ "${raw_iso}" == *"/"* ]]; then
        local lib_name
        lib_name=$(echo "${raw_iso}" | cut -d'/' -f1)
        local item_name
        item_name=$(echo "${raw_iso}" | cut -d'/' -f2)

        if govc library.ls "/${lib_name}/${item_name}" &>/dev/null || govc library.ls "${lib_name}/${item_name}" &>/dev/null; then
            log_success "Đã xác nhận item ISO tồn tại trong Content Library: ${lib_name}/${item_name}"
            return 0
        else
            log_error "Item ISO KHÔNG tồn tại trong Content Library: ${raw_iso}"
            if confirm_action "Khởi chạy menu chọn ISO từ Content Library để chọn lại?" "Y"; then
                select_iso_from_content_library "${pkr_file}" ""
                return $?
            fi
            return 1
        fi
    fi

    return 0
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

    # Đảm bảo phiên xác thực govc sẵn sàng
    if ! ensure_govc_session "${pkr_file}" "${config_file}"; then
        log_error "Không thể thiết lập phiên kết nối vCenter cho govc."
        return 1
    fi

    # Kiểm tra ISO đã lưu lần trước
    local last_iso=""
    if [[ -f "${config_file}" ]]; then
        last_iso=$(grep -E '^LAST_USED_ISO=' "${config_file}" | cut -d'"' -f2 || true)
    fi

    if [[ -n "${last_iso}" ]]; then
        if [[ "${last_iso}" =~ ^\[.*\] ]]; then
            log_info "Phát hiện tệp ISO đã dùng gần nhất trên Datastore: ${last_iso}"
            if confirm_action "Tiếp tục sử dụng tệp ISO này cho Packer?" "Y"; then
                update_iso_in_packer "${pkr_file}" "" "${last_iso}"
                return 0
            fi
        elif [[ "${last_iso}" == *"/"* && "${last_iso}" != "iso/"* ]]; then
            log_info "Phát hiện tệp ISO đã dùng gần nhất từ Content Library: ${last_iso}"
            if confirm_action "Tiếp tục sử dụng tệp ISO Content Library này cho Packer?" "Y"; then
                update_iso_in_packer "${pkr_file}" "" "${last_iso}"
                return 0
            fi
        elif [[ -n "${datastore}" && "${datastore}" != *"<"*">"* ]]; then
            log_info "Phát hiện tệp ISO đã dùng trong cấu hình gần nhất: ${last_iso}"
            if confirm_action "Tiếp tục sử dụng tệp ISO này trên Datastore [${datastore}]?" "Y"; then
                update_iso_in_packer "${pkr_file}" "${datastore}" "${last_iso}"
                return 0
            fi
        fi
    fi

    ensure_target_datastore() {
        if [[ -z "${datastore}" || "${datastore}" == *"<"*">"* ]]; then
            local ds_candidates=()
            mapfile -t ds_candidates < <(govc find -type s 2>/dev/null | sed 's|.*/||' | sort -u || true)
            if [[ ${#ds_candidates[@]} -gt 0 ]]; then
                echo ""
                echo "Danh sách Datastore khả dụng trên vCenter:"
                for idx in "${!ds_candidates[@]}"; do
                    echo "  $((idx+1))) ${ds_candidates[$idx]}"
                done
                local sel_ds=""
                if read -r -p "Vui lòng chọn Datastore (1-${#ds_candidates[@]}) [1]: " sel_ds; then
                    sel_ds="${sel_ds%$'\r'}"
                    sel_ds="${sel_ds:-1}"
                    if [[ "${sel_ds}" =~ ^[0-9]+$ ]] && [ "${sel_ds}" -ge 1 ] && [ "${sel_ds}" -le "${#ds_candidates[@]}" ]; then
                        datastore="${ds_candidates[$((sel_ds-1))]}"
                    fi
                fi
            fi

            if [[ -z "${datastore}" || "${datastore}" == *"<"*">"* ]]; then
                local input_ds=""
                read -r -p "Nhập tên Datastore đích trên vCenter: " input_ds
                input_ds="${input_ds%$'\r'}"
                if [[ -z "${input_ds}" || "${input_ds}" == *"<"*">"* ]]; then
                    log_error "Tên Datastore không được để trống hoặc chứa ký tự mẫu."
                    return 1
                fi
                datastore="${input_ds}"
            fi
        fi
        return 0
    }

    while true; do
        echo ""
        echo "Phương thức thiết lập ISO cài đặt hệ điều hành:"
        echo "  1) Tải ISO tự động từ Internet & upload lên Datastore"
        echo "  2) Chọn tệp ISO từ đĩa cục bộ & upload lên Datastore"
        echo "  3) Chọn tệp ISO đã có sẵn trên Datastore vCenter"
        echo "  4) Chọn tệp ISO từ vSphere Content Library"
        echo "  5) Quản lý kho vSphere Content Library (Tạo thư viện, nạp ISO)"
        echo "  0) Hủy và quay lại"
        if ! read -r -p "Nhập lựa chọn (0-5) [1]: " ISO_CHOICE; then
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
                ensure_target_datastore || continue
                local tmpl_os=""
                if [[ -n "${pkr_file}" ]]; then
                    tmpl_os="$(basename "$(dirname "${pkr_file}")")"
                fi

                local download_flag="--ubuntu"
                local iso_filename="ubuntu-24.04.5-live-server-amd64.iso"
                if [[ "${tmpl_os}" == *"rocky"* ]]; then
                    download_flag="--rocky"
                    iso_filename="Rocky-9-latest-x86_64-minimal.iso"
                fi

                log_info "Bắt đầu tải ISO từ Internet cho hệ điều hành [${tmpl_os:-generic}]..."
                if [[ -x "${seed_dir}/download_iso.sh" ]]; then
                    (cd "${seed_dir}" && ./download_iso.sh "${download_flag}")
                else
                    log_error "Không tìm thấy script ${seed_dir}/download_iso.sh."
                    return 1
                fi

                local iso_local="${seed_dir}/iso_cache/${iso_filename}"
                if [[ ! -f "${iso_local}" ]]; then
                    if [[ -f "iso_cache/${iso_filename}" ]]; then
                        iso_local="iso_cache/${iso_filename}"
                    else
                        log_error "Tệp ISO không tồn tại sau khi tải: ${iso_local}"
                        return 1
                    fi
                fi

                local iso_remote="iso/${iso_filename}"
                upload_iso_to_datastore "${datastore}" "${iso_local}" "${iso_remote}"
                update_iso_in_packer "${pkr_file}" "${datastore}" "${iso_remote}"
                save_last_used_iso "${config_file}" "${iso_remote}"
                break
                ;;
            2)
                ensure_target_datastore || continue
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
                ensure_target_datastore || continue
                log_info "Đang quét danh sách tệp .iso trên Datastore [${datastore}]..."
                mapfile -t REMOTE_ISOS < <(get_datastore_iso_files "${datastore}")
                if [[ ${#REMOTE_ISOS[@]} -eq 0 ]]; then
                    log_warn "Không tìm thấy tệp .iso nào trên Datastore [${datastore}]."
                    continue
                fi

                echo ""
                echo "Danh sách ISO có sẵn trên Datastore [${datastore}]:"
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
            4)
                if select_iso_from_content_library "${pkr_file}" "${config_file}"; then
                    break
                fi
                ;;
            5)
                run_content_library_menu "${config_file}"
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done

    return 0
}
