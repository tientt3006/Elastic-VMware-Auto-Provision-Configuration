#!/usr/bin/env bash
# ==============================================================================
# Common Shell Utilities for VMware Multi-Product Automation Platform
# ==============================================================================
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# --- Color Definitions (Terminal-aware) ---
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    CLR_RESET="\033[0m"
    CLR_RED="\033[0;31m"
    CLR_GREEN="\033[0;32m"
    CLR_YELLOW="\033[0;33m"
    CLR_BLUE="\033[0;34m"
    CLR_CYAN="\033[0;36m"
    CLR_BOLD="\033[1m"
else
    CLR_RESET=""
    CLR_RED=""
    CLR_GREEN=""
    CLR_YELLOW=""
    CLR_BLUE=""
    CLR_CYAN=""
    CLR_BOLD=""
fi

log_info() {
    echo -e "${CLR_BLUE}[INFO]${CLR_RESET} $*"
}

log_success() {
    echo -e "${CLR_GREEN}[SUCCESS]${CLR_RESET} $*"
}

log_warn() {
    echo -e "${CLR_YELLOW}[WARN]${CLR_RESET} $*"
}

log_error() {
    echo -e "${CLR_RED}[ERROR]${CLR_RESET} $*" >&2
}

log_banner() {
    local title="$1"
    echo ""
    echo "=============================================================================="
    echo "${title}"
    echo "=============================================================================="
}

check_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "Không tìm thấy lệnh '${cmd}'."
        [[ -n "${hint}" ]] && log_error "Gợi ý: ${hint}"
        return 1
    fi
    return 0
}

prompt_if_placeholder() {
    local var_name="$1"
    local prompt_msg="$2"
    local config_file="${3:-}"
    local current_val="${!var_name:-}"

    if [[ -z "${current_val}" || "${current_val}" == *"<"*">"* ]]; then
        local new_val=""
        while [[ -z "${new_val}" || "${new_val}" == *"<"*">"* ]]; do
            if ! read -r -p "${prompt_msg} [hiện tại: ${current_val}]: " new_val; then
                echo ""
                log_warn "Không thể đọc đầu vào (EOF hoặc luồng đã đóng)."
                return 1
            fi
            new_val="${new_val%$'\r'}"
            if [[ -z "${new_val}" ]]; then
                if [[ "${current_val}" == *"<"*">"* || -z "${current_val}" ]]; then
                    log_warn "Giá trị không được để trống hoặc chứa <PLACEHOLDER>!"
                    new_val=""
                else
                    new_val="${current_val}"
                fi
            fi
        done
        printf -v "${var_name}" "%s" "${new_val}"
        if [[ -n "${config_file}" && -f "${config_file}" ]]; then
            sed -i -E "s|^${var_name}=.*|${var_name}=\"${new_val}\"|" "${config_file}"
        fi
    fi
}

prompt_password() {
    local var_name="$1"
    local prompt_msg="$2"
    local current_val="${!var_name:-}"
    local new_val=""

    if [[ -n "${current_val}" ]]; then
        read -r -s -p "${prompt_msg} [Đã lưu trong phiên, Enter để giữ nguyên]: " new_val || true
        echo ""
        new_val="${new_val%$'\r'}"
        [[ -n "${new_val}" ]] && printf -v "${var_name}" "%s" "${new_val}"
    else
        while [[ -z "${new_val}" ]]; do
            if ! read -r -s -p "${prompt_msg}: " new_val; then
                echo ""
                log_warn "Không thể đọc mật khẩu (EOF hoặc luồng đã đóng)."
                return 1
            fi
            echo ""
            new_val="${new_val%$'\r'}"
            [[ -z "${new_val}" ]] && log_warn "Mật khẩu không được để trống!"
        done
        printf -v "${var_name}" "%s" "${new_val}"
    fi
}

confirm_action() {
    local prompt_msg="$1"
    local default_val="${2:-Y}"
    local reply=""
    read -r -p "${prompt_msg} [${default_val}]: " reply || true
    reply="${reply%$'\r'}"
    reply="${reply:-${default_val}}"
    if [[ "${reply}" =~ ^[yY]([eE][sS])?$ ]]; then
        return 0
    fi
    return 1
}

init_tmux_session() {
    local session_name="$1"
    local log_file="$2"
    shift 2 || true

    # Đã ở trong phiên tmux: outer session đã điều phối tee, không lồng thêm
    if [[ -n "${TMUX:-}" ]]; then
        return 0
    fi

    # Khởi tạo tmux nếu ở trong terminal tương tác và tmux khả dụng
    if [[ -t 0 ]] && command -v tmux &> /dev/null; then
        local target_session="${session_name}"

        # Kiểm tra nếu phiên chính hoặc các phiên liên quan đã tồn tại
        local active_sessions=()
        mapfile -t active_sessions < <(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^${session_name}(_[0-9]+)?$" || true)

        if [[ ${#active_sessions[@]} -gt 0 ]]; then
            # Tìm số thứ tự kế tiếp chưa tồn tại
            local idx=2
            while tmux has-session -t "${session_name}_${idx}" 2>/dev/null; do
                ((idx++))
            done
            local next_session="${session_name}_${idx}"
            local new_opt_idx=$(( ${#active_sessions[@]} + 1 ))

            echo ""
            echo "=============================================================================="
            echo "PHÁT HIỆN PHIÊN TMUX ĐANG HOẠT ĐỘNG"
            echo "=============================================================================="
            for i in "${!active_sessions[@]}"; do
                echo "  $((i+1))) Kết nối lại vào phiên đang chạy: [${active_sessions[$i]}]"
            done
            echo "  ${new_opt_idx}) Khởi tạo phiên mới có đánh số: [${next_session}]"
            echo "  0) Hủy"

            local choice=""
            if read -r -p "Vui lòng chọn (0-${new_opt_idx}) [${new_opt_idx}]: " choice; then
                choice="${choice%$'\r'}"
                choice="${choice:-${new_opt_idx}}"
                if [[ "${choice}" == "0" ]]; then
                    echo "Hủy khởi chạy phiên làm việc."
                    exit 0
                elif [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#active_sessions[@]}" ]; then
                    local chosen_attach="${active_sessions[$((choice-1))]}"
                    echo "Đang kết nối lại vào phiên tmux [${chosen_attach}]..."
                    exec tmux attach-session -t "${chosen_attach}"
                elif [[ "${choice}" == "${new_opt_idx}" ]]; then
                    target_session="${next_session}"
                else
                    target_session="${next_session}"
                fi
            else
                target_session="${next_session}"
            fi
        fi

        echo "Khởi tạo phiên tmux (${target_session}) để chống đứt kết nối SSH..."
        exec tmux new-session -s "${target_session}" \
            "bash -c 'trap \":\" SIGINT; bash \"$0\" \"$@\" 2>&1 | tee -a \"${log_file}\"; EXIT_CODE=\${PIPESTATUS[0]}; echo \"\"; echo \"=== Kết thúc với mã thoát: \${EXIT_CODE} ===\"; echo \"Bạn đang ở trong tmux. Gõ exit để đóng, hoặc nhấn Ctrl+B rồi D để detach.\"; exec bash'"
    else
        if [[ -t 0 ]]; then
            echo "CẢNH BÁO: tmux chưa được cài đặt. Nếu đứt SSH có thể bị gián đoạn."
        fi
        if [[ -t 1 && -n "${log_file:-}" ]]; then
            exec > >(tee -a "${log_file}") 2>&1
        fi
    fi
}
