#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Ansible Deployment Wrapper (Decentralized Component)
# - Run directly from inside ansible_test directory: ./run_ansible_secure.sh
# - Prompts for SSH, Sudo, and Elastic Stack passwords via masked terminal input
# - Injects credentials into Ansible strictly in memory via extra-vars
# - Automatically clears in-memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hàm dọn dẹp giải phóng biến khỏi bộ nhớ RAM
cleanup() {
    echo ""
    echo "Dọn dẹp thông tin bí mật Ansible khỏi bộ nhớ RAM..."
    unset SSH_PASS || true
    unset SUDO_PASS || true
    unset ELASTIC_PASS || true
    unset KIBANA_PASS || true
    echo "Hoàn tất dọn dẹp."
}
trap cleanup EXIT INT TERM

echo "=============================================================================="
echo "Hệ thống điều phối triển khai Ansible an toàn In-Memory"
echo "=============================================================================="

# 1. Nhập mật khẩu ẩn từ terminal
read -s -p "Nhập mật khẩu SSH (svc_admin): " SSH_PASS
echo ""
if [[ -z "${SSH_PASS}" ]]; then
    echo "Lỗi: Mật khẩu SSH không được để trống." >&2
    exit 1
fi

read -s -p "Nhập mật khẩu sudo (sudo/become): " SUDO_PASS
echo ""
if [[ -z "${SUDO_PASS}" ]]; then
    echo "Lỗi: Mật khẩu sudo không được để trống." >&2
    exit 1
fi

read -s -p "Nhập mật khẩu siêu quản trị (elastic): " ELASTIC_PASS
echo ""
if [[ -z "${ELASTIC_PASS}" ]]; then
    echo "Lỗi: Mật khẩu elastic không được để trống." >&2
    exit 1
fi

read -s -p "Nhập mật khẩu hệ thống Kibana (kibana_system): " KIBANA_PASS
echo ""
if [[ -z "${KIBANA_PASS}" ]]; then
    echo "Lỗi: Mật khẩu kibana_system không được để trống." >&2
    exit 1
fi

# 2. Yêu cầu xác nhận trước khi chạy
echo "------------------------------------------------------------------------------"
read -p "Xác nhận bắt đầu triển khai cụm Elastic Stack? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Hủy tiến trình theo yêu cầu của người dùng."
    exit 0
fi

# 3. Kích hoạt Virtual Environment (nếu có)
if [[ -f ~/.venvs/ansible-env/bin/activate ]]; then
    source ~/.venvs/ansible-env/bin/activate
fi

# 4. Thực thi Ansible Playbook
cd "${SCRIPT_DIR}"
export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

echo "=============================================================================="
echo "Khởi chạy Ansible playbook deploy_cluster.yml..."
echo "=============================================================================="

ansible-playbook playbooks/deploy_cluster.yml -e "ansible_password=${SSH_PASS} ansible_become_password=${SUDO_PASS} elastic_password=${ELASTIC_PASS} kibana_system_password=${KIBANA_PASS}"
