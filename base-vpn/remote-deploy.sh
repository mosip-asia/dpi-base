#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Mesh VPN Local Orchestrator & Deployer
# ==============================================================================
# Stages stack configurations and uploads them to the VM via Google IAP tunnel,
# then executes the VM-side deployer (/opt/dpi/deploy.sh) which retrieves
# secrets directly from GCP Secret Manager via its VM service account.
#
# Usage:
#   ./base-vpn/remote-deploy.sh
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# UI & Formatting Helpers
# ------------------------------------------------------------------------------
BOLD='\033[1m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m' # No Color

log_step() {
  echo -e "\n${BOLD}${BLUE}==========================================================${NC}"
  echo -e "${BOLD}${BLUE}$1${NC}"
  echo -e "${BOLD}${BLUE}==========================================================${NC}"
}

log_cmd() {
  echo -e "${CYAN}▶ [EXEC]${NC} ${DIM}$1${NC}"
}

log_info() {
  echo -e "${GREEN}✔ [INFO]${NC} $1"
}

VPN_PROJECT="base-vpn"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-b"
REMOTE_DIR="/opt/dpi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_step "📦 [1/2] Uploading Stack Manifests to VM via IAP..."

echo -e "Target VM:   ${BOLD}$VM_NAME${NC} (Project: ${CYAN}$VPN_PROJECT${NC}, Zone: ${CYAN}$ZONE${NC})"
echo -e "Source Dir:  ${BOLD}$SCRIPT_DIR/docker${NC}"
echo ""

# Upload docker-compose.yml, management.json.template, .env.template, and deploy.sh
SCP_CMD="gcloud compute scp --project=$VPN_PROJECT --zone=$ZONE --tunnel-through-iap $SCRIPT_DIR/docker/docker-compose.yml $SCRIPT_DIR/docker/management.json.template $SCRIPT_DIR/docker/.env.template $SCRIPT_DIR/docker/deploy.sh $VM_NAME:/tmp/"
log_cmd "$SCP_CMD"
gcloud compute scp --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap \
  "$SCRIPT_DIR/docker/docker-compose.yml" \
  "$SCRIPT_DIR/docker/management.json.template" \
  "$SCRIPT_DIR/docker/.env.template" \
  "$SCRIPT_DIR/docker/deploy.sh" \
  "$VM_NAME:/tmp/"

log_info "Files uploaded to /tmp on $VM_NAME."

log_step "⚡ [2/2] Executing Remote Deployer (/opt/dpi/deploy.sh) on VM..."

RUN_DEPLOY_CMD="gcloud compute ssh $VM_NAME --project=$VPN_PROJECT --zone=$ZONE --tunnel-through-iap --command=\"sudo mv /tmp/deploy.sh $REMOTE_DIR/deploy.sh && sudo chmod +x $REMOTE_DIR/deploy.sh && sudo $REMOTE_DIR/deploy.sh\""
log_cmd "$RUN_DEPLOY_CMD"

gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="
  sudo mv /tmp/deploy.sh $REMOTE_DIR/deploy.sh
  sudo chmod +x $REMOTE_DIR/deploy.sh
  sudo $REMOTE_DIR/deploy.sh
"

log_step "🎉 Deployment Complete!"
echo -e "NetBird Mesh VPN stack is live and healthy:"
echo -e "  • ${BOLD}Primary URL:${NC}       ${GREEN}https://netbird.base.dpi.ait.ac.th${NC}"
echo -e "  • ${BOLD}Switchable Prod URL:${NC} ${CYAN}https://netbird.dpi.ait.ac.th${NC} (Active once CNAME is configured)"
echo -e "  • ${BOLD}OAuth Allowed:${NC}      ${DIM}@dpi.ait.ac.th, @ait.asia, @ait.ac.th, approved @gmail.com${NC}"
echo -e "==========================================================\n"
