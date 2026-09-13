#!/usr/bin/env bash
# ==============================================================================
# 🔑 DPI Center — NetBird VPN Host SSH Helper (Ubuntu Session via IAP)
# ==============================================================================
# Seamlessly connects over Google IAP tunnel and drops directly into the
# 'ubuntu' system user shell.
#
# Usage:
#   ./base-vpn/ssh.sh                 # Interactive shell directly as 'ubuntu'
#   ./base-vpn/ssh.sh <command>       # Execute command as 'ubuntu'
#
# Examples:
#   ./base-vpn/ssh.sh
#   ./base-vpn/ssh.sh "cd /opt/netbird && docker compose ps"
#   ./base-vpn/ssh.sh "docker logs traefik --tail 50"
# ==============================================================================
set -euo pipefail

VPN_PROJECT="base-vpn"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-b"

CYAN='\033[0;36m'
NC='\033[0m'

if [ $# -gt 0 ]; then
  echo -e "${CYAN}▶ Executing on $VM_NAME as 'ubuntu' via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$VPN_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    -- -t "sudo -i -u ubuntu bash -c $(printf '%q' "$*")"
else
  echo -e "${CYAN}▶ Connecting to $VM_NAME as 'ubuntu' via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$VPN_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    -- -t "sudo -i -u ubuntu"
fi
