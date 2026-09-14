# Module tu dong hoa cai dat VMware vCenter Server Appliance (VCSA)

Thu muc nay chua toan bo ma nguon, tep dac ta cau hinh va so tay huong dan quy trinh cai dat tu dong vCenter Server Appliance (VCSA) tren VMware ESXi Host thong qua cong cu dong lenh chinh thuc `vcsa-deploy`.

## 1. Danh muc tai nguyen trong thu muc

| Tep tin | Chuc nang |
| :--- | :--- |
| `deploy_vcsa_unattended.sh` | Kich ban dieu phoi tu dong: mount ISO VCSA, nhan mat khau qua RAM, chay pre-check va thuc thi cai dat. |
| `templates/embedded_vcs_on_esxi.json.tpl` | Mau dac ta cau hinh JSON chuan VMware cho mo hinh Embedded VCSA tren standalone ESXi. |
| `vcsa_vars.env.example` | Tep mau khai bao bien ha tang khong nhay cam (IP, FQDN, Datastore, Gateway, DNS). |
| `01_vcsa_unattended_deployment_runbook.md` | So tay quy trinh ky thuat toan dien: nguyen ly, checklist ha tang, thao tac CLI, giai thich output va troubleshooting. |

---

## 2. Quy trinh khoi chay nhanh (Quick Start)

### Buoc 1: Chuan bi tep cau hinh bien
```bash
cp vcsa_vars.env.example vcsa_vars.env
```
Chinh sua cac thong so: `ESXI_HOSTNAME`, `DATASTORE_NAME`, `VCSA_STATIC_IP`, `VCSA_FQDN`, va duong dan `VCSA_ISO_PATH`.

### Buoc 2: Kich hoat cai dat tu dong
Thuc thi kich ban voi quyen root:
```bash
sudo ./deploy_vcsa_unattended.sh
```

### Buoc 3: Nhap mat khau an theo yeu cau tren man hinh
- Mat khau root cua ESXi Host dich.
- Mat khau root cua he dieu hanh VCSA.
- Mat khau quan tri Single Sign-On (`administrator@vsphere.local`).

Kich ban se tu dong chay precheck, yeu cau xac nhan `yes`, tien hanh cai dat va tu dong xoa sach mat khau khoi RAM khi hoan tat.
