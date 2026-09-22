#!/usr/bin/env bash
# ==============================================================================
# Script: download_iso.sh
# Muc dich: Tu dong tai tep ISO he dieu hanh (Ubuntu Server, VCSA) ve may Automation
# Tinh nang: Kiem tra ma bam SHA256, tiep tuc tai neu bi gian doan (resume)
# ==============================================================================
set -euo pipefail

DEST_DIR="${ISO_DEST_DIR:-./iso_cache}"
mkdir -p "${DEST_DIR}"

UBUNTU_2404_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.5-live-server-amd64.iso"
UBUNTU_2404_SHA256="97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8"

ROCKY_9_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso"

usage() {
    cat << EOF
Cach su dung: $0 [options]

Tuy chon:
  -u, --ubuntu              Tai ban cai dat Ubuntu 24.04 LTS Live Server
  -r, --rocky               Tai ban cai dat Rocky Linux 9 Minimal
  -v, --vcsa <URL>          Tai ban cai dat VMware vCenter Server Appliance (VCSA) tu URL chi dinh
  -c, --custom <URL> <SHA>  Tai tep ISO bat ky tu URL va doi chieu ma bam SHA256 (tuy chon)
  -d, --dir <PATH>          Thu muc luu tru tep ISO (Mac dinh: ./iso_cache)
  -h, --help                Hien thi huong dan su dung

Vi du:
  $0 --ubuntu
  $0 --rocky
  $0 --vcsa "http://internal-mirror.local/isos/VMware-VCSA-all-8.0.2.iso"
  $0 --custom "https://example.com/custom.iso" "abc123sha256..."
EOF
    exit 0
}

download_file() {
    local url="$1"
    local filename
    filename=$(basename "${url}")
    local target_path="${DEST_DIR}/${filename}"
    local expected_sha="${2:-}"

    echo "=============================================================================="
    echo "Bat dau tai tep: ${filename}"
    echo "URL nguon       : ${url}"
    echo "Thu muc dich    : ${target_path}"
    echo "=============================================================================="

    # Kiem tra neu tep da ton tai va dung ma bam thi bo qua
    if [[ -f "${target_path}" && -n "${expected_sha}" ]]; then
        echo "Tep da ton tai cuc bo. Dang kiem tra tinh toan ven SHA256..."
        local current_sha
        current_sha=$(sha256sum "${target_path}" | awk '{print $1}')
        if [[ "${current_sha}" == "${expected_sha}" ]]; then
            echo "Ma bam SHA256 hoan toan trung khop. Khong can tai lai."
            return 0
        else
            echo "Canh bao: Ma bam khong khop. Tien hanh tai lai tep..."
        fi
    fi

    # Thuc hien tai tep voi tinh nang tiep tuc (resume)
    if command -v curl &>/dev/null; then
        curl -C - -L --progress-bar -o "${target_path}" "${url}"
    elif command -v wget &>/dev/null; then
        wget -c -O "${target_path}" "${url}"
    else
        echo "Loi: Yeu cau curl hoac wget de tai tep." >&2
        exit 1
    fi

    # Kiem tra ma bam neu co khai bao
    if [[ -n "${expected_sha}" ]]; then
        echo "Kiem tra tinh toan ven SHA256 sau khi tai..."
        local actual_sha
        actual_sha=$(sha256sum "${target_path}" | awk '{print $1}')
        if [[ "${actual_sha}" != "${expected_sha}" ]]; then
            echo "Loi: Ma bam SHA256 khong khop!" >&2
            echo "Ky vong: ${expected_sha}" >&2
            echo "Thuc te : ${actual_sha}" >&2
            exit 1
        fi
        echo "Xac thuc ma bam SHA256 thanh cong."
    fi

    echo "Hoan tat tai tep: ${target_path}"
}

if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--ubuntu)
            download_file "${UBUNTU_2404_URL}" "${UBUNTU_2404_SHA256}"
            shift
            ;;
        -r|--rocky)
            download_file "${ROCKY_9_URL}" ""
            shift
            ;;
        -v|--vcsa)
            if [[ -z "${2:-}" ]]; then
                echo "Loi: Thieu tham so URL cho tuy chon --vcsa." >&2
                exit 1
            fi
            download_file "$2" ""
            shift 2
            ;;
        -c|--custom)
            if [[ -z "${2:-}" ]]; then
                echo "Loi: Thieu tham so URL cho tuy chon --custom." >&2
                exit 1
            fi
            download_file "$2" "${3:-}"
            if [[ -n "${3:-}" && "${3:-}" != -* ]]; then
                shift 3
            else
                shift 2
            fi
            ;;
        -d|--dir)
            DEST_DIR="$2"
            mkdir -p "${DEST_DIR}"
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
