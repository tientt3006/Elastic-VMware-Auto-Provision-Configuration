#!/usr/bin/env bash
# ==============================================================================
# Elastic Stack Configuration and Variable Generation Module
# ==============================================================================
[[ -n "${_ELASTIC_CONFIGURE_LOADED:-}" ]] && return 0
_ELASTIC_CONFIGURE_LOADED=1

PRODUCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PRODUCT_DIR}/../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "${REPO_ROOT}/lib/secrets.sh"
# shellcheck source=lib/vsphere.sh
source "${REPO_ROOT}/lib/vsphere.sh"

PKR_FILE="${REPO_ROOT}/packer/templates/ubuntu-24.04/packer.pkrvars.hcl"
TF_FILE="${REPO_ROOT}/terraform/profiles/elastic-stack/terraform.tfvars"
ANS_FILE="${REPO_ROOT}/ansible/products/elastic-stack/inventories/lab/hosts.yml"
ANS_VARS_FILE="${REPO_ROOT}/ansible/products/elastic-stack/inventories/lab/group_vars/all/main.yml"
USER_DATA_FILE="${REPO_ROOT}/packer/templates/ubuntu-24.04/http/user-data"
PRODUCT_CONF="${PRODUCT_DIR}/product.conf"

init_elastic_config_files() {
    log_banner "KIỂM TRA VÀ KHỞI TẠO TỆP CẤU HÌNH ELASTIC STACK"

    # Di chuyển hoặc khởi tạo product.conf
    if [[ ! -f "${PRODUCT_CONF}" ]]; then
        if [[ -f "${REPO_ROOT}/vars.conf" ]]; then
            log_info "Di chuyển tệp cấu hình cũ vars.conf -> ${PRODUCT_CONF}..."
            cp "${REPO_ROOT}/vars.conf" "${PRODUCT_CONF}"
        elif [[ -f "${PRODUCT_CONF}.example" ]]; then
            cp "${PRODUCT_CONF}.example" "${PRODUCT_CONF}"
            log_info "Đã tạo: ${PRODUCT_CONF}"
        fi
    fi

    [[ ! -f "${PKR_FILE}" && -f "${PKR_FILE}.example" ]] && cp "${PKR_FILE}.example" "${PKR_FILE}" && log_info "Đã tạo: ${PKR_FILE}"
    [[ ! -f "${TF_FILE}" && -f "${TF_FILE}.example" ]] && cp "${TF_FILE}.example" "${TF_FILE}" && log_info "Đã tạo: ${TF_FILE}"
    [[ ! -f "${ANS_FILE}" && -f "${ANS_FILE}.example" ]] && cp "${ANS_FILE}.example" "${ANS_FILE}" && log_info "Đã tạo: ${ANS_FILE}"
    [[ ! -f "${ANS_VARS_FILE}" && -f "${ANS_VARS_FILE}.example" ]] && cp "${ANS_VARS_FILE}.example" "${ANS_VARS_FILE}" && log_info "Đã tạo: ${ANS_VARS_FILE}"
    [[ ! -f "${USER_DATA_FILE}" && -f "${USER_DATA_FILE}.example" ]] && cp "${USER_DATA_FILE}.example" "${USER_DATA_FILE}" && log_info "Đã tạo: ${USER_DATA_FILE}"

    return 0
}

