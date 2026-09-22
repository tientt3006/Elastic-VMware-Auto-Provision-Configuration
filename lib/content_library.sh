#!/usr/bin/env bash
# ==============================================================================
# vSphere Content Library Management and ISO Resolution Module
# - Manages lifecycle of vSphere Content Libraries (list, create, inspect, import)
# - Resolves underlying Datastore paths for Packer vsphere-iso builder
# - Generic, modular, and reusable across all provisioning workflows
# ==============================================================================
[[ -n "${_LIB_CONTENT_LIBRARY_LOADED:-}" ]] && return 0
_LIB_CONTENT_LIBRARY_LOADED=1

# Ensure common utilities are available
CONTENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_LIB="$(cd "${CONTENT_LIB_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT_LIB}/lib/common.sh" ]] && source "${REPO_ROOT_LIB}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT_LIB}/lib/secrets.sh" ]] && source "${REPO_ROOT_LIB}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
[[ -f "${REPO_ROOT_LIB}/lib/vsphere.sh" ]] && source "${REPO_ROOT_LIB}/lib/vsphere.sh"

# ==============================================================================
# Core Content Library Query Functions
# ==============================================================================

# Liệt kê tất cả Content Libraries trên vCenter
# Output: Danh sách tên thư viện (mỗi dòng một tên)
get_content_libraries() {
    if ! command -v govc &>/dev/null; then
        log_error "govc chưa được cài đặt trong môi trường."
        return 1
    fi

    local raw_output
    raw_output=$(govc library.ls 2>/dev/null || true)
    if [[ -z "${raw_output}" ]]; then
        return 0
    fi

    # govc library.ls trả về dạng: /LibraryName
    echo "${raw_output}" | sed 's|^/||' | grep -v '^\s*$' | sort -u
}

# Liệt kê các items trong một Content Library
# $1: Tên Content Library
get_content_library_items() {
    local lib_name="$1"
    [[ -z "${lib_name}" ]] && return 1

    local raw_output
    raw_output=$(govc library.ls "/${lib_name}" 2>/dev/null || true)
    if [[ -z "${raw_output}" ]]; then
        return 0
    fi

    # govc library.ls /Lib trả về: /Lib/ItemName
    echo "${raw_output}" | sed "s|^/${lib_name}/||" | grep -v '^\s*$' | sort -u
}

