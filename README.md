# GitLab VM + Talos Runner - Terraform Proxmox

Terraform configuration to provision:
- **GitLab CE** on a Debian 12 VM with optional Cloudflare Tunnel for HTTPS
- **GitLab Runner** on a single-node Talos Linux Kubernetes cluster

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Proxmox VE                         │
│  ┌─────────────────────┐  ┌─────────────────────────┐   │
│  │   VM 1000 (Debian)  │  │   VM 1001 (Talos K8s)   │   │
│  │      GitLab CE      │  │    GitLab Runner        │   │
│  │   192.168.68.50     │  │    192.168.68.51        │   │
│  └─────────────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Proxmox VE 7.x or 8.x
- Terraform >= 1.0
- Ansible >= 2.10
- SSH key pair generated locally
- Network access to Proxmox API
- (Optional) Cloudflare account with a domain for HTTPS access

## VM Specifications

| VM | OS | CPU | RAM | Disk | Purpose |
|----|-----|-----|-----|------|---------|
| 1000 | Debian 12 | 4 cores | 16 GB | 80 GB | GitLab CE |
| 1001 | Talos Linux | 4 cores | 16 GB | 80 GB | K8s Runner |

## Quick Start

```bash
# Check for latest versions
./scripts/check-versions.sh

# Deploy everything
terraform init
terraform plan
terraform apply

# Get kubeconfig for runner cluster
terraform output -raw kubeconfig > ~/.kube/runner-config
```

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

| Variable | Description | Example |
|----------|-------------|---------|
| `proxmox_url` | Proxmox API URL | `https://192.168.1.100:8006` |
| `proxmox_password` | Proxmox root password | |
| `proxmox_node` | Proxmox node name | `pve` |
| `vm_ip` | Static IP for GitLab VM (CIDR) | `192.168.1.50/24` |
| `runner_ip` | Static IP for Talos runner | `192.168.1.51` |
| `runner_ip_cidr` | Static IP for Talos runner (CIDR) | `192.168.1.51/24` |
| `gateway` | Network gateway | `192.168.1.1` |

### 3. Pre-Deployment Checks (Optional)

Run the validation script to verify the IP and VM ID are available:

```bash
./scripts/pre-check.sh
```

This checks:
- IP address is not already in use (ping test)
- VM ID does not already exist in Proxmox (API query)

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This creates both the GitLab VM and the Talos runner cluster.

### 5. Install GitLab with Ansible

Configure Ansible secrets:

```bash
cp ansible/group_vars/all/secrets.yml.example ansible/group_vars/all/secrets.yml
```

Edit `ansible/group_vars/all/secrets.yml` with your values (see Cloudflare Tunnel section below if using HTTPS).

Update the inventory with your VM IP:

```bash
# Edit ansible/inventory/hosts.yml
ansible_host: <your-vm-ip>
```

Run the playbook:

```bash
cd ansible
ansible-playbook playbook.yml
```

This will:
- Install all dependencies
- Add GitLab repository
- Install and configure GitLab CE
- Configure Cloudflare Tunnel (if enabled)
- Display the initial root password

**Important:** After installation completes, restart the VM to ensure all services start cleanly:

```bash
ssh admin@<your-vm-ip> 'sudo reboot'
```

Wait a few minutes for GitLab to fully start after reboot.

## Talos Runner Cluster

The Talos runner is a single-node Kubernetes cluster for running GitLab CI/CD jobs.

### Accessing the Cluster

```bash
# Save kubeconfig
terraform output -raw kubeconfig > ~/.kube/runner-config

# Save talosconfig (for talosctl)
terraform output -raw talosconfig > ~/.talos/config

# Test connectivity
kubectl --kubeconfig ~/.kube/runner-config get nodes
talosctl --talosconfig ~/.talos/config health
```

### Install Cilium CNI

The cluster is configured without a default CNI. Install Cilium:

```bash
export KUBECONFIG=~/.kube/runner-config

helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.68.51 \
  --set k8sServicePort=6443
```

### Install GitLab Runner

