#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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

echo -e "${BOLD}${CYAN}=== Pre-deployment checks ===${NC}"
echo ""

# Check 1: Is the IP already in use?
echo -e "${BLUE}[1/2]${NC} Checking if IP ${BOLD}$VM_IP${NC} is in use..."
if ping -c 1 -W 1 "$VM_IP" &>/dev/null; then
    echo -e "  ${RED}✗ FAIL:${NC} IP $VM_IP is already responding to ping"
    IP_CHECK=1
else
    echo -e "  ${GREEN}✓ OK:${NC} IP $VM_IP is not in use"
    IP_CHECK=0
fi

echo ""

# Check 2: Is the VM ID already taken in Proxmox?
echo -e "${BLUE}[2/2]${NC} Checking if VM ID ${BOLD}$VM_ID${NC} exists in Proxmox..."

# Get auth ticket
TICKET_DATA=$(curl -sk -X POST \
    --data-urlencode "username=$PROXMOX_USER" \
    --data-urlencode "password=$PROXMOX_PASS" \
    "$PROXMOX_URL/api2/json/access/ticket" 2>/dev/null)

TICKET=$(echo "$TICKET_DATA" | grep -oP '"ticket":"\K[^"]+' || true)

if [[ -z "$TICKET" ]]; then
    echo -e "  ${YELLOW}? WARN:${NC} Could not authenticate to Proxmox API"
    echo "  (Check proxmox_url, proxmox_user, proxmox_password in tfvars)"
    VMID_CHECK=0
else
    # Check if VM exists
    API_RESPONSE=$(curl -sk -X GET \
        -H "Cookie: PVEAuthCookie=$TICKET" \
        "$PROXMOX_URL/api2/json/nodes/$PROXMOX_NODE/qemu/$VM_ID/status/current" 2>/dev/null)

    if echo "$API_RESPONSE" | grep -q '"status"'; then
        echo -e "  ${RED}✗ FAIL:${NC} VM ID $VM_ID already exists in Proxmox"
        VMID_CHECK=1
    else
        echo -e "  ${GREEN}✓ OK:${NC} VM ID $VM_ID is available"
        VMID_CHECK=0
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}=== Summary ===${NC}"

if [[ $IP_CHECK -eq 1 ]] || [[ $VMID_CHECK -eq 1 ]]; then
    echo -e "${RED}Some checks failed.${NC} Review before running terraform apply."
    exit 1
else
    echo -e "${GREEN}All checks passed.${NC} Safe to run terraform apply."
    exit 0
fi
