#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator Wrapper for Elastic Stack One-Click Deployment
# (Refactored to modular architecture: lib/ & products/elastic-stack/)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Nạp các thư viện nền tảng dùng chung
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "${SCRIPT_DIR}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
source "${SCRIPT_DIR}/lib/vsphere.sh"

# Khởi tạo bảo vệ phiên thực thi qua tmux
init_tmux_session "deploy_session" "${LOG_FILE}" "$@"

# Thiết lập bẫy xóa mật khẩu khỏi bộ nhớ RAM khi kết thúc
trap cleanup_secrets EXIT INT TERM

# Nạp module điều phối sản phẩm Elastic Stack và khởi chạy menu
# shellcheck source=products/elastic-stack/menu.sh
source "${SCRIPT_DIR}/products/elastic-stack/menu.sh"
run_elastic_menu
