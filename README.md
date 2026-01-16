# GitLab VM - Terraform Proxmox

Terraform configuration to provision a Debian 12 VM on Proxmox for hosting GitLab CE.

## Prerequisites

- Proxmox VE 7.x or 8.x
- Terraform >= 1.0
- SSH key pair generated locally
- Network access to Proxmox API

## VM Specifications

| Resource | Value |
|----------|-------|
| CPU | 4 cores |
| RAM | 8 GB |
| Disk | 80 GB |
| OS | Debian 12 (Bookworm) |

## Setup

### 1. Create Debian Cloud Template on Proxmox

SSH into your Proxmox host and run:

```bash
cd /var/lib/vz/template/iso/
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

qm create 9000 --name "debian-12-cloud" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 debian-12-genericcloud-amd64.qcow2 local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --agent enabled=1
qm set 9000 --serial0 socket --vga serial0
qm template 9000
```

Enable snippets storage:

```bash
pvesm set local --content vztmpl,iso,snippets
```

### 2. Configure Terraform Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

- `proxmox_url` - Proxmox API URL (e.g., `https://192.168.68.2:8006`)
- `proxmox_password` - Proxmox root password
- `proxmox_node` - Proxmox node name
- `vm_ip` - Static IP for the VM in CIDR notation
- `gateway` - Network gateway

### 3. Configure Cloud-Init

Edit `cloud-init/gitlab.yaml` and replace the SSH public key with your own:

```bash
cat ~/.ssh/id_ed25519.pub
```

### 4. Pre-Deployment Checks (Optional)

Run the validation script to verify the IP and VM ID are available:

```bash
./scripts/pre-check.sh
```

This checks:
- IP address is not already in use (ping test)
- VM ID does not already exist in Proxmox (API query)

### 5. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Post-Deployment: Install GitLab

### Option A: Ansible (Recommended)

```bash
cd ansible
ansible-playbook playbook.yml
```

This will:
- Install all dependencies
- Add GitLab repository
- Install and configure GitLab CE
- Display the initial root password

### Option B: Manual

SSH into the new VM:

```bash
ssh admin@192.168.68.50
```

Install GitLab CE:

```bash
# Install dependencies
sudo apt update
sudo apt install -y curl ca-certificates perl postfix

# Add GitLab repository
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash

# Install GitLab (replace URL with your domain/IP)
sudo EXTERNAL_URL="http://gitlab.local" apt install -y gitlab-ce

# Get initial root password
sudo cat /etc/gitlab/initial_root_password
```

Access GitLab at `http://192.168.68.50` and login as `root`.

## File Structure

```
gitlab-vm/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── terraform.tfvars        # Variable values (git-ignored)
├── terraform.tfvars.example# Template for terraform.tfvars
├── cloud-init/
│   └── gitlab.yaml         # Cloud-init user data
├── scripts/
│   └── pre-check.sh        # Pre-deployment validation script
├── ansible/
│   ├── ansible.cfg         # Ansible configuration
│   ├── playbook.yml        # Main playbook
│   ├── inventory/
│   │   └── hosts.yml       # Host inventory
│   ├── group_vars/
│   │   └── all.yml         # Variables
│   └── roles/
│       └── gitlab/         # GitLab role
├── .gitignore
└── README.md
```

## Destruction

To destroy the VM:

```bash
terraform destroy
```

## Troubleshooting

### VM not getting IP
- Verify cloud-init drive is attached
- Check Proxmox console for cloud-init errors
- Ensure qemu-guest-agent is running: `systemctl status qemu-guest-agent`

### Cannot connect via SSH
- Verify VM IP with Proxmox console
- Check that your SSH key matches the one in `cloud-init/gitlab.yaml`
- Ensure firewall allows SSH (port 22)

### Terraform authentication errors
- Verify `proxmox_url` includes the port (`:8006`)
- Check username format is `root@pam`
- If using self-signed cert, ensure `insecure = true` in provider config
