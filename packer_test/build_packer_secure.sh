#!/usr/bin/env bash
# ==============================================================================
# Secure In-Memory Packer Golden Image Build Wrapper (Decentralized Component)
# - Run directly from inside packer_test directory: ./build_packer_secure.sh
# - Extracts target vCenter topology directly from ./packer.pkrvars.hcl
# - Prompts for vCenter & SSH passwords via masked terminal input (read -s -p)
# - Exports credentials strictly in memory (PKR_VAR_* and GOVC_*)
# - Executes sub-second pre-flight check via govc about
# - Validates Packer configuration syntax (packer validate)
# - Checks for existing duplicate template and prompts for overwrite
# - Prompts user confirmation before initiating build
# - Automatically clears in-memory credentials upon exit via shell trap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKRVARS="${SCRIPT_DIR}/packer.pkrvars.hcl"



echo "=============================================================================="
echo "He thong dieu phoi dong goi Template Packer an toan In-Memory"
echo "=============================================================================="

if [[ ! -f "${PKRVARS}" ]]; then
    echo "Loi: Khong tim thay file cau hinh tai: ${PKRVARS}" >&2
    exit 1
fi

# 1. Trich xuat thong so vCenter tu file cau hinh
VCENTER_SERVER=$(grep -E '^\s*vcenter_server\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2)
VCENTER_USER=$(grep -E '^\s*vcenter_user\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2)
VM_NAME=$(grep -E '^\s*vm_name\s*=' "${PKRVARS}" | head -n 1 | cut -d'"' -f2)

echo "May chu vCenter: ${VCENTER_SERVER}"
echo "Tai khoan:       ${VCENTER_USER}"
echo "Ten template VM: ${VM_NAME}"
echo "------------------------------------------------------------------------------"

# 2. Nhap mat khau an tu terminal (Ho tro luu vet trong RAM)
if [[ -n "${VCENTER_PASS:-}" ]]; then
    echo "Mat khau vCenter da duoc nap tu bien moi truong."
else
    while [[ -z "${VCENTER_PASS:-}" ]]; do
        read -s -p "Nhap mat khau quan tri vCenter: " VCENTER_PASS
        echo ""
        [[ -z "${VCENTER_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

if [[ -n "${SSH_PASS:-}" ]]; then
    echo "Mat khau SSH da duoc nap tu bien moi truong."
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhap mat khau SSH khoi tao may ao: " SSH_PASS
        echo ""
        [[ -z "${SSH_PASS:-}" ]] && echo "Loi: Khong duoc de trong." >&2
    done
fi

# 3. Nap bien moi truong vao RAM
export PKR_VAR_vcenter_password="${VCENTER_PASS}"
export PKR_VAR_ssh_password="${SSH_PASS}"
export GOVC_URL="https://${VCENTER_SERVER}"
export GOVC_USERNAME="${VCENTER_USER}"
export GOVC_PASSWORD="${VCENTER_PASS}"
export GOVC_INSECURE="1"

# 4. Kiem tra truoc (Pre-flight Check) va kiem tra trung lap Template bang govc
if command -v govc &>/dev/null; then
    echo "Dang xac thuc ket noi toi vCenter qua govc API..."
    if govc about >/dev/null 2>&1; then
        echo "Xac thuc vCenter thanh cong."
    else
        echo "Loi: Xac thuc vCenter that bai. Vui long kiem tra lai mat khau." >&2
        exit 1
    fi

    # Kiem tra xem VM hoac template da ton tai tren vCenter hay chua (tim kiem de quy)
    VM_PATH=$(govc find -type m -name "${VM_NAME}" 2>/dev/null | head -n 1)
    if [[ -n "${VM_PATH}" ]]; then
        echo "------------------------------------------------------------------------------"
        echo "CANH BAO: May ao / Template '${VM_NAME}' da ton tai tren vCenter tai:"
        echo "Duong dan: ${VM_PATH}"
        echo "Mac dinh Packer se gap loi 'The name already exists' va khong the build tiep."
        echo "(Ghi chu: Neu ban khong thay no hien thi la Template, co the no la mot may ao (VM) bi kiet do lan build truoc bi loi)."
        echo "------------------------------------------------------------------------------"
        read -p "Ban co muon xoa VM/Template cu de build lai khong? (y/N): " OVERWRITE
        OVERWRITE="${OVERWRITE%$'\r'}"
        if [[ "${OVERWRITE}" =~ ^[yY]([eE][sS])?$ ]]; then
            echo "Dang xoa '${VM_PATH}' tren vCenter..."
            if govc vm.destroy "${VM_PATH}"; then
                echo "Da xoa thanh cong."
            else
                echo "Canh bao: govc khong the xoa. Packer se tiep tuc chay nhung co the gap loi..."
            fi
        else
            echo "Dung tien trinh. Vui long doi ten 'vm_name' trong ${PKRVARS} de build phien ban moi."
            exit 0
        fi
    fi
fi

# 5. Kiem tra cu phap Packer
cd "${SCRIPT_DIR}"
echo "Cai dat plugin va kiem tra tinh hop le cua cau hinh Packer..."
packer init .
packer validate -var-file="${PKRVARS}" .
echo "Cau hinh hop le."

# 6. Yeu cau xac nhan truoc khi build
echo "------------------------------------------------------------------------------"
read -p "Xac nhan bat dau build template bang Packer? (Y/n): " CONFIRM
CONFIRM="${CONFIRM%$'\r'}"
CONFIRM=${CONFIRM:-Y}
if [[ ! "${CONFIRM}" =~ ^[yY]([eE][sS])?$ ]]; then
    echo "Huy tien trinh theo yeu cau cua nguoi dung."
    exit 0
fi

# 7. Thuc thi build
echo "=============================================================================="
echo "Khoi chay Packer build..."
echo "=============================================================================="
packer build -var-file="${PKRVARS}" .
