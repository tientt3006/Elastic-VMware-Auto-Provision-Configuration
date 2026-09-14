# Huong dan van hanh may ao Automation va quan ly ISO

Thu muc nay chua cac kịch ban khoi tao moi truong va quan ly tep ISO tren may ao dieu phoi tai cho (Automation Ubuntu Seed Appliance).

## 1. Danh muc kich ban

| Kich ban | Chuc nang chinh |
| :--- | :--- |
| `setup_automation_env.sh` | Cai dat toan bo bo cong cu IaC: Packer, Terraform, Ansible, govc, pyvmomi, git tren Ubuntu. |
| `download_iso.sh` | Tu dong tai tep ISO (Ubuntu Server, VCSA) kem xac thuc ma bam SHA256 va ho tro tiep tuc tai (resume). |
| `upload_iso_to_vcenter.sh` | Day tep ISO len ESXi Datastore hoac vCenter Content Library qua `govc` hoac HTTPS endpoint. |

---

## 2. Quy trinh van hanh

### Buoc 1: Cai dat bo cong cu IaC len may Automation
Thuc thi kịch ban voi quyen `sudo`:
```bash
sudo ./setup_automation_env.sh
```

Kịch ban se tu dong:
- Cai dat cac goi he thong can thiet.
- Cau hinh kho luu tru HashiCorp va cai dat `terraform`, `packer`.
- Khoi tao Python virtual environment tai `/opt/venvs/ansible-env`, cai dat `ansible`, `pyvmomi`, tao symlink he thong.
- Tai va cai dat binary `govc` moi nhat tu GitHub vao `/usr/local/bin/govc`.
- Kiem tra phien ban cac cong cu sau khi hoan tat.

---

### Buoc 2: Tai tep ISO cai dat
Tai ban Ubuntu 24.04 LTS Live Server:
```bash
./download_iso.sh --ubuntu
```

Hoac tai tep ISO tu URL noi bo:
```bash
./download_iso.sh --custom "http://mirror.internal/isos/custom.iso" "sha256_checksum_neu_co"
```
Tep ISO se duoc luu mac dinh tai thu muc `./iso_cache/`.

---

### Buoc 3: Day ISO len Datastore hoac Content Library
- **Day len Datastore tren ESXi Host 1** (truoc khi co vCenter):
  ```bash
  ./upload_iso_to_vcenter.sh \
    -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso \
    -H 10.255.242.10 \
    -u root \
    -d datastore1 \
    -p iso
  ```

- **Import vao Content Library tren vCenter** (sau khi da cai VCSA):
  ```bash
  ./upload_iso_to_vcenter.sh \
    -f ./iso_cache/ubuntu-24.04.1-live-server-amd64.iso \
    -H vcsa.lab.internal \
    -u administrator@vsphere.local \
    -l "Content-Library-Lab"
  ```