```bash
export KUBECONFIG=~/.kube/runner-config

helm repo add gitlab https://charts.gitlab.io
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner --create-namespace \
  --set gitlabUrl=https://gitlab.yourdomain.com \
  --set runnerToken=<your-runner-token>
```

Get the runner token from GitLab: **Settings** → **CI/CD** → **Runners** → **New project runner**.

### Talos Management

```bash
# View cluster health
talosctl health

# View logs
talosctl logs kubelet

# Get cluster info
talosctl get members

# Upgrade Talos (after updating version in talos-runner.tf)
talosctl upgrade --image ghcr.io/siderolabs/installer:v1.9.2
```

## Version Management

Check for updates to Talos and Terraform providers:

```bash
./scripts/check-versions.sh
```

To update versions:
1. Edit `talos-runner.tf` for Talos version
2. Edit `main.tf` for provider versions
3. Run `terraform init -upgrade`

## Cloudflare Tunnel (HTTPS)

Cloudflare Tunnel provides secure HTTPS access to your GitLab instance without opening firewall ports.

### 1. Create Tunnel in Cloudflare

1. Go to **Cloudflare Zero Trust** → **Networks** → **Tunnels**
2. Click **Create a tunnel**
3. Select **Cloudflared** as the connector
4. Name your tunnel (e.g., `gitlab`)
5. Copy the tunnel token (starts with `eyJ...`)

### 2. Configure Public Hostname

In the tunnel configuration, add a **Public Hostname**:

| Field | Value |
|-------|-------|
| Subdomain | `gitlab` (or your choice) |
| Domain | Your Cloudflare domain |
| Type | `HTTP` |
| URL | `localhost:80` |

### 3. Configure Ansible

Edit `ansible/group_vars/all/secrets.yml`:

```yaml
gitlab_domain: "gitlab.yourdomain.com"
cloudflare_tunnel_token: "eyJ..."
```

Edit `ansible/group_vars/all/main.yml`:

```yaml
cloudflare_tunnel_enabled: true
gitlab_external_url: "https://gitlab.yourdomain.com"
```

### 4. Run Ansible

```bash
cd ansible
ansible-playbook playbook.yml
```

Your GitLab will be accessible at `https://gitlab.yourdomain.com`.

## CI/CD

This repository includes a GitHub Actions workflow for **Checkov** security scanning. It runs on every push and pull request to scan Terraform files for security misconfigurations.

## Destruction

To destroy everything:

```bash
terraform destroy
```

To destroy only the runner cluster (keep GitLab):

```bash
terraform destroy -target=talos_machine_bootstrap.runner \
  -target=talos_machine_configuration_apply.runner \
  -target=proxmox_virtual_environment_vm.talos_runner \
  -target=proxmox_virtual_environment_download_file.talos_image
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
- If host key changed: `ssh-keygen -R <vm-ip>`

### Terraform authentication errors
- Verify `proxmox_url` includes the port (`:8006`)
- Check username format is `root@pam`
- If using self-signed cert, ensure `insecure = true` in provider config
- Escape special characters in password (e.g., `\\` for backslash)

### Ansible module not found
- On Arch Linux, use a Python venv: `python -m venv ~/.local/ansible-venv && ~/.local/ansible-venv/bin/pip install ansible`
- Or use pyenv if system Python is too new

### Cloudflare Tunnel not connecting
- Verify tunnel token is correct
- Check tunnel status in Cloudflare Zero Trust dashboard
- Ensure public hostname is configured in Cloudflare
- Check logs: `ssh admin@<vm-ip> 'sudo journalctl -u cloudflared -n 50'`

### GitLab using too much memory
- Increase VM RAM in `main.tf` (recommended: 16GB)
- Run `terraform apply` and reboot VM
- Or manually adjust in Proxmox UI

### Talos node not bootstrapping
- Check Proxmox console for Talos boot messages
- Verify network connectivity: `talosctl --nodes 192.168.68.51 dmesg`
- Ensure the image downloaded correctly in Proxmox storage
- Check talosconfig endpoints match the VM IP

### Talos cluster unhealthy
- Run `talosctl health` to see specific issues
- Check etcd: `talosctl etcd members`
- View kubelet logs: `talosctl logs kubelet`
- Verify Cilium is installed and running