# Liệt kê tất cả tệp ISO trong một Content Library
# Hỗ trợ cả item có đuôi .iso và item không có đuôi (được lưu dưới dạng Other Types trong vCenter)
# $1: Tên Content Library
# Output: Danh sách tên item ISO khả dụng (mỗi dòng một item)
get_content_library_iso_files() {
    local lib_name="$1"
    [[ -z "${lib_name}" ]] && return 1

    # 1. Thử quét nhanh toàn bộ file bên trong thư viện qua wildcard
    local batch_output=""
    batch_output=$(govc library.ls "/${lib_name}/*/" 2>/dev/null || true)
    if [[ -n "${batch_output}" ]] && echo "${batch_output}" | grep -qi '\.iso$'; then
        while IFS= read -r fline; do
            [[ -z "${fline}" ]] && continue
            if [[ "${fline}" =~ \.iso$|\.ISO$ ]]; then
                local item_name
                item_name=$(echo "${fline}" | sed "s|^/${lib_name}/||" | cut -d'/' -f1)
                [[ -n "${item_name}" ]] && echo "${item_name}"
            fi
        done <<< "${batch_output}" | sort -u
        return 0
    fi

    # 2. Duyệt từng item trong thư viện nếu quét nhanh wildcard không trả về kết quả
    local items=()
    mapfile -t items < <(get_content_library_items "${lib_name}")
    if [[ ${#items[@]} -eq 0 ]]; then
        return 0
    fi

    local non_iso_regex='\.(tar|tar\.gz|tgz|zip|7z|rar|ovf|ova|vmdk|txt|json|xml|cfg|log|rpm|deb)$'

    for item in "${items[@]}"; do
        # Bỏ qua các item có định dạng tệp rõ ràng không phải ISO
        if [[ "${item}" =~ ${non_iso_regex} ]]; then
            continue
        fi

        # Nếu tên item kết thúc bằng .iso hoặc .ISO
        if [[ "${item}" =~ \.iso$|\.ISO$ ]]; then
            echo "${item}"
            continue
        fi

        # Kiểm tra tệp con bên trong item bằng dấu gạch chéo cuối
        local files_raw
        files_raw=$(govc library.ls "/${lib_name}/${item}/" 2>/dev/null || true)
        if [[ -n "${files_raw}" ]] && echo "${files_raw}" | grep -qi '\.iso$'; then
            echo "${item}"
            continue
        fi

        # Kiểm tra đường dẫn lưu trữ tầng Datastore của item bằng govc library.info -L -l
        local ds_path
        ds_path=$(govc library.info -L -l "/${lib_name}/${item}" 2>/dev/null || true)
        if [[ -n "${ds_path}" ]] && echo "${ds_path}" | grep -qi '\.iso'; then
            echo "${item}"
            continue
        fi

        # Kiểm tra metadata của item qua govc library.info
        local item_info
        item_info=$(govc library.info "/${lib_name}/${item}" 2>/dev/null || true)
        if [[ -n "${item_info}" ]]; then
            if echo "${item_info}" | grep -Ei '^\s*Type:\s*iso\b' &>/dev/null || echo "${item_info}" | grep -qi '\.iso'; then
                echo "${item}"
                continue
            fi
        fi

        # Dự phòng cho các item trong mục Other Types không có đuôi tệp
        if ! [[ "${item}" =~ \.[a-zA-Z0-9_-]{1,6}$ ]]; then
            echo "${item}"
        fi
    done | sort -u
}

# Lấy đường dẫn Datastore chuẩn hóa của file ISO trong Content Library
# $1: Tên Content Library
# $2: Đường dẫn file hoặc tên item trong library
# Output: [DatastoreName] contentlib-UUID/item-UUID/FileName.iso
resolve_content_library_iso_datastore_path() {
    local lib_name="$1"
    local file_rel_path="$2"

    [[ -z "${lib_name}" || -z "${file_rel_path}" ]] && return 1

    local full_query="/${lib_name}/${file_rel_path}"
    local ds_raw
    ds_raw=$(govc library.info -L -l "${full_query}" 2>/dev/null || true)

    # Nếu truy vấn trực tiếp chưa có, thử truy vấn theo item
    if [[ -z "${ds_raw}" || "${ds_raw}" != *"["*"]"* ]]; then
        local item_only
        item_only=$(echo "${file_rel_path}" | cut -d'/' -f1)
        ds_raw=$(govc library.info -L -l "/${lib_name}/${item_only}" 2>/dev/null || true)
    fi

    # Trích xuất dòng chứa đường dẫn Datastore chuẩn [DatastoreName] ... .iso
    local clean_path
    clean_path=$(echo "${ds_raw}" | tr -d '\r' | grep -E '^\[[^]]+\].*\.iso' | head -n 1 || true)
    if [[ -z "${clean_path}" ]]; then
        clean_path=$(echo "${ds_raw}" | tr -d '\r' | grep -E '^\[[^]]+\]' | head -n 1 || true)
    fi
    clean_path=$(echo "${clean_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ -z "${clean_path}" || "${clean_path}" != *"["*"]"* ]]; then
        log_error "Không thể phân giải đường dẫn Datastore cho: ${full_query}"
        return 1
    fi

    echo "${clean_path}"
}

# ==============================================================================
# Lifecycle Management Functions (Create, Import)
# ==============================================================================

# Tạo Content Library mới trên vCenter
# $1: Tên Content Library
# $2: Tên Datastore lưu trữ
# $3: Mô tả (tùy chọn)
create_content_library() {
    local lib_name="$1"
    local datastore="$2"
    local description="${3:-Local Content Library for OS ISO and VM Templates}"

    if [[ -z "${lib_name}" || -z "${datastore}" ]]; then
        log_error "Tên Content Library và Datastore không được để trống."
        return 1
    fi

    log_info "Đang tạo Content Library '${lib_name}' trên Datastore [${datastore}]..."
    if govc library.create -ds="${datastore}" -d="${description}" "${lib_name}"; then
        log_success "Đã tạo thành công Content Library: ${lib_name}"
        return 0
    else
        log_error "Không thể tạo Content Library '${lib_name}'."
        return 1
    fi
}

# Nhập (import) tệp ISO vào Content Library
# $1: Tên Content Library
# $2: Đường dẫn nguồn (file local hoặc HTTP/HTTPS URL)
# $3: Tên item hiển thị (tùy chọn, mặc định lấy tên file)
import_iso_to_content_library() {
    local lib_name="$1"
    local source_uri="$2"
    local item_name="${3:-}"

    if [[ -z "${lib_name}" || -z "${source_uri}" ]]; then
        log_error "Tên Content Library và nguồn tệp ISO không được để trống."
        return 1
    fi

    if [[ -z "${item_name}" ]]; then
        item_name=$(basename "${source_uri}")
    fi

    if [[ "${source_uri}" =~ ^https?:// ]]; then
        log_info "Đang yêu cầu vCenter tải trực tiếp ISO từ URL vào Content Library '${lib_name}'..."
        log_info "Nguồn URL:  ${source_uri}"
        log_info "Tên Item:   ${item_name}"
        if govc library.import -pull -n="${item_name}" "${lib_name}" "${source_uri}"; then
            log_success "Đã yêu cầu vCenter tải và nạp ISO thành công."
            return 0
        else
            log_error "Lỗi khi nhập ISO từ URL vào Content Library."
            return 1
        fi
    else
        if [[ ! -f "${source_uri}" ]]; then
            log_error "Tệp ISO cục bộ không tồn tại: ${source_uri}"
            return 1
        fi
        log_info "Đang tải lên tệp ISO từ máy local vào Content Library '${lib_name}'..."
        log_info "Tệp nguồn: ${source_uri}"
        log_info "Tên Item:  ${item_name}"
        if govc library.import -n="${item_name}" "${lib_name}" "${source_uri}"; then
            log_success "Đã tải lên và nạp ISO vào Content Library thành công."
            return 0
        else
            log_error "Lỗi khi tải tệp ISO lên Content Library."
            return 1
        fi
    fi
}

# ==============================================================================
# Interactive Picker & Management Menus
# ==============================================================================

# Trình tương tác: Chọn ISO từ Content Library và đồng bộ vào Packer pkrvars
# $1: Đường dẫn file packer.pkrvars.hcl
# $2: Đường dẫn file cấu hình phụ trợ (product.conf nếu có)
select_iso_from_content_library() {
    local pkr_file="$1"
    local config_file="${2:-}"

    if [[ -z "${pkr_file}" ]]; then
        log_error "Đường dẫn file cấu hình Packer không được để trống."
        return 1
    fi

    log_banner "CHỌN TỆP ISO TỪ VSPHERE CONTENT LIBRARY CHO PACKER"

    # Đảm bảo phiên xác thực govc sẵn sàng
    if ! ensure_govc_session "${pkr_file}" "${config_file}"; then
        log_error "Không thể thiết lập phiên kết nối vCenter cho govc."
        return 1
    fi

    log_info "Đang truy vấn danh sách Content Library trên vCenter..."
    local libraries=()
    mapfile -t libraries < <(get_content_libraries)

    if [[ ${#libraries[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy Content Library nào trên vCenter."
        log_info "Vui lòng dùng mục '5) Quản lý kho vSphere Content Library' để tạo thư viện mới."
        return 1
    fi

    echo "Danh sách Content Library có sẵn:"
    for idx in "${!libraries[@]}"; do
        echo "  $((idx+1))) ${libraries[$idx]}"
    done
    echo "  0) Hủy thao tác"

    local sel_lib=""
    if ! read -r -p "Vui lòng chọn Content Library (1-${#libraries[@]}) [1]: " sel_lib; then
        echo ""
        return 1
    fi
    sel_lib="${sel_lib%$'\r'}"
    sel_lib="${sel_lib:-1}"
    sel_lib="$(echo "${sel_lib}" | tr -d ' ')"

    if [[ "${sel_lib}" == "0" ]]; then
        log_info "Hủy thao tác."
        return 1
    fi

    if ! [[ "${sel_lib}" =~ ^[0-9]+$ ]] || [ "${sel_lib}" -lt 1 ] || [ "${sel_lib}" -gt "${#libraries[@]}" ]; then
        log_error "Lựa chọn Content Library không hợp lệ."
        return 1
    fi

    local chosen_lib="${libraries[$((sel_lib-1))]}"
    log_info "Đã chọn Content Library: ${chosen_lib}"

    log_info "Đang quét các tệp ISO trong thư viện '${chosen_lib}'..."
    local iso_list=()
    mapfile -t iso_list < <(get_content_library_iso_files "${chosen_lib}")

    if [[ ${#iso_list[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy tệp ISO nào trong Content Library '${chosen_lib}'."
        return 1
    fi

    echo ""
    echo "Danh sách tệp ISO trong Content Library [${chosen_lib}]:"
    for idx in "${!iso_list[@]}"; do
        echo "  $((idx+1))) ${iso_list[$idx]}"
    done
    echo "  0) Hủy"

    local sel_iso=""
    if ! read -r -p "Vui lòng chọn số thứ tự tệp ISO: " sel_iso; then
        echo ""
        return 1
    fi
    sel_iso="${sel_iso%$'\r'}"
    if [[ "${sel_iso}" == "0" ]]; then
        log_info "Hủy thao tác."
        return 1
    fi

    if ! [[ "${sel_iso}" =~ ^[0-9]+$ ]] || [ "${sel_iso}" -lt 1 ] || [ "${sel_iso}" -gt "${#iso_list[@]}" ]; then
        log_error "Lựa chọn số thứ tự ISO không hợp lệ."
        return 1
    fi

    local chosen_iso_file="${iso_list[$((sel_iso-1))]}"
    log_info "Đang xác định định danh chuẩn vSphere Content Library cho: ${chosen_iso_file}..."

    # Truy vấn tệp con bên trong item (nếu có)
    local sub_file=""
    local files_raw
    files_raw=$(govc library.ls "/${chosen_lib}/${chosen_iso_file}/" 2>/dev/null || true)
    if [[ -n "${files_raw}" ]]; then
        sub_file=$(echo "${files_raw}" | sed "s|^/${chosen_lib}/${chosen_iso_file}/||" | tr -d '\r' | grep -i '\.iso$' | head -n 1 || true)
    fi

    local cl_iso_path=""
    if [[ -n "${sub_file}" && "${chosen_iso_file}" != "${sub_file}" ]]; then
        cl_iso_path="${chosen_lib}/${chosen_iso_file}/${sub_file}"
    elif [[ -n "${sub_file}" && "${chosen_iso_file}" == "${sub_file}" ]]; then
        cl_iso_path="${chosen_lib}/${chosen_iso_file}"
    else
        cl_iso_path="${chosen_lib}/${chosen_iso_file}"
    fi

    log_success "Định danh ISO chuẩn vSphere Content Library: ${cl_iso_path}"

    # Xác định Datastore lưu trữ của Content Library (phục vụ kiểm tra/đồng bộ vcenter_datastore)
    local lib_datastore=""
    local resolved_ds_path
    resolved_ds_path=$(resolve_content_library_iso_datastore_path "${chosen_lib}" "${chosen_iso_file}" 2>/dev/null || true)
    if [[ -n "${resolved_ds_path}" ]]; then
        lib_datastore=$(echo "${resolved_ds_path}" | sed -E 's/^\[([^]]+)\].*/\1/' || true)
    fi
    if [[ -z "${lib_datastore}" ]]; then
        lib_datastore=$(govc library.info "/${chosen_lib}" 2>/dev/null | tr -d '\r' | grep -i 'Datastore:' | awk '{print $2}' || true)
    fi
    if [[ -n "${lib_datastore}" ]]; then
        log_info "Datastore lưu trữ của Content Library: [${lib_datastore}]"
    fi

    # Khởi tạo tệp cấu hình Packer từ .example nếu chưa tồn tại
    if [[ ! -f "${pkr_file}" && -f "${pkr_file}.example" ]]; then
        log_info "Khởi tạo tệp cấu hình Packer từ ${pkr_file}.example..."
        cp "${pkr_file}.example" "${pkr_file}"
    fi

    local pkr_dir
    pkr_dir="$(dirname "${pkr_file}")"
    if [[ ! -f "${pkr_dir}/http/user-data" && -f "${pkr_dir}/http/user-data.example" ]]; then
        cp "${pkr_dir}/http/user-data.example" "${pkr_dir}/http/user-data"
    fi

    # Cập nhật vào file packer.pkrvars.hcl
    if [[ -f "${pkr_file}" ]]; then
        # Cập nhật danh sách iso_paths bằng định danh chuẩn Content Library
        if grep -q "^iso_paths" "${pkr_file}"; then
            sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "'"${cl_iso_path}"'"\
]' "${pkr_file}"
            log_success "Đã cập nhật iso_paths trong ${pkr_file}:"
            log_success "  ${cl_iso_path}"
        fi

        # Kiểm tra và đồng bộ vcenter_datastore nếu đang chứa placeholder
        if [[ -n "${lib_datastore}" ]]; then
            local cur_ds
            cur_ds=$(grep -E '^\s*vcenter_datastore\s*=' "${pkr_file}" | head -n 1 | cut -d'"' -f2 || true)
            if [[ -z "${cur_ds}" || "${cur_ds}" == *"<"*">"* ]]; then
                sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${lib_datastore}\2/" "${pkr_file}"
                log_success "Đã tự động đồng bộ vcenter_datastore thành Datastore của Content Library: ${lib_datastore}"
            elif [[ "${cur_ds}" != "${lib_datastore}" ]]; then
                log_warn "Cảnh báo: Datastore của VM (${cur_ds}) khác Datastore của Content Library (${lib_datastore})."
                echo "Để tránh lỗi 'Invalid configuration for device 0', hai Datastore này nên truy cập được từ cùng host ESXi."
                if confirm_action "Bạn có muốn đồng bộ vcenter_datastore sang '${lib_datastore}' không?" "Y"; then
                    sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${lib_datastore}\2/" "${pkr_file}"
                    log_success "Đã cập nhật vcenter_datastore thành: ${lib_datastore}"
                fi
            fi
        fi
    fi

    if [[ -n "${config_file}" ]] && declare -f save_last_used_iso &>/dev/null; then
        save_last_used_iso "${config_file}" "${cl_iso_path}"
    fi

    return 0
}

# Sao chép hoặc di chuyển tệp ISO từ Datastore sang Content Library
copy_or_move_iso_datastore_to_content_library() {
    log_banner "SAO CHÉP / DI CHUYỂN TỆP ISO TỪ DATASTORE SANG CONTENT LIBRARY"

    # 1. Liệt kê các Content Library đích
    local libs=()
    mapfile -t libs < <(get_content_libraries)
    if [[ ${#libs[@]} -eq 0 ]]; then
        log_warn "Chưa có Content Library nào trên vCenter. Vui lòng tạo thư viện trước."
        return 1
    fi

    echo "Danh sách Content Library đích:"
    for idx in "${!libs[@]}"; do
        echo "  $((idx+1))) ${libs[$idx]}"
    done
    local sel_lib=""
    if ! read -r -p "Chọn thư viện đích (1-${#libs[@]}) [1]: " sel_lib; then
        return 1
    fi
    sel_lib="${sel_lib%$'\r'}"
    sel_lib="${sel_lib:-1}"
    if ! [[ "${sel_lib}" =~ ^[0-9]+$ ]] || [ "${sel_lib}" -lt 1 ] || [ "${sel_lib}" -gt "${#libs[@]}" ]; then
        log_error "Lựa chọn thư viện không hợp lệ."
        return 1
    fi
    local target_lib="${libs[$((sel_lib-1))]}"

    # 2. Chọn Datastore nguồn
    local ds_candidates=()
    mapfile -t ds_candidates < <(govc find -type d 2>/dev/null | sed 's|.*/||' | sort -u || true)
    local src_ds=""
    if [[ ${#ds_candidates[@]} -gt 0 ]]; then
        echo ""
        echo "Danh sách Datastore nguồn trên vCenter:"
        for idx in "${!ds_candidates[@]}"; do
            echo "  $((idx+1))) ${ds_candidates[$idx]}"
        done
        local sel_src_ds=""
        if read -r -p "Chọn Datastore nguồn (1-${#ds_candidates[@]}) [1]: " sel_src_ds; then
            sel_src_ds="${sel_src_ds%$'\r'}"
            sel_src_ds="${sel_src_ds:-1}"
            if [[ "${sel_src_ds}" =~ ^[0-9]+$ ]] && [ "${sel_src_ds}" -ge 1 ] && [ "${sel_src_ds}" -le "${#ds_candidates[@]}" ]; then
                src_ds="${ds_candidates[$((sel_src_ds-1))]}"
            fi
        fi
    fi

    if [[ -z "${src_ds}" ]]; then
        read -r -p "Nhập tên Datastore nguồn chứa tệp ISO: " src_ds
        src_ds="${src_ds%$'\r'}"
        if [[ -z "${src_ds}" ]]; then
            log_error "Tên Datastore nguồn không được để trống."
            return 1
        fi
    fi

    log_info "Đang quét danh sách tệp .iso trên Datastore [${src_ds}]..."
    local raw_isos
    if ! raw_isos=$(govc datastore.ls -R -ds="${src_ds}" 2>&1); then
        log_error "Không thể truy vấn Datastore [${src_ds}]:"
        echo "${raw_isos}"
        return 1
    fi

    local ds_iso_list=()
    mapfile -t ds_iso_list < <(echo "${raw_isos}" | grep -i "\.iso$" || true)
    if [[ ${#ds_iso_list[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy tệp .iso nào trên Datastore [${src_ds}]."
        return 1
    fi

    echo ""
    echo "Danh sách tệp ISO tìm thấy trên Datastore [${src_ds}]:"
    for idx in "${!ds_iso_list[@]}"; do
        echo "  $((idx+1))) ${ds_iso_list[$idx]}"
    done
    local sel_iso=""
    if ! read -r -p "Chọn số thứ tự tệp ISO muốn đưa vào Content Library (1-${#ds_iso_list[@]}): " sel_iso; then
        return 1
    fi
    sel_iso="${sel_iso%$'\r'}"
    if ! [[ "${sel_iso}" =~ ^[0-9]+$ ]] || [ "${sel_iso}" -lt 1 ] || [ "${sel_iso}" -gt "${#ds_iso_list[@]}" ]; then
        log_error "Lựa chọn tệp ISO không hợp lệ."
        return 1
    fi
    local chosen_ds_iso="${ds_iso_list[$((sel_iso-1))]}"
    local base_name
    base_name=$(basename "${chosen_ds_iso}")

    echo ""
    echo "Phương thức thực hiện:"
    echo "  1) Sao chép (Copy - giữ lại tệp gốc trên Datastore [${src_ds}])"
    echo "  2) Di chuyển (Move - xóa tệp gốc trên Datastore sau khi nạp vào Content Library)"
    local op_mode=""
    read -r -p "Chọn phương thức (1-2) [1]: " op_mode
    op_mode="${op_mode%$'\r'}"
    op_mode="${op_mode:-1}"

    echo ""
    echo "Cơ chế truyền dữ liệu vào Content Library:"
    echo "  1) Truyền trực tiếp qua HTTPS URL giữa ESXi Host và vCenter (Direct Pull - không tốn băng thông máy trạm)"
    echo "  2) Trung chuyển qua bộ đệm tạm của máy chạy code (Fallback - tải về máy trạm rồi đẩy lên)"
    local transfer_mech=""
    read -r -p "Chọn cơ chế (1-2) [1]: " transfer_mech
    transfer_mech="${transfer_mech%$'\r'}"
    transfer_mech="${transfer_mech:-1}"

    local pull_success=0

    # Cơ chế 1: Direct Pull từ ESXi Host qua endpoint HTTPS /folder
    if [[ "${transfer_mech}" == "1" ]]; then
        local hosts=()
        mapfile -t hosts < <(govc find -type h 2>/dev/null | sed 's|.*/||' | sort -u || true)
        local esxi_host=""
        if [[ ${#hosts[@]} -eq 1 ]]; then
            esxi_host="${hosts[0]}"
            echo "Tự động phát hiện ESXi Host duy nhất: ${esxi_host}"
            local input_host=""
            read -r -p "Nhấn [Enter] để tiếp tục (hoặc nhập địa chỉ IP khác) [${esxi_host}]: " input_host
            input_host="${input_host%$'\r'}"
            esxi_host="${input_host:-${esxi_host}}"
        elif [[ ${#hosts[@]} -gt 1 ]]; then
            echo ""
            echo "Danh sách ESXi Host kết nối với vCenter:"
            for idx in "${!hosts[@]}"; do
                echo "  $((idx+1))) ${hosts[$idx]}"
            done
            local sel_host=""
            read -r -p "Chọn ESXi Host chứa Datastore [${src_ds}] (1-${#hosts[@]}) [1]: " sel_host
            sel_host="${sel_host%$'\r'}"
            sel_host="${sel_host:-1}"
            if [[ "${sel_host}" =~ ^[0-9]+$ ]] && [ "${sel_host}" -ge 1 ] && [ "${sel_host}" -le "${#hosts[@]}" ]; then
                esxi_host="${hosts[$((sel_host-1))]}"
            fi
        fi

        if [[ -z "${esxi_host}" ]]; then
            read -r -p "Nhập địa chỉ IP / FQDN của ESXi Host: " esxi_host
            esxi_host="${esxi_host%$'\r'}"
        fi

        if [[ -z "${esxi_host}" ]]; then
            log_error "Địa chỉ ESXi Host không được để trống."
            return 1
        fi

        local esxi_user="root"
        if [[ -z "${ESXI_PASS:-}" ]]; then
            prompt_password "ESXI_PASS" "Nhập mật khẩu tài khoản ${esxi_user} của ESXi Host (${esxi_host})" || return 1
        fi
        local esxi_pass="${ESXI_PASS}"

        local clean_iso_path="${chosen_ds_iso#/}"
        local enc_user enc_pass enc_path enc_ds
        enc_user=$(url_encode "${esxi_user}" "")
        enc_pass=$(url_encode "${esxi_pass}" "")
        enc_path=$(url_encode "${clean_iso_path}" "/")
        enc_ds=$(url_encode "${src_ds}" "")

        local direct_url="https://${enc_user}:${enc_pass}@${esxi_host}/folder/${enc_path}?dcPath=ha-datacenter&dsName=${enc_ds}"

        log_info "Kích hoạt tác vụ vCenter kéo trực tiếp tệp ISO từ ESXi Host [${esxi_host}]..."
        log_info "Điểm cuối truyền tải: https://${esxi_host}/folder/${clean_iso_path}?dcPath=ha-datacenter&dsName=${src_ds}"

        if govc library.import -pull -n="${base_name}" "${target_lib}" "${direct_url}"; then
            log_success "vCenter đã hoàn tất nạp tệp '${base_name}' vào Content Library '${target_lib}' (Direct Transfer)."
            pull_success=1
        else
            log_error "Kéo tệp trực tiếp từ ESXi Host qua endpoint HTTPS /folder thất bại."
            log_warn "Nguyên nhân có thể do sai mật khẩu root ESXi, chứng chỉ SSL chưa được tin cậy, hoặc bị chặn cổng TCP 443 giữa vCenter và ESXi."
            if confirm_action "Chuyển sang phương thức trung chuyển qua máy chạy code?" "Y"; then
                transfer_mech=2
            else
                return 1
            fi
        fi
    fi

    # Cơ chế 2: Trung chuyển qua bộ đệm tạm của máy chạy code (Fallback)
    if [[ ${pull_success} -eq 0 && "${transfer_mech}" == "2" ]]; then
        local tmp_dir="/tmp/iso_import_cache"
        mkdir -p "${tmp_dir}"
        local tmp_file="${tmp_dir}/${base_name}"

        log_info "Đang tải tệp ISO từ Datastore [${src_ds}] ${chosen_ds_iso} về bộ đệm tạm máy trạm..."
        if ! govc datastore.download -ds="${src_ds}" "${chosen_ds_iso}" "${tmp_file}"; then
            log_error "Tải tệp ISO từ Datastore về máy trạm thất bại."
            rm -f "${tmp_file}"
            return 1
        fi

        log_info "Đang nạp tệp ISO từ máy trạm vào Content Library '${target_lib}'..."
        if govc library.import -n="${base_name}" "${target_lib}" "${tmp_file}"; then
            log_success "Đã nạp tệp '${base_name}' vào Content Library '${target_lib}' thành công."
            pull_success=1
        else
            log_error "Nạp tệp ISO vào Content Library thất bại."
        fi

        rm -f "${tmp_file}"
        log_info "Đã giải phóng vùng đệm tạm."
    fi

    # Xóa tệp nguồn nếu hoàn tất nạp và chọn phương thức Di chuyển (Move)
    if [[ ${pull_success} -eq 1 && "${op_mode}" == "2" ]]; then
        log_info "Đang xóa tệp gốc trên Datastore [${src_ds}] theo phương thức Di chuyển (Move)..."
        govc datastore.rm -ds="${src_ds}" "${chosen_ds_iso}" || log_warn "Xóa tệp gốc trên Datastore không thành công."
    fi

    return 0
}

# Menu quản lý tổng thể Content Library (độc lập)
run_content_library_menu() {
    local config_file="${1:-}"

    log_banner "QUẢN LÝ KHO TÀI NGUYÊN VSPHERE CONTENT LIBRARY & DATASTORE ISO"

    # Đảm bảo phiên xác thực govc sẵn sàng
    if ! ensure_govc_session "" "${config_file}"; then
        log_error "Không thể thiết lập phiên kết nối vCenter cho govc."
        return 1
    fi

    while true; do
        echo ""
        echo "Thao tác quản trị Content Library và kho ISO:"
        echo "  1) Liệt kê Content Library và các tệp ISO bên trong"
        echo "  2) Tạo Content Library mới trên Datastore"
        echo "  3) Tải tệp ISO từ Internet vào Content Library (URL - pull)"
        echo "  4) Upload tệp ISO từ máy cục bộ vào Content Library"
        echo "  5) Di chuyển / Sao chép tệp ISO từ Datastore sang Content Library"
        echo "  6) Liệt kê các tệp ISO đang có trên Datastore vCenter"
        echo "  7) Upload tệp ISO từ máy cục bộ lên Datastore vCenter"
        echo "  0) Quay lại"

        local choice=""
        if ! read -r -p "Vui lòng chọn (0-7) [1]: " choice; then
            echo ""
            return 0
        fi
        choice="${choice%$'\r'}"
        choice="${choice:-1}"

        case "${choice}" in
            0)
                return 0
                ;;
            1)
                log_info "Đang tải danh mục Content Library..."
                local libs=()
                mapfile -t libs < <(get_content_libraries)
                if [[ ${#libs[@]} -eq 0 ]]; then
                    log_warn "Hiện không có Content Library nào trên vCenter."
                else
                    echo ""
                    echo "=============================================================================="
                    printf "%-4s | %-30s | %s\n" "STT" "Tên Content Library" "Số lượng tệp ISO"
                    echo "------------------------------------------------------------------------------"
                    for idx in "${!libs[@]}"; do
                        local lname="${libs[$idx]}"
                        local isos=()
                        mapfile -t isos < <(get_content_library_iso_files "${lname}")
                        printf "%-4s | %-30s | %s tệp\n" "$((idx+1))" "${lname}" "${#isos[@]}"
                        for isofile in "${isos[@]}"; do
                            echo "       -> ${isofile}"
                        done
                    done
                    echo "=============================================================================="
                fi
                ;;
            2)
                local new_name=""
                read -r -p "Nhập tên Content Library mới: " new_name
                new_name="${new_name%$'\r'}"
                if [[ -z "${new_name}" ]]; then
                    log_error "Tên Content Library không được để trống."
                    continue
                fi

                local target_ds=""
                local ds_candidates=()
                mapfile -t ds_candidates < <(govc find -type d 2>/dev/null | sed 's|.*/||' | sort -u || true)
                if [[ ${#ds_candidates[@]} -gt 0 ]]; then
                    echo "Danh sách Datastore lưu trữ thư viện:"
                    for idx in "${!ds_candidates[@]}"; do
                        echo "  $((idx+1))) ${ds_candidates[$idx]}"
                    done
                    local sel_ds=""
                    if read -r -p "Chọn Datastore (1-${#ds_candidates[@]}) [1]: " sel_ds; then
                        sel_ds="${sel_ds%$'\r'}"
                        sel_ds="${sel_ds:-1}"
                        if [[ "${sel_ds}" =~ ^[0-9]+$ ]] && [ "${sel_ds}" -ge 1 ] && [ "${sel_ds}" -le "${#ds_candidates[@]}" ]; then
                            target_ds="${ds_candidates[$((sel_ds-1))]}"
                        fi
                    fi
                fi

                if [[ -z "${target_ds}" ]]; then
                    read -r -p "Nhập tên Datastore lưu trữ thư viện: " target_ds
                    target_ds="${target_ds%$'\r'}"
                    if [[ -z "${target_ds}" ]]; then
                        log_error "Tên Datastore không được để trống."
                        continue
                    fi
                fi

                local desc=""
                read -r -p "Nhập mô tả [ISO and VM Templates]: " desc
                desc="${desc%$'\r'}"
                desc="${desc:-ISO and VM Templates}"

                create_content_library "${new_name}" "${target_ds}" "${desc}"
                ;;
            3)
                local libs=()
                mapfile -t libs < <(get_content_libraries)
                if [[ ${#libs[@]} -eq 0 ]]; then
                    log_warn "Chưa có Content Library nào. Vui lòng tạo thư viện trước."
                    continue
                fi

                echo "Chọn thư viện đích:"
                for idx in "${!libs[@]}"; do
                    echo "  $((idx+1))) ${libs[$idx]}"
                done
                local sel_target=""
                read -r -p "Chọn thư viện (1-${#libs[@]}) [1]: " sel_target
                sel_target="${sel_target%$'\r'}"
                sel_target="${sel_target:-1}"
                if ! [[ "${sel_target}" =~ ^[0-9]+$ ]] || [ "${sel_target}" -lt 1 ] || [ "${sel_target}" -gt "${#libs[@]}" ]; then
                    log_error "Lựa chọn không hợp lệ."
                    continue
                fi
                local target_lib="${libs[$((sel_target-1))]}"

                local url_path=""
                read -r -p "Nhập trực tiếp URL tệp ISO (Internet): " url_path
                url_path="${url_path%$'\r'}"
                if [[ -n "${url_path}" ]]; then
                    import_iso_to_content_library "${target_lib}" "${url_path}"
                fi
                ;;
            4)
                local libs=()
                mapfile -t libs < <(get_content_libraries)
                if [[ ${#libs[@]} -eq 0 ]]; then
                    log_warn "Chưa có Content Library nào. Vui lòng tạo thư viện trước."
                    continue
                fi

                echo "Chọn thư viện đích:"
                for idx in "${!libs[@]}"; do
                    echo "  $((idx+1))) ${libs[$idx]}"
                done
                local sel_target=""
                read -r -p "Chọn thư viện (1-${#libs[@]}) [1]: " sel_target
                sel_target="${sel_target%$'\r'}"
                sel_target="${sel_target:-1}"
                if ! [[ "${sel_target}" =~ ^[0-9]+$ ]] || [ "${sel_target}" -lt 1 ] || [ "${sel_target}" -gt "${#libs[@]}" ]; then
                    log_error "Lựa chọn không hợp lệ."
                    continue
                fi
                local target_lib="${libs[$((sel_target-1))]}"

                local local_path=""
                read -r -p "Nhập đường dẫn tệp ISO trên máy cục bộ: " local_path
                local_path="${local_path%$'\r'}"
                if [[ -n "${local_path}" ]]; then
                    import_iso_to_content_library "${target_lib}" "${local_path}"
                fi
                ;;
            5)
                copy_or_move_iso_datastore_to_content_library
                ;;
            6)
                local ds_list=()
                mapfile -t ds_list < <(govc find -type d 2>/dev/null | sed 's|.*/||' | sort -u || true)
                local target_ds=""
                if [[ ${#ds_list[@]} -gt 0 ]]; then
                    echo "Chọn Datastore cần xem danh sách ISO:"
                    for idx in "${!ds_list[@]}"; do
                        echo "  $((idx+1))) ${ds_list[$idx]}"
                    done
                    local sel_ds=""
                    if read -r -p "Vui lòng chọn (1-${#ds_list[@]}) [1]: " sel_ds; then
                        sel_ds="${sel_ds%$'\r'}"
                        sel_ds="${sel_ds:-1}"
                        if [[ "${sel_ds}" =~ ^[0-9]+$ ]] && [ "${sel_ds}" -ge 1 ] && [ "${sel_ds}" -le "${#ds_list[@]}" ]; then
                            target_ds="${ds_list[$((sel_ds-1))]}"
                        fi
                    fi
                fi
                if [[ -z "${target_ds}" ]]; then
                    read -r -p "Nhập tên Datastore: " target_ds
                    target_ds="${target_ds%$'\r'}"
                fi
                if [[ -n "${target_ds}" ]]; then
                    log_info "Đang quét danh sách tệp .iso trên Datastore [${target_ds}]..."
                    local raw_isos
                    if raw_isos=$(govc datastore.ls -R -ds="${target_ds}" 2>&1); then
                        local isos=()
                        mapfile -t isos < <(echo "${raw_isos}" | grep -i "\.iso$" || true)
                        if [[ ${#isos[@]} -gt 0 ]]; then
                            echo "Danh sách tệp ISO trên [${target_ds}]:"
                            for idx in "${!isos[@]}"; do
                                echo "  $((idx+1))) ${isos[$idx]}"
                            done
                        else
                            log_warn "Không tìm thấy tệp .iso nào trên Datastore [${target_ds}]."
                        fi
                    else
                        log_error "Lỗi truy vấn Datastore [${target_ds}]:"
                        echo "${raw_isos}"
                    fi
                fi
                ;;
            7)
                local ds_list=()
                mapfile -t ds_list < <(govc find -type d 2>/dev/null | sed 's|.*/||' | sort -u || true)
                local target_ds=""
                if [[ ${#ds_list[@]} -gt 0 ]]; then
                    echo "Chọn Datastore đích để upload ISO:"
                    for idx in "${!ds_list[@]}"; do
                        echo "  $((idx+1))) ${ds_list[$idx]}"
                    done
                    local sel_ds=""
                    if read -r -p "Vui lòng chọn (1-${#ds_list[@]}) [1]: " sel_ds; then
                        sel_ds="${sel_ds%$'\r'}"
                        sel_ds="${sel_ds:-1}"
                        if [[ "${sel_ds}" =~ ^[0-9]+$ ]] && [ "${sel_ds}" -ge 1 ] && [ "${sel_ds}" -le "${#ds_list[@]}" ]; then
                            target_ds="${ds_list[$((sel_ds-1))]}"
                        fi
                    fi
                fi
                if [[ -z "${target_ds}" ]]; then
                    read -r -p "Nhập tên Datastore đích: " target_ds
                    target_ds="${target_ds%$'\r'}"
                fi
                if [[ -z "${target_ds}" ]]; then
                    log_error "Tên Datastore không được để trống."
                    continue
                fi

                local local_iso=""
                read -r -p "Nhập đường dẫn tệp ISO cục bộ: " local_iso
                local_iso="${local_iso%$'\r'}"
                if [[ -z "${local_iso}" || ! -f "${local_iso}" ]]; then
                    log_error "Tệp ISO cục bộ không tồn tại: ${local_iso}"
                    continue
                fi
                local iso_base
                iso_base=$(basename "${local_iso}")
                upload_iso_to_datastore "${target_ds}" "${local_iso}" "iso/${iso_base}"
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done
}
