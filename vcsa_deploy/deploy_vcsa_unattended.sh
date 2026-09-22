#!/usr/bin/env bash
# ==============================================================================
# Script: deploy_vcsa_unattended.sh
# Muc dich: Tu dong hoa 100% qua trinh cai dat VMware vCenter Server Appliance (VCSA)
#           thong qua cong cu vcsa-deploy (VMware CLI Installer) khong can giam sat
# Co che bao mat: 
#   - Nhan mat khau qua terminal an (read -s -p)
#   - Render tep cau hinh JSON truc tiep vao RAM disk (/dev/shm)
#   - Tu dong don dep RAM va unmount ISO khi tien trinh ket thuc (trap)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vcsa_vars.env"
TEMPLATE_FILE="${SCRIPT_DIR}/templates/embedded_vcs_on_esxi.json.tpl"
MOUNT_POINT="/mnt/vcsa_iso"
RAM_SPEC_FILE="/dev/shm/vcsa_deployment_spec_$$.json"

# Kiem tra quyen root (bat buoc de mount ISO va thuc thi vcsa-deploy)
if [[ $EUID -ne 0 ]]; then
    echo "Loi: Kich ban phai duoc thuc thi voi quyen root (sudo)." >&2
    exit 1
fi

# 1. Kiem tra tep bien moi truong
if [[ ! -f "${CONFIG_FILE}" ]]; then
    if [[ -f "${SCRIPT_DIR}/vcsa_vars.env.example" ]]; then
        echo "Canh bao: Khong tim thay 'vcsa_vars.env'. Dang tao tu 'vcsa_vars.env.example'..."
        cp "${SCRIPT_DIR}/vcsa_vars.env.example" "${CONFIG_FILE}"
        echo "Vui long chinh sua thong so trong '${CONFIG_FILE}' truoc khi chay lai."
        exit 1
    else
        echo "Loi: Khong tim thay tep cau hinh 'vcsa_vars.env'." >&2
        exit 1
    fi
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Ham don dep an toan
cleanup() {
    echo ""
    echo "=============================================================================="
    echo "Tien hanh don dep tai nguyen va xoa thong tin bi mat..."
    echo "=============================================================================="
    
    # Xoa tep JSON trong RAM disk
    if [[ -f "${RAM_SPEC_FILE}" ]]; then
        shred -u -z -n 3 "${RAM_SPEC_FILE}" 2>/dev/null || rm -f "${RAM_SPEC_FILE}"
        echo "- Da tieu huy tep cau hinh trong RAM disk."
    fi

    # Unmount ISO neu dang mount
    if mountpoint -q "${MOUNT_POINT}"; then
        umount "${MOUNT_POINT}" || true
        echo "- Da go mount (umount) diem mount: ${MOUNT_POINT}."
    fi

    # Giai phong cac bien mat khau khoi RAM
    unset ESXI_PASSWORD || true
    unset VCSA_ROOT_PASSWORD || true
    unset SSO_ADMIN_PASSWORD || true
    echo "- Da giai phong bien mat khau khoi RAM."
    echo "Hoan tat don dep."
}
trap cleanup EXIT INT TERM

echo "=============================================================================="
echo "KHOI TAO TIEN TRINH CAI DAT VCENTER SERVER APPLIANCE (VCSA) TU DONG"
echo "=============================================================================="

# 2. Kiem tra tep ISO ton tai
if [[ ! -f "${VCSA_ISO_PATH}" ]]; then
    echo "Loi: Tep ISO VCSA khong ton tai tai duong dan: ${VCSA_ISO_PATH}" >&2
    echo "Goi y: Su dung kịch ban download_iso.sh de tai ISO ve may truoc." >&2
    exit 1
fi

# 3. Mount tep ISO VCSA
mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
    echo "Dang mount tep ISO vao ${MOUNT_POINT}..."
    mount -o loop,ro "${VCSA_ISO_PATH}" "${MOUNT_POINT}"
fi

VCSA_DEPLOY_BIN="${MOUNT_POINT}/vcsa-cli-installer/lin64/vcsa-deploy"
if [[ ! -f "${VCSA_DEPLOY_BIN}" ]]; then
    echo "Loi: Khong tim thay cong cu vcsa-deploy tai: ${VCSA_DEPLOY_BIN}" >&2
    exit 1
fi

# 4. Nhap cac mat khau quan tri an
echo "------------------------------------------------------------------------------"
echo "Yeu cau nhap thong tin xac thuc (Thong tin chi luu tam thoi trong RAM):"
echo "Luu y do phuc tap mat khau VMware: Toi thieu 8 ky tu, gom chu hoa, chu thuong, so va ky tu dac biet."
echo "------------------------------------------------------------------------------"

