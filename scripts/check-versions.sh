#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}Checking for latest versions...${NC}\n"

# Function to get current version from files
get_current_talos_version() {
    grep -oP 'talos_version\s*=\s*"v?\K[0-9]+\.[0-9]+\.[0-9]+' "$PROJECT_DIR/talos-runner.tf" 2>/dev/null || echo "not found"
}

get_current_provider_version() {
    local provider=$1
    grep -A2 "source.*$provider" "$PROJECT_DIR/main.tf" | grep -oP 'version\s*=\s*"~>\s*\K[0-9]+\.[0-9]+' 2>/dev/null || echo "not found"
}

# Function to get latest version from GitHub
get_latest_github_release() {
    local repo=$1
    curl -s "https://api.github.com/repos/$repo/releases/latest" | grep -oP '"tag_name":\s*"v?\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "failed"
}

# Function to get latest provider version from Terraform Registry
get_latest_provider_version() {
    local namespace=$1
    local name=$2
    curl -s "https://registry.terraform.io/v1/providers/$namespace/$name/versions" | grep -oP '"version":\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 2>/dev/null || echo "failed"
}

# Function to get current Helm chart version from talos-runner.tf
get_current_helm_version() {
    local chart=$1
    grep -A5 "chart.*\"$chart\"" "$PROJECT_DIR/talos-runner.tf" | grep -oP 'version\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "not found"
}

# Function to get latest Helm chart version
get_latest_helm_version() {
    local repo=$1
    local chart=$2
    helm search repo "$repo/$chart" --output json 2>/dev/null | grep -oP '"version":\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "failed"
}

# Compare versions (returns 0 if update available, 1 if current)
version_gt() {
    test "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" != "$2"
}

print_version_status() {
    local name=$1
    local current=$2
    local latest=$3

    if [[ "$current" == "not found" ]]; then
        echo -e "  ${YELLOW}$name${NC}: current not found, latest: ${BLUE}$latest${NC}"
    elif [[ "$latest" == "failed" ]]; then
        echo -e "  ${YELLOW}$name${NC}: current: $current, ${RED}failed to fetch latest${NC}"
    elif [[ "$current" == "$latest" ]] || [[ "v$current" == "$latest" ]]; then
        echo -e "  ${GREEN}$name${NC}: $current ${GREEN}(up to date)${NC}"
    elif version_gt "$latest" "$current"; then
        echo -e "  ${YELLOW}$name${NC}: $current -> ${GREEN}$latest${NC} ${YELLOW}(update available)${NC}"
    else
        echo -e "  ${GREEN}$name${NC}: $current ${GREEN}(up to date)${NC}"
    fi
}

# Check Talos Linux
echo -e "${BLUE}Talos Linux:${NC}"
CURRENT_TALOS=$(get_current_talos_version)
LATEST_TALOS=$(get_latest_github_release "siderolabs/talos")
print_version_status "talos" "$CURRENT_TALOS" "$LATEST_TALOS"

echo ""

# Check Terraform Providers
echo -e "${BLUE}Terraform Providers:${NC}"

CURRENT_PROXMOX=$(get_current_provider_version "bpg/proxmox")
LATEST_PROXMOX=$(get_latest_provider_version "bpg" "proxmox")
print_version_status "bpg/proxmox" "$CURRENT_PROXMOX" "$LATEST_PROXMOX"

CURRENT_TALOS_PROVIDER=$(get_current_provider_version "siderolabs/talos")
LATEST_TALOS_PROVIDER=$(get_latest_provider_version "siderolabs" "talos")
print_version_status "siderolabs/talos" "$CURRENT_TALOS_PROVIDER" "$LATEST_TALOS_PROVIDER"

CURRENT_HELM_PROVIDER=$(get_current_provider_version "hashicorp/helm")
LATEST_HELM_PROVIDER=$(get_latest_provider_version "hashicorp" "helm")
print_version_status "hashicorp/helm" "$CURRENT_HELM_PROVIDER" "$LATEST_HELM_PROVIDER"

echo ""

# Check Helm Charts
echo -e "${BLUE}Helm Charts:${NC}"

CURRENT_CILIUM=$(get_current_helm_version "cilium")
LATEST_CILIUM=$(curl -s "https://api.github.com/repos/cilium/cilium/releases/latest" | grep -oP '"tag_name":\s*"v\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "failed")
print_version_status "cilium" "$CURRENT_CILIUM" "$LATEST_CILIUM"

CURRENT_GITLAB_RUNNER=$(get_current_helm_version "gitlab-runner")
LATEST_GITLAB_RUNNER=$(curl -s "https://gitlab.com/api/v4/projects/gitlab-org%2Fcharts%2Fgitlab-runner/releases" | grep -oP '"tag_name":\s*"v\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | head -1 || echo "failed")
print_version_status "gitlab-runner" "$CURRENT_GITLAB_RUNNER" "$LATEST_GITLAB_RUNNER"

echo ""

# Summary
echo -e "${BLUE}---${NC}"
echo -e "To update Talos version, edit: ${YELLOW}talos-runner.tf${NC} (talos_version local)"
echo -e "To update providers, edit: ${YELLOW}main.tf${NC} (version constraints)"
echo -e "To update Helm charts, edit: ${YELLOW}talos-runner.tf${NC} (helm_release versions)"
echo -e "After updating, run: ${YELLOW}terraform init -upgrade && terraform apply${NC}"