gather_elastic_vars() {
    init_elastic_config_files

    if [[ ! -f "${PRODUCT_CONF}" ]]; then
        log_error "Không tìm thấy tệp cấu hình: ${PRODUCT_CONF}"
        exit 1
    fi

    # Nạp các biến cấu hình sản phẩm
    # shellcheck source=/dev/null
    source "${PRODUCT_CONF}"

    log_banner "THIẾT LẬP THÔNG SỐ HẠ TẦNG ELASTIC STACK"
    prompt_if_placeholder "SITE_VCSA_IP" "Nhập IP của vCenter Server" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "VCENTER_USER" "Nhập tài khoản đăng nhập vCenter (vd: administrator@vsphere.local)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "ISO_DATASTORE" "Nhập tên Datastore lưu ISO" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "SSH_USER" "Nhập tài khoản SSH cho máy ảo (vd: ubuntu, sysops)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "IP_E01" "Nhập IP tĩnh cho Elasticsearch Node 1 (srv-elastic-01)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "IP_E02" "Nhập IP tĩnh cho Elasticsearch Node 2 (srv-elastic-02)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "IP_E03" "Nhập IP tĩnh cho Elasticsearch Node 3 (srv-elastic-03)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "IP_KBN" "Nhập IP tĩnh cho Kibana/Fleet Server (srv-kibana-gw)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "GW" "Nhập Default Gateway (vd: 10.0.6.1)" "${PRODUCT_CONF}" || return 1
    prompt_if_placeholder "DNS_SERVER" "Nhập IP của DNS Server (cách nhau dấu phẩy nếu nhiều hơn 1)" "${PRODUCT_CONF}" || return 1

    log_banner "THU THẬP MẬT KHẨU BẢO MẬT (LƯU TRONG BỘ NHỚ RAM)"
    prompt_password "VCENTER_PASS" "Mật khẩu quản trị vCenter" || return 1
    prompt_password "SSH_PASS" "Mật khẩu SSH (${SSH_USER})" || return 1
    prompt_password "SUDO_PASS" "Mật khẩu Sudo (đặc quyền become/root)" || return 1
    prompt_password "ELASTIC_PASS" "Mật khẩu siêu quản trị Elastic (elastic)" || return 1
    prompt_password "KIBANA_PASS" "Mật khẩu hệ thống Kibana (kibana_system)" || return 1

    export VCENTER_PASS SSH_PASS SUDO_PASS ELASTIC_PASS KIBANA_PASS
    export VSPHERE_PASSWORD="${VCENTER_PASS}"
    export TF_VAR_vsphere_password="${VCENTER_PASS}"
    export PKR_VAR_vcenter_password="${VCENTER_PASS}"
    export PKR_VAR_ssh_password="${SSH_PASS}"

    export_govc_env "${SITE_VCSA_IP}" "${VCENTER_USER}" "${VCENTER_PASS}"

    for var in SITE_VCSA_IP VCENTER_PASS ISO_DATASTORE SSH_PASS; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Biến $var không được để trống. Vui lòng kiểm tra lại cấu hình."
            return 1
        fi
    done
    return 0
}