read -s -p "Nhap mat khau root cua ESXi Host (${ESXI_USERNAME}@${ESXI_HOSTNAME}): " ESXI_PASSWORD
echo ""
if [[ -z "${ESXI_PASSWORD}" ]]; then
    echo "Loi: Mat khau ESXi khong duoc de trong." >&2
    exit 1
fi

read -s -p "Nhap mat khau root cho he dieu hanh VCSA sap tao: " VCSA_ROOT_PASSWORD
echo ""
if [[ -z "${VCSA_ROOT_PASSWORD}" ]]; then
    echo "Loi: Mat khau root VCSA khong duoc de trong." >&2
    exit 1
fi

read -s -p "Nhap mat khau quan tri Single Sign-On (<VCENTER_USER>): " SSO_ADMIN_PASSWORD
echo ""
if [[ -z "${SSO_ADMIN_PASSWORD}" ]]; then
    echo "Loi: Mat khau SSO khong duoc de trong." >&2
    exit 1
fi

# 5. Sinh tep cau hinh JSON vao RAM disk (/dev/shm)
echo "Dang tao tep dac ta cau hinh VCSA trong bo nho RAM (/dev/shm)..."
export ESXI_HOSTNAME ESXI_USERNAME ESXI_PASSWORD DEPLOYMENT_NETWORK DATASTORE_NAME
export VCSA_SIZE VCSA_VM_NAME VCSA_ROOT_PASSWORD NTP_SERVERS SSO_ADMIN_PASSWORD
export SSO_DOMAIN_NAME VCSA_STATIC_IP DNS_SERVER_PRIMARY DNS_SERVER_SECONDARY
export VCSA_PREFIX VCSA_GATEWAY VCSA_FQDN

# Thay the bien moi truong vao template
envsubst < "${TEMPLATE_FILE}" > "${RAM_SPEC_FILE}"
chmod 0600 "${RAM_SPEC_FILE}"

echo "Tep dac ta cau hinh da duoc sinh an toan tai: ${RAM_SPEC_FILE}"

# 6. Thuc hien kiem tra dieu kien tien quyet (Pre-check)
echo "=============================================================================="
echo "GIAI DOAN 1: KIEM TRA DIEU KIEN TIEN QUYET (PRECHECK-ONLY)..."
echo "=============================================================================="

"${VCSA_DEPLOY_BIN}" install \
    --precheck-only \
    --accept-eula \
    --no-ssl-certificate-verification \
    "${RAM_SPEC_FILE}"

echo "=============================================================================="
echo "Kiem tra dieu kien tien quyet (Precheck) THANH CONG."
echo "Thong so trien khai du kien:"
echo "  - ESXi Host Dich     : ${ESXI_HOSTNAME}"
echo "  - Ten May Ao VCSA    : ${VCSA_VM_NAME} (Size: ${VCSA_SIZE})"
echo "  - Datastore          : ${DATASTORE_NAME}"
echo "  - Dia Chi IP Tinh    : ${VCSA_STATIC_IP}/${VCSA_PREFIX} (Gateway: ${VCSA_GATEWAY})"
echo "  - FQDN He Thong      : ${VCSA_FQDN}"
echo "  - SSO Domain         : ${SSO_DOMAIN_NAME}"
echo "=============================================================================="

read -p "Xac nhan bat dau trien khai VCSA ngay bay gio? (Y/n): " CONFIRM
CONFIRM="${CONFIRM%$'\r'}"
CONFIRM=${CONFIRM:-Y}
if [[ ! "${CONFIRM}" =~ ^[yY]([eE][sS])?$ ]]; then
    echo "Huy tien trinh theo yeu cau cua nguoi dung."
    exit 0
fi

# 7. Tien hanh cai dat thuc te
echo "=============================================================================="
echo "GIAI DOAN 2: TIEN HANH CAI DAT VCSA (UOC TINH 15 - 25 PHUT)..."
echo "=============================================================================="

"${VCSA_DEPLOY_BIN}" install \
    --accept-eula \
    --no-ssl-certificate-verification \
    "${RAM_SPEC_FILE}"

echo "=============================================================================="
echo "TRIEN KHAI VCENTER SERVER APPLIANCE THANH CONG!"
echo "Truy cap giao dien quan tri vSphere Client tai:"
echo "  URL          : https://${VCSA_FQDN}/ui hoac https://${VCSA_STATIC_IP}/ui"
echo "  Tai khoan SSO: <VCENTER_USER>"
echo "=============================================================================="
