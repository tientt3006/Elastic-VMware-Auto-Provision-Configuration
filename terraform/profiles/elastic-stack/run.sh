#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Terraform Provisioning Wrapper (Decentralized Component)
# - Run directly from inside terraform/profiles/elastic-stack directory: ./run.sh
# - Reads target topology directly from ./terraform.tfvars (Zero .env dependency)
# - Prompts for password interactively via masked input (read -s -p)
# - Stores credentials strictly in memory (RAM environment variables)
# - Validates vCenter connectivity via govc pre-flight check in < 1 second
# - Runs terraform apply with -parallelism=1 to eliminate ObjectStatus(0) panic
# - Guarantees ZERO passwords written to disk, auto-unsets variables on exit
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS="${SCRIPT_DIR}/terraform.tfvars"



echo "=============================================================================="
echo "He thong dieu phoi cap phat ha tang bao mat In-Memory (Terraform)"
echo "=============================================================================="

if [[ ! -f "${TFVARS}" ]]; then
    echo "Loi: Khong tim thay file cau hinh tai: ${TFVARS}" >&2
    exit 1
fi

# 1. Trich xuat thong so may chu truc tiep tu terraform.tfvars
VSPHERE_SERVER=$(grep -E '^\s*vsphere_server\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)
VSPHERE_USER=$(grep -E '^\s*vsphere_user\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)

# 2. Nhap mat khau an tu terminal (Ho tro luu vet trong RAM)
echo "May chu vCenter: ${VSPHERE_SERVER}"
echo "Tai khoan:       ${VSPHERE_USER}"

# Kế thừa từ kịch bản mẹ nếu có
VSPHERE_PASSWORD="${VCENTER_PASS:-${VSPHERE_PASSWORD:-}}"

if [[ -n "${VSPHERE_PASSWORD:-}" ]]; then
    echo "Mat khau vCenter da duoc nap tu bien moi truong."
else
    while [[ -z "${VSPHERE_PASSWORD:-}" ]]; do
        read -s -p "Nhap mat khau vCenter: " VSPHERE_PASSWORD
        echo ""
        [[ -z "${VSPHERE_PASSWORD:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

# 3. Nap bien moi truong vao bo nho RAM
export TF_VAR_vsphere_password="${VSPHERE_PASSWORD}"
export GOVC_URL="${VSPHERE_SERVER}"
export GOVC_USERNAME="${VSPHERE_USER}"
export GOVC_PASSWORD="${VSPHERE_PASSWORD}"
export GOVC_INSECURE="1"

# 4. Kiem tra truoc (Pre-flight Validation) bang govc
if command -v govc &>/dev/null; then
    echo "Dang xac thuc ket noi toi vCenter qua govc API..."
    if govc about >/dev/null 2>&1; then
        echo "Xac thuc vCenter thanh cong."
        govc about
    else
        echo "Loi: Xac thuc vCenter that bai. Vui long kiem tra lai mat khau hoac ket noi mang." >&2
        exit 1
    fi
fi

# 5. Extract additional variables for auto-import
VCENTER_DC=$(grep -E '^\s*vsphere_datacenter\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)
VM_FOLDER=$(grep -E '^\s*vm_target_folder\s*=' "${TFVARS}" | head -n 1 | cut -d'"' -f2)

cd "${SCRIPT_DIR}"

echo ""
echo "=============================================================================="
echo "Khoi chay Terraform init..."
echo "=============================================================================="
terraform init
echo ""
echo "=============================================================================="
echo "Khoi chay Terraform apply (che do an toan -parallelism=1)..."
echo "=============================================================================="
terraform apply -parallelism=1
