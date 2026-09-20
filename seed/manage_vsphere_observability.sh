#!/usr/bin/env bash
# ==============================================================================
# Script điều phối tích hợp / hoàn tác giám sát VMware vSphere (vCenter & ESXi)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../state"
mkdir -p "${STATE_DIR}"

VARS_CONF="${SCRIPT_DIR}/../vars.conf"
if [[ -f "${VARS_CONF}" ]]; then
    source "${VARS_CONF}"
fi

ACTION="${1:-apply}"

# ==============================================================================
# HÀM BỔ TRỢ & NHẬP THAM SỐ TƯƠNG TÁC
# ==============================================================================

prompt_credentials() {

    echo "=============================================================================="
    echo "THIẾT LẬP THAM SỐ GIÁM SÁT VMWARE VSPHERE"
    echo "=============================================================================="

    if [[ -z "${SITE_VCSA_IP:-}" || "${SITE_VCSA_IP}" == *"<"*">"* ]]; then
        read -p "Địa chỉ IP vCenter Server: " SITE_VCSA_IP
        export SITE_VCSA_IP
    fi

    if [[ -z "${IP_KBN:-}" || "${IP_KBN}" == *"<"*">"* ]]; then
        read -p "Địa chỉ IP Gateway / Kibana (srv-kibana-gw): " IP_KBN
        export IP_KBN
    fi

    if [[ -z "${VCENTER_PASS:-}" ]]; then
        read -s -p "Mật khẩu vCenter Administrator (${VCENTER_USER:-administrator@vsphere.local}): " VCENTER_PASS
        echo ""
        export VCENTER_PASS
    fi

    export GOVC_URL="https://${SITE_VCSA_IP}"
    export GOVC_USERNAME="${VCENTER_USER:-administrator@vsphere.local}"
    export GOVC_PASSWORD="${VCENTER_PASS}"
    export GOVC_INSECURE="1"

    # 1. Tài khoản Service Account Read-Only
    read -p "Tài khoản Service Account Read-Only [mặc định: svc_elastic_ro]: " INPUT_USER
    SVC_USER="${INPUT_USER:-svc_elastic_ro}"

    while true; do
        read -s -p "Mật khẩu cho tài khoản '${SVC_USER}': " SVC_PASS
        echo ""
        if [[ -z "${SVC_PASS}" ]]; then
            echo "Lỗi: Mật khẩu không được để trống!" >&2
            continue
        fi
        read -s -p "Xác nhận lại mật khẩu: " SVC_PASS_CONFIRM
        echo ""
        if [[ "${SVC_PASS}" != "${SVC_PASS_CONFIRM}" ]]; then
            echo "Lỗi: Mật khẩu xác nhận không khớp! Vui lòng nhập lại." >&2
        else
            break
        fi
    done

    # 2. Mật khẩu siêu quản trị elasticsearch (elastic)
    if [[ -z "${ELASTIC_PASS:-}" ]]; then
        read -s -p "Mật khẩu siêu quản trị Elasticsearch (elastic): " ELASTIC_PASS
        echo ""
        export ELASTIC_PASS
    fi

    export SVC_USER SVC_PASS
}

# ==============================================================================
# HÀM QUẢN LÝ VSPHERE (GOVC)
# ==============================================================================

check_and_create_sso_user() {
    echo ""
    echo "--- [1/4] THIẾT LẬP TÀI KHOẢN SERVICE ACCOUNT READ-ONLY TRÊN VCENTER ---"
    
    # Kiểm tra tồn tại trong SSO
    if govc sso.user.ls 2>/dev/null | grep -qw "${SVC_USER}"; then
        echo "=> Tài khoản SSO '${SVC_USER}' đã tồn tại. Đang đồng bộ cập nhật mật khẩu..."
        govc sso.user.update -p "${SVC_PASS}" "${SVC_USER}"
        echo "=> Đã cập nhật mật khẩu SSO thành công."
    else
        echo "=> Đang tạo mới tài khoản SSO '${SVC_USER}'..."
        govc sso.user.create -p "${SVC_PASS}" "${SVC_USER}"
        echo "=> Đã tạo tài khoản SSO thành công."
    fi


    # Gán quyền ReadOnly tại root vCenter
    echo "=> Đảm bảo quyền ReadOnly tại cấp gốc (/) cho '${SVC_USER}@vsphere.local'..."
    govc permissions.set -principal "${SVC_USER}@vsphere.local" -role ReadOnly /
    echo "=> Phân quyền hoàn tất."
}

