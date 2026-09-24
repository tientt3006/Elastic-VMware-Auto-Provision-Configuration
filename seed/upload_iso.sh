#!/usr/bin/env bash
# ==============================================================================
# Script: upload_iso_to_vcenter.sh
# Muc dich: Day tep ISO tu may Automation len ESXi Datastore hoac Content Library
# Phuong thuc: 
#   1. Su dung govc datastore.upload (truc tiep len ESXi hoac vCenter)
#   2. Su dung govc library.import (day vao vSphere Content Library)
#   3. Su dung curl HTTPS toi endpoint /folder cua ESXi (khi chua co govc/vCenter)
# ==============================================================================
set -euo pipefail

cleanup() {
    [[ -t 0 ]] && stty echo icanon 2>/dev/null || true
    unset VM_TARGET_PASS || true
    unset GOVC_PASSWORD || true
}
trap cleanup EXIT INT TERM

usage() {
    cat << EOF
Cach su dung: $0 [options]

Tuy chon:
  -f, --file <PATH>           Duong dan toi tep ISO cuc bo (Bat buoc)
  -H, --host <IP/FQDN>        Dia chi IP hoac ten mien ESXi Host hoac vCenter (Bat buoc)
  -u, --user <USERNAME>       Tai khoan quan tri (Mac dinh: root)
  -d, --datastore <NAME>      Ten Datastore dich tren ESXi/vCenter (VD: datastore1)
  -p, --path <REMOTE_PATH>    Thu muc dich tren Datastore (Mac dinh: iso)
  -l, --library <LIB_NAME>    Ten vSphere Content Library (neu muon import vao Content Library)
  -m, --method <govc|curl>    Phuong thuc truyen tai (Mac dinh: govc)
  -h, --help                  Hien thi huong dan su dung

Vi du:
  # 1. Day ISO len Datastore tren ESXi Host bang govc:
  $0 -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso -H <ESXI_HOST_IP> -u root -d datastore1

  # 2. Import ISO vao Content Library tren vCenter:
  $0 -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso -H vcsa.lab.internal -u <VCENTER_USER> -l "DevOps-Content-Lib"

  # 3. Day ISO truc tiep qua HTTPS /folder (khi khong co govc):
  $0 -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso -H <ESXI_HOST_IP> -u root -d datastore1 -m curl
EOF
    exit 0
}

ISO_FILE=""
TARGET_HOST=""
TARGET_USER="root"
TARGET_DATASTORE=""
REMOTE_PATH="iso"
CONTENT_LIBRARY=""
UPLOAD_METHOD="govc"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            ISO_FILE="$2"
            shift 2
            ;;
        -H|--host)
            TARGET_HOST="$2"
            shift 2
            ;;
        -u|--user)
            TARGET_USER="$2"
            shift 2
            ;;
        -d|--datastore)
            TARGET_DATASTORE="$2"
            shift 2
            ;;
        -p|--path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        -l|--library)
            CONTENT_LIBRARY="$2"
            shift 2
            ;;
        -m|--method)
            UPLOAD_METHOD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Tham so khong hop le: $1" >&2
            usage
            ;;
    esac
done

if [[ -z "${ISO_FILE}" || ! -f "${ISO_FILE}" ]]; then
    echo "Loi: Tep ISO '${ISO_FILE}' khong ton tai hoac chua duoc chi dinh." >&2
    exit 1
fi

if [[ -z "${TARGET_HOST}" ]]; then
    echo "Loi: Phai chi dinh dia chi may chu (-H hoac --host)." >&2
    exit 1
fi

ISO_BASENAME=$(basename "${ISO_FILE}")

# Nhap mat khau an
read -s -p "Nhap mat khau cho tai khoan ${TARGET_USER}@${TARGET_HOST}: " VM_TARGET_PASS
echo ""

if [[ -z "${VM_TARGET_PASS}" ]]; then
    echo "Loi: Mat khau khong duoc de trong." >&2
    exit 1
fi

# Thuc hien day tep theo phuong thuc duoc chi dinh
if [[ -n "${CONTENT_LIBRARY}" ]]; then
    echo "=============================================================================="
    echo "Dang import ISO '${ISO_BASENAME}' vao Content Library: ${CONTENT_LIBRARY}"
    echo "vCenter Host: ${TARGET_HOST}"
    echo "=============================================================================="

    export GOVC_URL="https://${TARGET_HOST}"
    export GOVC_USERNAME="${TARGET_USER}"
    export GOVC_PASSWORD="${VM_TARGET_PASS}"
    export GOVC_INSECURE="true"

    if ! command -v govc &>/dev/null; then
        echo "Loi: Yeu cau cai dat cong cu govc de import vao Content Library." >&2
        exit 1
    fi

    govc library.import -n "${ISO_BASENAME}" "${CONTENT_LIBRARY}" "${ISO_FILE}"
    echo "Import vao Content Library thanh cong."

elif [[ "${UPLOAD_METHOD}" == "govc" ]]; then
    if [[ -z "${TARGET_DATASTORE}" ]]; then
        echo "Loi: Phai chi dinh ten Datastore (-d hoac --datastore)." >&2
        exit 1
    fi

    echo "=============================================================================="
    echo "Dang upload ISO '${ISO_BASENAME}' len Datastore: [${TARGET_DATASTORE}] ${REMOTE_PATH}/"
    echo "Dich Den: ${TARGET_HOST}"
    echo "=============================================================================="

    export GOVC_URL="https://${TARGET_HOST}"
    export GOVC_USERNAME="${TARGET_USER}"
    export GOVC_PASSWORD="${VM_TARGET_PASS}"
    export GOVC_INSECURE="true"
    export GOVC_DATASTORE="${TARGET_DATASTORE}"

    if ! command -v govc &>/dev/null; then
        echo "Loi: Khong tim thay lenh govc tren he thong. Vui long cai dat hoac dung tuy chon '-m curl'." >&2
        exit 1
    fi

    # Tao thu muc neu chua ton tai tren Datastore
    govc datastore.mkdir "${REMOTE_PATH}" || true

    # Upload tep ISO
    govc datastore.upload "${ISO_FILE}" "${REMOTE_PATH}/${ISO_BASENAME}"
    echo "Upload len Datastore qua govc thanh cong."

elif [[ "${UPLOAD_METHOD}" == "curl" ]]; then
    if [[ -z "${TARGET_DATASTORE}" ]]; then
        echo "Loi: Phai chi dinh ten Datastore (-d hoac --datastore)." >&2
        exit 1
    fi

    echo "=============================================================================="
    echo "Dang upload ISO truc tiep qua HTTPS /folder endpoint toi ESXi Host: ${TARGET_HOST}"
    echo "Datastore: ${TARGET_DATASTORE} | Thu muc: ${REMOTE_PATH}/${ISO_BASENAME}"
    echo "=============================================================================="

    UPLOAD_URL="https://${TARGET_HOST}/folder/${REMOTE_PATH}/${ISO_BASENAME}?dsName=${TARGET_DATASTORE}"

    curl -k -u "${TARGET_USER}:${VM_TARGET_PASS}" \
         --progress-bar \
         -T "${ISO_FILE}" \
         "${UPLOAD_URL}"

    echo ""
    echo "Upload truc tiep qua HTTPS endpoint /folder thanh cong."
else
    echo "Loi: Phuong thuc '${UPLOAD_METHOD}' khong duoc ho tro (chon 'govc' hoac 'curl')." >&2
    exit 1
fi
