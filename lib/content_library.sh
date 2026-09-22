#!/usr/bin/env bash
# ==============================================================================
# vSphere Content Library Management and ISO Resolution Module
# - Manages lifecycle of vSphere Content Libraries (list, create, inspect, import)
# - Resolves underlying Datastore paths for Packer vsphere-iso builder
# - Generic, modular, and reusable across all provisioning workflows
# ==============================================================================

# Ensure common utilities are available
CONTENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_LIB="$(cd "${CONTENT_LIB_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
[[ -f "${REPO_ROOT_LIB}/lib/common.sh" ]] && source "${REPO_ROOT_LIB}/lib/common.sh"
# shellcheck source=lib/secrets.sh
[[ -f "${REPO_ROOT_LIB}/lib/secrets.sh" ]] && source "${REPO_ROOT_LIB}/lib/secrets.sh"

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

# Liệt kê tất cả tệp ISO trong một Content Library (duyệt đệ quy item và files)
# $1: Tên Content Library
# Output: Đường dẫn tương đối dạng: ItemName/FileName.iso
get_content_library_iso_files() {
    local lib_name="$1"
    [[ -z "${lib_name}" ]] && return 1

    local items=()
    mapfile -t items < <(get_content_library_items "${lib_name}")
    if [[ ${#items[@]} -eq 0 ]]; then
        return 0
    fi

    for item in "${items[@]}"; do
        local files_raw
        files_raw=$(govc library.ls "/${lib_name}/${item}" 2>/dev/null || true)
        if [[ -n "${files_raw}" ]]; then
            while IFS= read -r fpath; do
                [[ -z "${fpath}" ]] && continue
                if [[ "${fpath}" =~ \.iso$|\.ISO$ ]]; then
                    # Trích xuất dạng: ItemName/FileName.iso
                    local rel_file
                    rel_file=$(echo "${fpath}" | sed "s|^/${lib_name}/||")
                    echo "${rel_file}"
                fi
            done <<< "${files_raw}"
        else
            # Trường hợp bản thân item kết thúc bằng .iso
            if [[ "${item}" =~ \.iso$|\.ISO$ ]]; then
                echo "${item}/${item}"
            fi
        fi
    done
}

# Lấy đường dẫn Datastore chuẩn hóa của file ISO trong Content Library
# $1: Tên Content Library
# $2: Đường dẫn file trong library (ItemName/FileName.iso hoặc ItemName)
# Output: [DatastoreName] contentlib-UUID/item-UUID/FileName.iso
resolve_content_library_iso_datastore_path() {
    local lib_name="$1"
    local file_rel_path="$2"

    [[ -z "${lib_name}" || -z "${file_rel_path}" ]] && return 1

    local full_query="/${lib_name}/${file_rel_path}"
    local ds_path
    ds_path=$(govc library.info -L -l "${full_query}" 2>/dev/null || true)

    # Nếu truy vấn file trực tiếp chưa có, thử truy vấn item
    if [[ -z "${ds_path}" || "${ds_path}" != *"["*"]"* ]]; then
        local item_only
        item_only=$(echo "${file_rel_path}" | cut -d'/' -f1)
        ds_path=$(govc library.info -L -l "/${lib_name}/${item_only}" 2>/dev/null || true)
    fi

    if [[ -z "${ds_path}" || "${ds_path}" != *"["*"]"* ]]; then
        log_error "Không thể phân giải đường dẫn Datastore cho: ${full_query}"
        return 1
    fi

    echo "${ds_path}"
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

    log_info "Đang truy vấn danh sách Content Library trên vCenter..."
    local libraries=()
    mapfile -t libraries < <(get_content_libraries)

    if [[ ${#libraries[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy Content Library nào trên vCenter."
        if confirm_action "Bạn có muốn tạo một Content Library mới ngay bây giờ không?" "Y"; then
            local new_lib_name=""
            read -r -p "Nhập tên Content Library mới [ISO_Repository]: " new_lib_name
            new_lib_name="${new_lib_name%$'\r'}"
            new_lib_name="${new_lib_name:-ISO_Repository}"

            local target_ds=""
            read -r -p "Nhập tên Datastore lưu trữ thư viện: " target_ds
            target_ds="${target_ds%$'\r'}"
            if [[ -z "${target_ds}" ]]; then
                log_error "Tên Datastore không được để trống."
                return 1
            fi

            if create_content_library "${new_lib_name}" "${target_ds}"; then
                libraries=("${new_lib_name}")
            else
                return 1
            fi
        else
            return 1
        fi
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
        echo ""
        echo "Tùy chọn xử lý:"
        echo "  1) Nạp tệp ISO từ máy cục bộ vào thư viện này"
        echo "  2) Nạp tệp ISO trực tiếp từ Internet URL vào thư viện này"
        echo "  0) Hủy"
        local add_choice=""
        read -r -p "Vui lòng chọn (0-2) [1]: " add_choice
        add_choice="${add_choice%$'\r'}"
        case "${add_choice}" in
            1)
                local local_iso=""
                read -r -p "Nhập đường dẫn tệp ISO cục bộ: " local_iso
                local_iso="${local_iso%$'\r'}"
                if import_iso_to_content_library "${chosen_lib}" "${local_iso}"; then
                    mapfile -t iso_list < <(get_content_library_iso_files "${chosen_lib}")
                else
                    return 1
                fi
                ;;
            2)
                local url_iso=""
                read -r -p "Nhập đường dẫn URL của tệp ISO: " url_iso
                url_iso="${url_iso%$'\r'}"
                if import_iso_to_content_library "${chosen_lib}" "${url_iso}"; then
                    mapfile -t iso_list < <(get_content_library_iso_files "${chosen_lib}")
                else
                    return 1
                fi
                ;;
            *)
                return 1
                ;;
        esac
    fi

    if [[ ${#iso_list[@]} -eq 0 ]]; then
        log_error "Vẫn chưa có tệp ISO nào khả dụng trong thư viện."
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
    log_info "Đang phân giải đường dẫn tầng Datastore cho: ${chosen_iso_file}..."

    local resolved_path
    resolved_path=$(resolve_content_library_iso_datastore_path "${chosen_lib}" "${chosen_iso_file}")
    if [[ -z "${resolved_path}" ]]; then
        log_error "Không thể phân giải đường dẫn Datastore của ISO trong Content Library."
        return 1
    fi

    log_success "Đường dẫn Datastore hợp lệ: ${resolved_path}"

    # Trích xuất tên Datastore từ đường dẫn dạng [DatastoreName] path...
    local lib_datastore
    lib_datastore=$(echo "${resolved_path}" | sed -E 's/^\[([^]]+)\].*/\1/' || true)

    # Cập nhật vào file packer.pkrvars.hcl
    if [[ -f "${pkr_file}" ]]; then
        # Cập nhật danh sách iso_paths
        if grep -q "^iso_paths" "${pkr_file}"; then
            sed -i -e '/^iso_paths[[:space:]]*=[[:space:]]*\[/,/^[[:space:]]*\]/c\
iso_paths = [\
  "'"${resolved_path}"'"\
]' "${pkr_file}"
            log_success "Đã cập nhật iso_paths trong ${pkr_file}:"
            log_success "  ${resolved_path}"
        fi

        # Kiểm tra và đồng bộ vcenter_datastore nếu đang chứa placeholder
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

    return 0
}

# Menu quản lý tổng thể Content Library (độc lập)
run_content_library_menu() {
    local config_file="${1:-}"

    log_banner "QUẢN LÝ KHO TÀI NGUYÊN VSPHERE CONTENT LIBRARY"

    while true; do
        echo ""
        echo "Thao tác quản trị Content Library:"
        echo "  1) Liệt kê Content Library và các tệp ISO bên trong"
        echo "  2) Tạo Content Library mới trên Datastore"
        echo "  3) Nhập tệp ISO vào Content Library (từ file cục bộ hoặc Internet URL)"
        echo "  4) Xóa Content Library"
        echo "  0) Quay lại"

        local choice=""
        if ! read -r -p "Vui lòng chọn (0-4) [1]: " choice; then
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
                read -r -p "Nhập tên Datastore lưu trữ thư viện: " target_ds
                target_ds="${target_ds%$'\r'}"
                if [[ -z "${target_ds}" ]]; then
                    log_error "Tên Datastore không được để trống."
                    continue
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

                echo "Phương thức nguồn:"
                echo "  1) Nhập đường dẫn tệp ISO cục bộ"
                echo "  2) Nhập trực tiếp URL Internet (vCenter tự động pull)"
                local src_mode=""
                read -r -p "Chọn phương thức (1-2) [1]: " src_mode
                src_mode="${src_mode%$'\r'}"
                src_mode="${src_mode:-1}"

                local src_path=""
                if [[ "${src_mode}" == "2" ]]; then
                    read -r -p "Nhập URL tệp ISO: " src_path
                else
                    read -r -p "Nhập đường dẫn tệp ISO trên máy: " src_path
                fi
                src_path="${src_path%$'\r'}"

                if [[ -n "${src_path}" ]]; then
                    import_iso_to_content_library "${target_lib}" "${src_path}"
                fi
                ;;
            4)
                log_warn "Tính năng xóa tài nguyên trên vCenter yêu cầu quyền kiểm soát cẩn trọng."
                local libs=()
                mapfile -t libs < <(get_content_libraries)
                if [[ ${#libs[@]} -eq 0 ]]; then
                    log_info "Không có Content Library nào để xóa."
                    continue
                fi
                echo "Danh sách Content Library:"
                for idx in "${!libs[@]}"; do
                    echo "  $((idx+1))) ${libs[$idx]}"
                done
                echo "  0) Hủy"
                local del_idx=""
                read -r -p "Nhập số thứ tự Content Library muốn xóa: " del_idx
                del_idx="${del_idx%$'\r'}"
                if [[ "${del_idx}" == "0" ]]; then
                    continue
                fi
                if [[ "${del_idx}" =~ ^[0-9]+$ ]] && [ "${del_idx}" -ge 1 ] && [ "${del_idx}" -le "${#libs[@]}" ]; then
                    local del_lib="${libs[$((del_idx-1))]}"
                    if confirm_action "CẢNH BÁO: Bạn có chắc chắn muốn xóa Content Library '${del_lib}' không?" "N"; then
                        if govc library.rm "${del_lib}"; then
                            log_success "Đã xóa Content Library: ${del_lib}"
                        else
                            log_error "Xóa Content Library thất bại."
                        fi
                    fi
                fi
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                ;;
        esac
    done
}