configure_esxi_syslog_with_backup() {
    echo ""
    echo "--- [2/4] KHÁM PHÁ MÁY CHỦ ESXi ĐỘNG VÀ THIẾT LẬP SYSLOG FORWARDING ---"
    local GATEWAY_IP="${IP_KBN}"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="${STATE_DIR}/esxi_syslog_backup_${TIMESTAMP}.json"
    local LATEST_LINK="${STATE_DIR}/esxi_syslog_backup_latest.json"

    local HOST_PATHS
    HOST_PATHS=$(govc find -type h)
    if [[ -z "${HOST_PATHS}" ]]; then
        echo "CẢNH BÁO: Không tìm thấy máy chủ ESXi nào qua vCenter API!" >&2
        return 0
    fi

    echo "Phát hiện các máy chủ ESXi sau:"
    echo "${HOST_PATHS}"
    echo "Bắt đầu sao lưu hiện trạng vào tệp: ${BACKUP_FILE}..."

    python3 - "${BACKUP_FILE}" "${GATEWAY_IP}" << 'PYEOF'
import sys, json

backup_path = sys.argv[1]
gw_ip = sys.argv[2]

data = {
    "target_gateway": f"udp://{gw_ip}:9525",
    "hosts": {}
}

with open(backup_path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

    for host_path in ${HOST_PATHS}; do
        local host_name
        host_name=$(basename "${host_path}")
        echo "------------------------------------------------------------------"
        echo "Xử lý máy chủ: ${host_name}"

        # 1. Đọc cấu hình hiện tại để lưu backup
        local CUR_LOGHOST
        CUR_LOGHOST=$(govc host.esxcli -host "${host_name}" system syslog config get 2>/dev/null | grep -E "Remote Host:" | sed 's/.*Remote Host:[ ]*//' || echo "")
        local CUR_FW
        CUR_FW=$(govc host.esxcli -host "${host_name}" network firewall ruleset get --ruleset-id=syslog 2>/dev/null | grep -E "Enabled:" | awk '{print $2}' || echo "false")

        python3 - "${BACKUP_FILE}" "${host_name}" "${CUR_LOGHOST}" "${CUR_FW}" << 'PYEOF'
import sys, json

backup_path, host, loghost, fw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(backup_path, "r") as f:
    data = json.load(f)

data["hosts"][host] = {
    "loghost": loghost,
    "firewall_enabled": True if fw.lower() == "true" else False
}

with open(backup_path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

        # 2. Mở Firewall ruleset syslog nếu chưa mở
        if [[ "${CUR_FW}" != "true" ]]; then
            echo "=> Mở quy tắc tường lửa Syslog trên ${host_name}..."
            govc host.esxcli -host "${host_name}" network firewall ruleset set --ruleset-id=syslog --enabled=true
            govc host.esxcli -host "${host_name}" network firewall refresh
        else
            echo "=> Tường lửa Syslog đã mở sẵn. Bỏ qua."
        fi

        # 3. Cấu hình loghost nếu chưa trỏ đúng
        local TARGET_LOGHOST="udp://${GATEWAY_IP}:9525"
        if [[ "${CUR_LOGHOST}" == *"${TARGET_LOGHOST}"* ]]; then
            echo "=> Máy chủ đã trỏ đúng tới ${TARGET_LOGHOST}. Bỏ qua nạp lại (Idempotent)."
        else
            echo "=> Thiết lập loghost -> ${TARGET_LOGHOST}..."
            govc host.esxcli -host "${host_name}" system syslog config set --loghost="${TARGET_LOGHOST}"
            govc host.esxcli -host "${host_name}" system syslog reload
            echo "=> Đã nạp lại dịch vụ vmsyslogd thành công."
        fi
    done

    cp "${BACKUP_FILE}" "${LATEST_LINK}"
    echo "------------------------------------------------------------------"
    echo "Đã lưu bản sao lưu hiện trạng tại: ${BACKUP_FILE}"
}

configure_vcsa_syslog() {
    echo ""
    echo "--- [3/4] THIẾT LẬP VCENTER APPLIANCE SYSLOG FORWARDING QUA VCENTER REST API ---"
    local GATEWAY_IP="${IP_KBN}"
    local VC_USER="${VCENTER_USER:-${GOVC_USERNAME:-administrator@vsphere.local}}"
    local VC_PASS="${VCENTER_PASS:-${GOVC_PASSWORD:-}}"

    if [[ -z "${VC_PASS}" ]]; then
        echo "CẢNH BÁO: Không có mật khẩu quản trị vCenter trong bộ nhớ. Bỏ qua cấu hình vCenter Appliance Syslog."
        return 0
    fi

    # 1. Lấy Session token từ vCenter REST API (HTTPS port 443)
    local SESSION_RESP
    SESSION_RESP=$(curl -s -k -X POST -u "${VC_USER}:${VC_PASS}" "https://${SITE_VCSA_IP}/api/session" 2>/dev/null || echo "")
    local SESSION_TOKEN=$(echo "${SESSION_RESP}" | tr -d '"')

    if [[ -n "${SESSION_TOKEN}" && "${SESSION_TOKEN}" != *"error"* && "${SESSION_TOKEN}" != *"Unauthorized"* ]]; then
        # 2. Đọc và sao lưu hiện trạng Syslog forwarding của vCenter Appliance
        local CUR_FWD
        CUR_FWD=$(curl -s -k -H "vmware-api-session-id: ${SESSION_TOKEN}" "https://${SITE_VCSA_IP}/api/appliance/logging/forwarding" 2>/dev/null || echo "[]")
        
        local LATEST_LINK="${STATE_DIR}/esxi_syslog_backup_latest.json"
        if [[ -f "${LATEST_LINK}" ]]; then
            python3 - "${LATEST_LINK}" "${CUR_FWD}" << 'PYEOF'
import sys, json
backup_file, cur_fwd_str = sys.argv[1], sys.argv[2]
try:
    with open(backup_file, "r") as f:
        data = json.load(f)
    try:
        data["vcsa_forwarding"] = json.loads(cur_fwd_str)
    except Exception:
        data["vcsa_forwarding"] = []
    with open(backup_file, "w") as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
PYEOF
        fi

        # 3. Kiểm tra Idempotent: nếu đã chứa target gateway thì bỏ qua
        if echo "${CUR_FWD}" | grep -q "${GATEWAY_IP}"; then
            echo "=> vCenter Appliance đã có cấu hình chuyển tiếp về ${GATEWAY_IP}:9525. Bỏ qua (Idempotent)."
        else
            echo "=> Thiết lập vCenter Appliance Syslog Forwarding -> udp://${GATEWAY_IP}:9525..."
            local API_STATUS
            API_STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -X PUT \
                -H "vmware-api-session-id: ${SESSION_TOKEN}" \
                -H "Content-Type: application/json" \
                -d '{"cfg_list": [{"hostname": "'"${GATEWAY_IP}"'", "port": 9525, "protocol": "UDP"}]}' \
                "https://${SITE_VCSA_IP}/api/appliance/logging/forwarding" || echo "500")

            if [[ "${API_STATUS}" =~ ^(200|204)$ ]]; then
                echo "=> Đã cấu hình vCenter Appliance chuyển tiếp Syslog về ${GATEWAY_IP}:9525 thành công."
            else
                echo "CẢNH BÁO: Cấu hình vCenter Syslog trả về HTTP ${API_STATUS}."
            fi
        fi
    else
        echo "CẢNH BÁO: Không thể xác thực vào vCenter REST API port 443. Bỏ qua vCenter Syslog."
    fi
}

run_fleet_ansible_integration() {
    echo ""
    echo "--- [4/4] CẤU HÌNH KIBANA FLEET INTEGRATION QUA ANSIBLE ---"
    cd "${SCRIPT_DIR}/../ansible/products/elastic-stack"
    export ANSIBLE_CONFIG="${SCRIPT_DIR}/../ansible/ansible.cfg"

    ansible-playbook playbooks/configure_vsphere_observability.yml \
        -e "vcenter_server=${SITE_VCSA_IP} vcenter_readonly_user=${SVC_USER} vcenter_readonly_password=${SVC_PASS} elastic_password=${ELASTIC_PASS}"

    echo ""
    echo "=============================================================================="
    echo "HOÀN TẤT TÍCH HỢP GIÁM SÁT VMWARE VSPHERE!"
    echo "Toàn bộ Metrics và Logs đang được gửi về srv-kibana-gw (${IP_KBN}:9525)."
    echo "Truy cập Kibana (http://${IP_KBN}:5601 > Dashboards) để xem trực quan hóa."
    echo "=============================================================================="
}

rollback() {
    echo "=============================================================================="
    echo "TIẾN TRÌNH HOÀN TÁC CẤU HÌNH GIÁM SÁT VMWARE VSPHERE (ROLLBACK)"
    echo "=============================================================================="

    local LATEST_BACKUP="${STATE_DIR}/esxi_syslog_backup_latest.json"
    if [[ ! -f "${LATEST_BACKUP}" ]]; then
        echo "LỖI: Không tìm thấy tệp sao lưu ${LATEST_BACKUP} để hoàn tác!" >&2
        exit 1
    fi

    if [[ -z "${SITE_VCSA_IP:-}" || "${SITE_VCSA_IP}" == *"<"*">"* ]]; then
        read -p "Địa chỉ IP vCenter Server: " SITE_VCSA_IP
        export SITE_VCSA_IP
    fi

    if [[ -z "${VCENTER_PASS:-}" ]]; then
        read -s -p "Mật khẩu vCenter Administrator (${VCENTER_USER:-administrator@vsphere.local}): " VCENTER_PASS
        echo ""
        export VCENTER_PASS
    fi

    export GOVC_URL="https://${SITE_VCSA_IP}"
    export GOVC_USERNAME="${VCENTER_USER:-administrator@vsphere.local}"
    export GOVC_PASSWORD="${VCENTER_PASS}"
    export GOVC_INSECURE="1"

    if [[ -z "${ELASTIC_PASS:-}" ]]; then
        read -s -p "Mật khẩu siêu quản trị Elasticsearch (elastic): " ELASTIC_PASS
        echo ""
        export ELASTIC_PASS
    fi

    echo "Đang nạp dữ liệu hoàn tác từ: ${LATEST_BACKUP}..."
    python3 - "${LATEST_BACKUP}" << 'PYEOF'
import sys, json, subprocess

backup_path = sys.argv[1]
with open(backup_path, "r") as f:
    data = json.load(f)

hosts = data.get("hosts", {})
for host, cfg in hosts.items():
    orig_loghost = cfg.get("loghost", "")
    orig_fw = cfg.get("firewall_enabled", False)

    print(f"------------------------------------------------------------------")
    print(f"Đang hoàn tác cho máy chủ: {host}...")
    
    # 1. Khôi phục loghost
    try:
        subprocess.run(["govc", "host.esxcli", "-host", host, "system", "syslog", "config", "set", f"--loghost={orig_loghost}"], check=True)
        subprocess.run(["govc", "host.esxcli", "-host", host, "system", "syslog", "reload"], check=True)
        print(f"=> Khôi phục loghost thành: '{orig_loghost}'")
    except Exception as e:
        print(f"=> Lỗi khôi phục loghost: {e}")

    # 2. Khôi phục firewall
    try:
        fw_val = "true" if orig_fw else "false"
        subprocess.run(["govc", "host.esxcli", "-host", host, "network", "firewall", "ruleset", "set", "--ruleset-id=syslog", f"--enabled={fw_val}"], check=True)
        subprocess.run(["govc", "host.esxcli", "-host", host, "network", "firewall", "refresh"], check=True)
        print(f"=> Khôi phục firewall ruleset syslog thành: {fw_val}")
    except Exception as e:
        print(f"=> Lỗi khôi phục firewall: {e}")
PYEOF

    # Khôi phục vCenter Appliance Syslog nếu có trong bản backup
    local VC_USER="${VCENTER_USER:-${GOVC_USERNAME:-administrator@vsphere.local}}"
    local VC_PASS="${VCENTER_PASS:-${GOVC_PASSWORD:-}}"
    if [[ -n "${VC_PASS}" ]]; then
        python3 - "${LATEST_BACKUP}" "${SITE_VCSA_IP}" "${VC_USER}" "${VC_PASS}" << 'PYEOF'
import sys, json, urllib.request, ssl, base64

backup_path, vc_ip, vc_user, vc_pass = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(backup_path, "r") as f:
        data = json.load(f)
    orig_vcsa_fwd = data.get("vcsa_forwarding")
    if orig_vcsa_fwd is not None:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        sess_url = f"https://{vc_ip}/api/session"
        auth_hdr = "Basic " + base64.b64encode(f"{vc_user}:{vc_pass}".encode()).decode()
        req = urllib.request.Request(sess_url, headers={"Authorization": auth_hdr}, method="POST")
        with urllib.request.urlopen(req, context=ctx) as resp:
            token = json.loads(resp.read().decode())

        fwd_url = f"https://{vc_ip}/api/appliance/logging/forwarding"
        payload = {"cfg_list": orig_vcsa_fwd}
        put_req = urllib.request.Request(fwd_url, data=json.dumps(payload).encode(), headers={
            "vmware-api-session-id": token,
            "Content-Type": "application/json"
        }, method="PUT")
        with urllib.request.urlopen(put_req, context=ctx) as put_resp:
            print(f"=> Khôi phục cấu hình Syslog vCenter Appliance thành công (HTTP {put_resp.status}).")
except Exception as e:
    print(f"=> Lỗi khôi phục Syslog vCenter Appliance: {e}")
PYEOF
    fi

    echo ""
    echo "--- GỠ BỎ CHÍNH SÁCH GIÁM SÁT VSPHERE TRÊN KIBANA FLEET ---"
    cd "${SCRIPT_DIR}/../ansible/products/elastic-stack"
    export ANSIBLE_CONFIG="${SCRIPT_DIR}/../ansible/ansible.cfg"

    ansible-playbook playbooks/rollback_vsphere_observability.yml \
        -e "elastic_password=${ELASTIC_PASS}" || true

    echo ""
    echo "=============================================================================="
    echo "HOÀN TẤT TOÀN BỘ CẤU HÌNH VSPHERE OBSERVABILITY THÀNH CÔNG."
    echo "=============================================================================="
}


# ==============================================================================
# MAIN
# ==============================================================================

case "${ACTION}" in
    apply)
        prompt_credentials
        check_and_create_sso_user
        configure_esxi_syslog_with_backup
        configure_vcsa_syslog
        run_fleet_ansible_integration
        ;;
    rollback)
        rollback
        ;;
    *)
        echo "Cách dùng: $0 [apply|rollback]"
        exit 1
        ;;
esac
