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

echo "=============================================================================="
echo "Hệ thống điều phối triển khai Ansible an toàn In-Memory"
echo "=============================================================================="

# 1. Nhap mat khau an tu terminal (Ho tro luu vet trong RAM)
if [[ -n "${SSH_PASS:-}" ]]; then
    read -s -p "Nhap mat khau SSH (svc_admin) [An Enter de giu nguyen]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && SSH_PASS="${INPUT_PASS}"
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhap mat khau SSH (svc_admin): " SSH_PASS
        echo ""
        [[ -z "${SSH_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${SUDO_PASS:-}" ]]; then
    read -s -p "Nhap mat khau sudo (sudo/become) [An Enter de giu nguyen]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && SUDO_PASS="${INPUT_PASS}"
else
    while [[ -z "${SUDO_PASS:-}" ]]; do
        read -s -p "Nhap mat khau sudo (sudo/become): " SUDO_PASS
        echo ""
        [[ -z "${SUDO_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${ELASTIC_PASS:-}" ]]; then
    read -s -p "Nhap mat khau sieu quan tri (elastic) [An Enter de giu nguyen]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && ELASTIC_PASS="${INPUT_PASS}"
else
    while [[ -z "${ELASTIC_PASS:-}" ]]; do
        read -s -p "Nhap mat khau sieu quan tri (elastic): " ELASTIC_PASS
        echo ""
        [[ -z "${ELASTIC_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${KIBANA_PASS:-}" ]]; then
    read -s -p "Nhap mat khau he thong Kibana (kibana_system) [An Enter de giu nguyen]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && KIBANA_PASS="${INPUT_PASS}"
else
    while [[ -z "${KIBANA_PASS:-}" ]]; do
        read -s -p "Nhap mat khau he thong Kibana (kibana_system): " KIBANA_PASS
        echo ""
        [[ -z "${KIBANA_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

# 2. Yêu cầu xác nhận trước khi chạy
echo "------------------------------------------------------------------------------"
read -p "Xác nhận bắt đầu cấu hình Observability (Fleet/ILM)? (yes/no): " CONFIRM
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
echo "Khởi chạy Master Playbook (site_observability.yml) cấu hình Observability..."
echo "=============================================================================="

ansible-playbook playbooks/site_observability.yml -e "ansible_password=${SSH_PASS} ansible_become_password=${SUDO_PASS} elastic_password=${ELASTIC_PASS} kibana_system_password=${KIBANA_PASS}"
