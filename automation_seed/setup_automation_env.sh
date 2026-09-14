#!/usr/bin/env bash
# ==============================================================================
# Script: setup_automation_env.sh
# Muc dich: Cai dat va cau hinh toan bo bo cong cu IaC tren may ao Automation Ubuntu
# Cong cu: Packer, Terraform, Ansible, govc, python3-pyvmomi, git, cac tien ich he thong
# He dieu hanh muc tieu: Ubuntu 22.04 / 24.04 LTS
# ==============================================================================
set -euo pipefail

# Kiem tra quyen root
if [[ $EUID -ne 0 ]]; then
    echo "Loi: Kich ban phai duoc thuc thi voi quyen root (sudo)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "=============================================================================="
echo "Khoi tao cai dat bo cong cu tu dong hoa ha tang tren may Ubuntu Automation"
echo "=============================================================================="

# 1. Cap nhat he thong va cai dat cac goi tien ich co ban
echo "[1/6] Cap nhat kho goi he thong va cai dat cac cong cu co ban..."
apt-get update -y
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    git \
    jq \
    unzip \
    tar \
    sshpass \
    xorriso \
    genisoimage \
    p7zip-full \
    net-tools \
    dnsutils \
    iputils-ping \
    openssl

# 2. Cai dat Terraform va Packer tu kho luu tru chinh thuc cua HashiCorp
echo "[2/6] Cai dat Terraform va Packer tu kho HashiCorp..."
if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
fi

CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" | \
    tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

apt-get update -y
apt-get install -y terraform packer

# 3. Cai dat moi truong Python va Ansible qua Virtual Environment
echo "[3/6] Cai dat Python3 va Ansible Virtual Environment..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libffi-dev \
    libssl-dev

VENV_DIR="/opt/venvs/ansible-env"
mkdir -p "$(dirname "${VENV_DIR}")"

if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
fi

# Nang cap pip va cai dat Ansible cung cac thu vien VMware
"${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel
"${VENV_DIR}/bin/pip" install \
    "ansible-core>=2.16.0" \
    "ansible>=9.0.0" \
    "pyvmomi>=8.0.2.0" \
    "requests>=2.31.0" \
    "urllib3>=2.0.0" \
    "netaddr" \
    "jmespath"

# Tao symlink de goi truc tiep ansible ma khong can kich hoat venv thu cong
ln -sf "${VENV_DIR}/bin/ansible" /usr/local/bin/ansible
ln -sf "${VENV_DIR}/bin/ansible-playbook" /usr/local/bin/ansible-playbook
ln -sf "${VENV_DIR}/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy
ln -sf "${VENV_DIR}/bin/ansible-inventory" /usr/local/bin/ansible-inventory

# Cai dat Ansible Collection cho VMware
"${VENV_DIR}/bin/ansible-galaxy" collection install community.vmware --force

# 4. Cai dat VMware govc (CLI tuong tac truc tiep vCenter/ESXi bang Go)
echo "[4/6] Cai dat VMware govc..."
GOVC_VERSION=$(curl -s "https://api.github.com/repos/vmware/govmomi/releases/latest" | jq -r '.tag_name // "v0.48.0"')
GOVC_ARCH="x86_64"
GOVC_URL="https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_${GOVC_ARCH}.tar.gz"

TMP_GOVC_DIR=$(mktemp -d)
if curl -fsSL "${GOVC_URL}" -o "${TMP_GOVC_DIR}/govc.tar.gz"; then
    tar -xzf "${TMP_GOVC_DIR}/govc.tar.gz" -C "${TMP_GOVC_DIR}"
    install -m 0755 "${TMP_GOVC_DIR}/govc" /usr/local/bin/govc
    rm -rf "${TMP_GOVC_DIR}"
    echo "govc ${GOVC_VERSION} da duoc cai dat thanh cong vao /usr/local/bin/govc."
else
    echo "Canh bao: Khong the tai govc tu internet. Kiem tra lai ket noi mang." >&2
    rm -rf "${TMP_GOVC_DIR}"
fi

# 5. Thiet lap cau hinh moi truong mac dinh
echo "[5/6] Thiet lap bien moi truong he thong..."
cat << 'EOF' > /etc/profile.d/iac_env.sh
# IaC Automation Environment Defaults
export VIRTUAL_ENV="/opt/venvs/ansible-env"
export PATH="/opt/venvs/ansible-env/bin:${PATH}"
export ANSIBLE_HOST_KEY_CHECKING="False"
export GOVC_INSECURE="true"
EOF

chmod 0644 /etc/profile.d/iac_env.sh

# 6. Kiem tra xac nhan phien ban cac cong cu da cai dat
echo "[6/6] Kiem tra ket qua cai dat..."
echo "------------------------------------------------------------------------------"
printf "%-20s: %s\n" "Git" "$(git --version)"
printf "%-20s: %s\n" "Terraform" "$(terraform version | head -n 1)"
printf "%-20s: %s\n" "Packer" "$(packer version | head -n 1)"
printf "%-20s: %s\n" "Ansible" "$(/usr/local/bin/ansible --version | head -n 1)"
printf "%-20s: %s\n" "Python" "$(python3 --version)"
if command -v govc &>/dev/null; then
    printf "%-20s: %s\n" "govc" "$(govc version)"
else
    printf "%-20s: %s\n" "govc" "Chua cai dat (can tai thu cong)"
fi
echo "------------------------------------------------------------------------------"
echo "Hoan tat thiet lap moi truong tren may Automation Ubuntu."
echo "Co the su dung truc tiep cac lenh: packer, terraform, ansible, govc."