configure_elastic_templates() {
    log_info "Bắt đầu điền thông số động vào các tệp cấu hình..."

    # Khởi tạo hoặc tái sử dụng SSH Key tiêu chuẩn (~/.ssh/id_ed25519)
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    local SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
        log_info "Tự động tạo SSH key mới: ${SSH_KEY_PATH}..."
        ssh-keygen -t ed25519 -N "" -f "${SSH_KEY_PATH}" -C ""
        chmod 600 "${SSH_KEY_PATH}"
        chmod 644 "${SSH_KEY_PATH}.pub"
    else
        log_info "Sử dụng SSH key hiện có: ${SSH_KEY_PATH}"
    fi
    local SSH_PUB_KEY
    SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

    # Cập nhật Packer HCL Variables
    if [[ -f "${PKR_FILE}" ]]; then
        sed -i -E "s/(vcenter_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_network\s*=\s*\")[^\"]+(\")/\1${PKR_NETWORK}\2/" "${PKR_FILE}"
        sed -i -E "s/(vcenter_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${PKR_FILE}"
        sed -i -E "s/(vm_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${PKR_FILE}"
        sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${PKR_FILE}"
    fi

    # Cập nhật Terraform tfvars
    if [[ -f "${TF_FILE}" ]]; then
        sed -i -E "s/(vsphere_server\s*=\s*\")[^\"]+(\")/\1${SITE_VCSA_IP}\2/" "${TF_FILE}"
        sed -i -E "s/(vsphere_user\s*=\s*\")[^\"]+(\")/\1${VCENTER_USER}\2/" "${TF_FILE}"
        sed -i -E "s/(vsphere_datacenter\s*=\s*\")[^\"]+(\")/\1${VCENTER_DC}\2/" "${TF_FILE}"
        sed -i -E "s/(vsphere_cluster\s*=\s*\")[^\"]+(\")/\1${VCENTER_CLUSTER}\2/" "${TF_FILE}"
        sed -i -E "s/(vsphere_datastore\s*=\s*\")[^\"]+(\")/\1${ISO_DATASTORE}\2/" "${TF_FILE}"
        sed -i -E "s/(vm_target_folder\s*=\s*\")[^\"]+(\")/\1${VM_FOLDER}\2/" "${TF_FILE}"
        sed -i -E "s/(vsphere_template_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"
        sed -i -E "s/(content_library_item_name\s*=\s*\")[^\"]+(\")/\1${TPL_NAME}\2/" "${TF_FILE}"

        if grep -q "ssh_username" "${TF_FILE}"; then
            sed -i -E "s/(ssh_username\s*=\s*\")[^\"]+(\")/\1${SSH_USER}\2/" "${TF_FILE}"
        else
            echo "ssh_username   = \"${SSH_USER}\"" >> "${TF_FILE}"
        fi

        if grep -q "ssh_public_key" "${TF_FILE}"; then
            sed -i -E "s|(ssh_public_key\s*=\s*\")[^\"]+(\")|\1${SSH_PUB_KEY}\2|" "${TF_FILE}"
        else
            echo "ssh_public_key = \"${SSH_PUB_KEY}\"" >> "${TF_FILE}"
        fi

        # Định dạng danh sách DNS
        local formatted_dns=""
        for ip in $(echo "${DNS_SERVER}" | tr ',' ' '); do
            if [[ -z "${formatted_dns}" ]]; then
                formatted_dns="\"${ip}\""
            else
                formatted_dns="${formatted_dns}, \"${ip}\""
            fi
        done
        sed -i -E "s/(default_dns_servers\s*=\s*).*/\1\[${formatted_dns}\]/" "${TF_FILE}"

        # Cập nhật địa chỉ IP 4 máy ảo trong Terraform bằng Python
        python3 - "${TF_FILE}" "${IP_E01}" "${IP_E02}" "${IP_E03}" "${IP_KBN}" "${GW}" "${NETMASK}" << 'PYEOF'
import sys, re
tf_file = sys.argv[1]
ips = {"elastic_01": sys.argv[2], "elastic_02": sys.argv[3], "elastic_03": sys.argv[4], "kibana_gw": sys.argv[5]}
gw = sys.argv[6]
netmask = sys.argv[7]

with open(tf_file, 'r') as f:
    content = f.read()

for key, ip in ips.items():
    pattern = r'("' + key + r'"\s*=\s*\{)(.*?)(\n\s*\})'
    def replacer(m):
        block = m.group(2)
        block = re.sub(r'(ip_address\s*=\s*")[^"]+(")', r'\g<1>' + ip + r'\2', block)
        block = re.sub(r'(gateway\s*=\s*")[^"]+(")', r'\g<1>' + gw + r'\2', block)
        block = re.sub(r'(netmask\s*=\s*)\d+', r'\g<1>' + netmask, block)
        return m.group(1) + block + m.group(3)
    content = re.sub(pattern, replacer, content, flags=re.DOTALL)

with open(tf_file, 'w') as f:
    f.write(content)
PYEOF
    fi

    # Cập nhật Ansible Configuration và Inventory
    local ans_cfg="${REPO_ROOT}/ansible/ansible.cfg"
    if [[ -f "${ans_cfg}" ]]; then
        sed -i -E "s/(remote_user\s*=\s*).*/\1${SSH_USER}/" "${ans_cfg}"
    fi

    if [[ -f "${ANS_FILE}" ]]; then
        sed -i -E "s/(ansible_user\s*:\s*).*/\1${SSH_USER}/" "${ANS_FILE}"
        sed -i "s|<IP_NODE_01>|${IP_E01}|g" "${ANS_FILE}"
        sed -i "s|<IP_NODE_02>|${IP_E02}|g" "${ANS_FILE}"
        sed -i "s|<IP_NODE_03>|${IP_E03}|g" "${ANS_FILE}"
        sed -i "s|<IP_KIBANA>|${IP_KBN}|g" "${ANS_FILE}"
        sed -i "s|<SSH_USER>|${SSH_USER}|g" "${ANS_FILE}"
        if ! grep -q "ansible_ssh_private_key_file" "${ANS_FILE}"; then
            sed -i "/ansible_user:/a \    ansible_ssh_private_key_file: ~/.ssh/id_ed25519" "${ANS_FILE}"
        fi
    fi

    # Cập nhật group_vars Ansible
    if [[ -f "${ANS_VARS_FILE}" ]]; then
        sed -i -E "s|(fleet_server_url:\s*\").*(\")|\1https://${IP_KBN}:8220\2|" "${ANS_VARS_FILE}"
        sed -i -E "s|(fleet_server_elasticsearch_url:\s*\").*(\")|\1http://${IP_E01}:9200\2|" "${ANS_VARS_FILE}"
        if grep -q "CHANGE_ME_TO_A_LONG_RANDOM_VALUE_32_CHARS" "${ANS_VARS_FILE}"; then
            local random_kbn_key
            random_kbn_key=$(openssl rand -hex 24)
            sed -i "s/CHANGE_ME_TO_A_LONG_RANDOM_VALUE_32_CHARS/${random_kbn_key}/g" "${ANS_VARS_FILE}"
        fi
    fi

    # Cập nhật Autoinstall user-data cho Packer
    if [[ -f "${USER_DATA_FILE}" ]]; then
        local ssh_hash
        ssh_hash=$(python3 -c "import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" "${SSH_PASS}" 2>/dev/null || openssl passwd -6 "${SSH_PASS}")
        sed -i -E "s|(password:\s*\").*(\")|\1${ssh_hash}\2|" "${USER_DATA_FILE}"
        sed -i -E "s/(username:\s*).*/\1${SSH_USER}/" "${USER_DATA_FILE}"
        sed -i "s|<SSH_USER>|${SSH_USER}|g" "${USER_DATA_FILE}"
        sed -i "s|<SSH_PUB_KEY>|${SSH_PUB_KEY}|g" "${USER_DATA_FILE}"
    fi

    log_success "Hoàn tất điền cấu hình đồng bộ cho Packer, Terraform và Ansible."
}
