#!/usr/bin/env bash
# ==============================================================================
# 🔑 DPI Center — NetBird VPN Host SSH Helper via Google IAP Tunnel
# ==============================================================================
# Usage:
#   ./base-vpn/ssh.sh                 # Interactive shell
#   ./base-vpn/ssh.sh <command>       # Execute remote command
#
# Examples:
#   ./base-vpn/ssh.sh
#   ./base-vpn/ssh.sh "cd /opt/netbird && sudo docker compose ps"
#   ./base-vpn/ssh.sh "sudo docker logs traefik --tail 50"
# ==============================================================================
set -euo pipefail

VPN_PROJECT="base-vpn"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-b"

CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

if [ $# -gt 0 ]; then
  echo -e "${CYAN}▶ Executing command on $VM_NAME via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$VPN_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    --command="$*"
else
  echo -e "${CYAN}▶ Opening interactive SSH shell on $VM_NAME via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$VPN_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap
fi
