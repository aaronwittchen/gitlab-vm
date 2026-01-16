#!/bin/bash
set -e

# Load variables from terraform.tfvars
TFVARS_FILE="${1:-terraform.tfvars}"

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo "Error: $TFVARS_FILE not found"
    exit 1
fi

# Parse values from tfvars (handles escaped quotes and special chars)
parse_tfvar() {
    local key="$1"
    local file="$2"
    grep "^${key}" "$file" | sed 's/.*= *"\(.*\)"/\1/' | sed 's/\\"/"/g'
}

PROXMOX_URL=$(parse_tfvar 'proxmox_url' "$TFVARS_FILE")
PROXMOX_USER=$(parse_tfvar 'proxmox_user' "$TFVARS_FILE")
PROXMOX_PASS=$(parse_tfvar 'proxmox_password' "$TFVARS_FILE")
PROXMOX_NODE=$(parse_tfvar 'proxmox_node' "$TFVARS_FILE")
VM_ID=$(grep '^vm_id' "$TFVARS_FILE" | grep -oE '[0-9]+')
VM_IP=$(parse_tfvar 'vm_ip' "$TFVARS_FILE" | cut -d'/' -f1)

echo "=== Pre-deployment checks ==="
echo ""

# Check 1: Is the IP already in use?
echo "[1/2] Checking if IP $VM_IP is in use..."
if ping -c 1 -W 1 "$VM_IP" &>/dev/null; then
    echo "  FAIL: IP $VM_IP is already responding to ping"
    IP_CHECK=1
else
    echo "  OK: IP $VM_IP is not in use"
    IP_CHECK=0
fi

echo ""

# Check 2: Is the VM ID already taken in Proxmox?
echo "[2/2] Checking if VM ID $VM_ID exists in Proxmox..."

# Get auth ticket
TICKET_DATA=$(curl -sk -X POST \
    --data-urlencode "username=$PROXMOX_USER" \
    --data-urlencode "password=$PROXMOX_PASS" \
    "$PROXMOX_URL/api2/json/access/ticket" 2>/dev/null)

TICKET=$(echo "$TICKET_DATA" | grep -oP '"ticket":"\K[^"]+' || true)

if [[ -z "$TICKET" ]]; then
    echo "  WARN: Could not authenticate to Proxmox API"
    echo "  (Check proxmox_url, proxmox_user, proxmox_password in tfvars)"
    VMID_CHECK=0
else
    # Check if VM exists
    API_RESPONSE=$(curl -sk -X GET \
        -H "Cookie: PVEAuthCookie=$TICKET" \
        "$PROXMOX_URL/api2/json/nodes/$PROXMOX_NODE/qemu/$VM_ID/status/current" 2>/dev/null)

    if echo "$API_RESPONSE" | grep -q '"status"'; then
        echo "  FAIL: VM ID $VM_ID already exists in Proxmox"
        VMID_CHECK=1
    else
        echo "  OK: VM ID $VM_ID is available"
        VMID_CHECK=0
    fi
fi

echo ""
echo "=== Summary ==="

if [[ $IP_CHECK -eq 1 ]] || [[ $VMID_CHECK -eq 1 ]]; then
    echo "Some checks failed. Review before running terraform apply."
    exit 1
else
    echo "All checks passed. Safe to run terraform apply."
    exit 0
fi
