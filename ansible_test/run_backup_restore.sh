#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Backup & Disaster Recovery Wrapper for Elastic Stack
# - Run directly from inside ansible_test directory: ./run_backup_restore.sh
# - Dedicated execution tool: completely isolated from day-1 & day-2 deployments
# - Prompts for credentials via masked terminal input (In-Memory only)
# - Supports automated repository setup, SLM configuration, on-demand snapshots,
#   and snapshot restoration
# - Automatically unsets memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
    echo ""
    echo "Don dep thong tin bi mat Backup/Restore khoi bo nho RAM..."
    unset SSH_PASS || true
    unset SUDO_PASS || true
    unset ELASTIC_PASS || true
    echo "Hoan tat don dep."
}
trap cleanup EXIT INT TERM

echo "=============================================================================="
echo "He thong dieu phoi Sao luu va Phuc hoi tham hoa Elastic Stack (In-Memory)"
echo "=============================================================================="

# 1. Nhap mat khau an tu terminal
read -s -p "Nhap mat khau SSH (svc_admin): " SSH_PASS
echo ""
if [[ -z "${SSH_PASS}" ]]; then
    echo "Loi: Mat khau SSH khong duoc de trong." >&2
    exit 1
fi

read -s -p "Nhap mat khau sudo (become): " SUDO_PASS
echo ""
if [[ -z "${SUDO_PASS}" ]]; then
    echo "Loi: Mat khau sudo khong duoc de trong." >&2
    exit 1
fi

read -s -p "Nhap mat khau quan tri Elasticsearch (elastic): " ELASTIC_PASS
echo ""
if [[ -z "${ELASTIC_PASS}" ]]; then
    echo "Loi: Mat khau elastic khong duoc de trong." >&2
    exit 1
fi

# 2. Kich hoat Virtual Environment neu ton tai
if [[ -f ~/.venvs/ansible-env/bin/activate ]]; then
    source ~/.venvs/ansible-env/bin/activate
fi

cd "${SCRIPT_DIR}"
export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

# Trich xuat IP node dau tien tu inventory de goi API truc tiep khi can
ES_HOST=$(grep -E 'srv-elastic-01' -A 1 inventories/lab/hosts.yml | grep 'ansible_host' | awk '{print $2}' || echo "10.255.242.211")
ES_API="http://${ES_HOST}:9200"

echo "------------------------------------------------------------------------------"
echo "Elasticsearch Target API: ${ES_API}"
echo "------------------------------------------------------------------------------"
echo "Chon thao tac can thuc hien:"
echo "  1) Thiet lap Snapshot Repository & Chinh sach SLM tu dong (setup_backup_repository.yml)"
echo "  2) Tao ban Snapshot thu cong ngay lap tuc (On-Demand Snapshot)"
echo "  3) Khoi phuc du lieu tu mot ban Snapshot (restore_snapshot.yml)"
echo "  4) Xem danh sach cac ban Snapshot hien co tren cum"
echo "  5) Thoat"
echo "------------------------------------------------------------------------------"
read -p "Nhap lua chon (1-5): " ACTION_CHOICE

case "${ACTION_CHOICE}" in
    1)
        echo "=============================================================================="
        echo "Khoi chay Playbook thiet lap Snapshot Repository & SLM Policy..."
        echo "=============================================================================="
        ansible-playbook playbooks/setup_backup_repository.yml \
            -e "ansible_password=${SSH_PASS} ansible_become_password=${SUDO_PASS} elastic_password=${ELASTIC_PASS}"
        ;;
    2)
        DEFAULT_SNAP_NAME="manual-snap-$(date +%Y%m%d-%H%M%S)"
        read -p "Nhap ten ban Snapshot [${DEFAULT_SNAP_NAME}]: " CUSTOM_SNAP_NAME
        SNAP_NAME="${CUSTOM_SNAP_NAME:-$DEFAULT_SNAP_NAME}"

        echo "Dang gui lenh tao Snapshot '${SNAP_NAME}' toi ${ES_API}..."
        curl -s -u "elastic:${ELASTIC_PASS}" -X PUT "${ES_API}/_snapshot/elastic_backup_repo/${SNAP_NAME}?wait_for_completion=true" \
            -H "Content-Type: application/json" \
            -d '{
                "indices": ".ds-logs-fortinet.firewall-*, .ds-metrics-system.*",
                "ignore_unavailable": true,
                "include_global_state": false
            }' | jq . || true
        ;;
    3)
        echo "Cac ban Snapshot hien co trong kho 'elastic_backup_repo':"
        curl -s -u "elastic:${ELASTIC_PASS}" "${ES_API}/_cat/snapshots/elastic_backup_repo?v" || true
        echo ""
        read -p "Nhap ten ban Snapshot can khoi phuc (snapshot_name): " TARGET_SNAP
        if [[ -z "${TARGET_SNAP}" ]]; then
            echo "Loi: Ten snapshot khong duoc de trong." >&2
            exit 1
        fi

        echo "CANH BAO: Thao tac khoi phuc se tam thoi dong cac chi muc phu hop de nap lai du lieu."
        read -p "Xac nhan khoi phuc tu '${TARGET_SNAP}'? (yes/no): " CONFIRM_RESTORE
        if [[ "${CONFIRM_RESTORE}" != "yes" ]]; then
            echo "Huy thao tac khoi phuc."
            exit 0
        fi

        echo "=============================================================================="
        echo "Khoi chay Playbook restore_snapshot.yml..."
        echo "=============================================================================="
        ansible-playbook playbooks/restore_snapshot.yml \
            -e "snapshot_to_restore=${TARGET_SNAP} elastic_password=${ELASTIC_PASS}"
        ;;
    4)
        echo "Danh sach cac kho luu tru Snapshot (Repositories):"
        curl -s -u "elastic:${ELASTIC_PASS}" "${ES_API}/_snapshot" | jq . || true
        echo "------------------------------------------------------------------------------"
        echo "Danh sach cac ban Snapshot:"
        curl -s -u "elastic:${ELASTIC_PASS}" "${ES_API}/_cat/snapshots?v" || true
        echo "------------------------------------------------------------------------------"
        echo "Chinh sach SLM hien tai:"
        curl -s -u "elastic:${ELASTIC_PASS}" "${ES_API}/_slm/policy" | jq . || true
        ;;
    5)
        echo "Thoat chuong trinh."
        exit 0
        ;;
    *)
        echo "Lua chon khong hop le."
        exit 1
        ;;
esac
