#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator Script for One-Click Deployment
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Mở tmux session nếu chưa ở trong tmux để tránh đứt kết nối SSH
if [[ -z "${TMUX:-}" ]]; then
    echo "Đang kiểm tra môi trường tmux..."
    if command -v tmux &> /dev/null; then
        echo "Khởi tạo phiên tmux (deploy_session) để chống đứt kết nối SSH..."
        # Mở tmux và chạy lại chính kịch bản này, ghi log
        exec tmux new-session -s deploy_session "bash \"$0\" \"$@\" 2>&1 | tee \"${LOG_FILE}\""
    else
        echo "CẢNH BÁO: tmux chưa được cài đặt. Tiến trình vẫn tiếp tục nhưng nếu đứt SSH sẽ bị gián đoạn."
        # Chuyển hướng stdout và stderr ra màn hình và file log
        exec > >(tee -a "${LOG_FILE}") 2>&1
    fi
else
    # Nếu đã ở trong tmux, chuyển hướng ghi log
    exec > >(tee -a "${LOG_FILE}") 2>&1
fi

echo "=============================================================================="
echo "HỆ THỐNG ĐIỀU PHỐI TỰ ĐỘNG - ONE CLICK DEPLOYMENT"
echo "Log file: ${LOG_FILE}"
echo "=============================================================================="

# 1. Cảnh báo an toàn
echo "CẢNH BÁO TRƯỚC KHI CHẠY (PRE-FLIGHT WARNING)"
echo "Đảm bảo bạn ĐÃ CHỈNH SỬA các thông tin hạ tầng sau cho phù hợp với Site khách hàng:"
echo " - Tên VM, Hostname, Network, Folder, ESXi Host, Datastore..."
echo " - Các tệp cần kiểm tra: packer_test/packer.pkrvars.hcl, terraform_test/terraform.tfvars, ansible_test/inventories/lab/hosts.yml"
echo "=============================================================================="
read -p "Đã kiểm tra kỹ và sẵn sàng? (yes/no): " READY
if [[ "${READY}" != "yes" ]]; then
    echo "Dừng tiến trình. Vui lòng kiểm tra lại cấu hình."
    exit 0
fi

# 2. Cập nhật linh động IP vCenter
echo ""
echo "--- CẤU HÌNH VCENTER CHO SITE ---"
read -p "Nhập IP hoặc FQDN của vCenter (ví dụ: 10.0.6.30 hoặc vcsa.bvnttwhcm.int): " SITE_VCSA_IP
if [[ -z "${SITE_VCSA_IP}" ]]; then
    echo "Lỗi: IP vCenter không được để trống." >&2
    exit 1
fi

echo "Đang cập nhật địa chỉ vCenter thành ${SITE_VCSA_IP}..."
sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${SCRIPT_DIR}/packer_test/packer.pkrvars.hcl"
sed -i -E "s/(vsphere_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${SCRIPT_DIR}/terraform_test/terraform.tfvars"
echo "Đã cập nhật IP vCenter thành công."

# 3. Thu thập Mật khẩu (1 LẦN DUY NHẤT)
echo ""
echo "--- THÔNG TIN BẢO MẬT (PASSWORD PROMPTS) ---"
if [[ -n "${VCENTER_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu quản trị vCenter [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export VCENTER_PASS="${INPUT_PASS}"
else
    while [[ -z "${VCENTER_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu quản trị vCenter: " VCENTER_PASS
        echo ""
        [[ -z "${VCENTER_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export VCENTER_PASS
fi

if [[ -n "${SSH_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu SSH khởi tạo (svc_admin) [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export SSH_PASS="${INPUT_PASS}"
else
    while [[ -z "${SSH_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu SSH khởi tạo (svc_admin): " SSH_PASS
        echo ""
        [[ -z "${SSH_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export SSH_PASS
fi

if [[ -n "${SUDO_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu sudo (sudo/become) [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export SUDO_PASS="${INPUT_PASS}"
else
    while [[ -z "${SUDO_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu sudo (sudo/become): " SUDO_PASS
        echo ""
        [[ -z "${SUDO_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export SUDO_PASS
fi

if [[ -n "${ELASTIC_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu siêu quản trị Elastic [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export ELASTIC_PASS="${INPUT_PASS}"
else
    while [[ -z "${ELASTIC_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu siêu quản trị Elastic: " ELASTIC_PASS
        echo ""
        [[ -z "${ELASTIC_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export ELASTIC_PASS
fi

if [[ -n "${KIBANA_PASS:-}" ]]; then
    read -s -p "Nhập mật khẩu hệ thống Kibana [Ấn Enter để giữ nguyên]: " INPUT_PASS
    echo ""
    [[ -n "${INPUT_PASS}" ]] && export KIBANA_PASS="${INPUT_PASS}"
else
    while [[ -z "${KIBANA_PASS:-}" ]]; do
        read -s -p "Nhập mật khẩu hệ thống Kibana: " KIBANA_PASS
        echo ""
        [[ -z "${KIBANA_PASS:-}" ]] && echo "Lỗi: Không được để trống." >&2
    done
    export KIBANA_PASS
fi

# 4. Thực thi tuần tự các tiến trình con
echo ""
echo "=============================================================================="
echo "BẮT ĐẦU TRIỂN KHAI (TIẾN TRÌNH 1/4): ĐÓNG GÓI PACKER TEMPLATE"
echo "=============================================================================="
cd "${SCRIPT_DIR}/packer_test"
./build_packer_secure.sh

echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 2/4: KHỞI TẠO HẠ TẦNG VSPHERE (TERRAFORM)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/terraform_test"
# Terraform không có script yêu cầu SSH_PASS, Terraform xài VSPHERE_PASSWORD
# Map VCENTER_PASS sang VSPHERE_PASSWORD để script con không hỏi lại
export VSPHERE_PASSWORD="${VCENTER_PASS}"
./run_provision_secure.sh

echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 3/4: CẤU HÌNH ELASTIC STACK (ANSIBLE)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/ansible_test"
./run_ansible_secure.sh

echo ""
echo "=============================================================================="
echo "TIẾN TRÌNH 4/4: KÍCH HOẠT QUAN SÁT TẬP TRUNG (OBSERVABILITY)"
echo "=============================================================================="
cd "${SCRIPT_DIR}/ansible_test"
./run_observability_setup.sh

echo ""
echo "=============================================================================="
echo "HOÀN TẤT QUÁ TRÌNH TRIỂN KHAI ONE-CLICK TỰ ĐỘNG."
echo "=============================================================================="
