#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Ansible Deployment Wrapper (Decentralized Component)
# - Run directly from inside ansible/products/elastic-stack directory: ./run_observability.sh
# - Prompts for SSH, Sudo, and Elastic Stack passwords via masked terminal input
# - Injects credentials into Ansible strictly in memory via extra-vars
# - Automatically clears in-memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
    echo ""
    echo "Dọn dẹp thông tin bí mật khỏi bộ nhớ RAM..."
    unset SSH_PASS SUDO_PASS ELASTIC_PASS KIBANA_PASS || true
    echo "Hoàn tất dọn dẹp."
}
trap cleanup EXIT INT TERM

echo "=============================================================================="
echo "Hệ thống điều phối triển khai Ansible an toàn In-Memory"
echo "=============================================================================="

# 1. Nhap mat khau an tu terminal (Ho tro luu vet trong RAM)
if [[ -n "${SSH_PASS:-}" ]]; then
    echo "Mat khau SSH da duoc nap tu bien moi truong."
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhap mat khau SSH: " SSH_PASS
        echo ""
        [[ -z "${SSH_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${SUDO_PASS:-}" ]]; then
    echo "Mat khau sudo da duoc nap tu bien moi truong."
else
    while [[ -z "${SUDO_PASS:-}" ]]; do
        read -s -p "Nhap mat khau sudo (sudo/become): " SUDO_PASS
        echo ""
        [[ -z "${SUDO_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${ELASTIC_PASS:-}" ]]; then
    echo "Mat khau elastic da duoc nap tu bien moi truong."
else
    while [[ -z "${ELASTIC_PASS:-}" ]]; do
        read -s -p "Nhap mat khau sieu quan tri (elastic): " ELASTIC_PASS
        echo ""
        [[ -z "${ELASTIC_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${KIBANA_PASS:-}" ]]; then
    echo "Mat khau kibana_system da duoc nap tu bien moi truong."
else
    while [[ -z "${KIBANA_PASS:-}" ]]; do
        read -s -p "Nhap mat khau he thong Kibana (kibana_system): " KIBANA_PASS
        echo ""
        [[ -z "${KIBANA_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

# 2. Yêu cầu xác nhận trước khi chạy
echo "------------------------------------------------------------------------------"
read -p "Xác nhận bắt đầu cấu hình Observability (Fleet/ILM)? (Y/n): " CONFIRM
CONFIRM="${CONFIRM%$'\r'}"
CONFIRM=${CONFIRM:-Y}
if [[ ! "${CONFIRM}" =~ ^[yY]([eE][sS])?$ ]]; then
    echo "Hủy tiến trình theo yêu cầu của người dùng."
    exit 1
fi

# 3. Kích hoạt Virtual Environment (nếu có)
if [[ -f ~/.venvs/ansible-env/bin/activate ]]; then
    source ~/.venvs/ansible-env/bin/activate
elif [[ -f /opt/venvs/ansible-env/bin/activate ]]; then
    source /opt/venvs/ansible-env/bin/activate
fi

# 4. Thực thi Ansible Playbook
cd "${SCRIPT_DIR}"
export ANSIBLE_CONFIG="${SCRIPT_DIR}/../../ansible.cfg"

echo "=============================================================================="
echo "Khởi chạy Master Playbook (site_observability.yml) cấu hình Observability..."
echo "=============================================================================="

ansible-playbook -i inventories/lab/hosts.yml playbooks/site_observability.yml -e "ansible_password=${SSH_PASS} ansible_become_password=${SUDO_PASS} elastic_password=${ELASTIC_PASS} kibana_system_password=${KIBANA_PASS}"
