#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Mesh VPN Local Orchestrator & Deployer
# ==============================================================================
# Resolves Google OAuth & relay secrets, stages stack configurations, uploads
# them to the VM via IAP, and executes the VM-side deployer (/opt/dpi/deploy.sh).
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

log_warn() {
  echo -e "${YELLOW}⚠ [WARN]${NC} $1"
}

VPN_PROJECT="base-vpn"
MGMT_PROJECT="base-mgmt"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-b"
REMOTE_DIR="/opt/dpi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NETBIRD_FQDN="netbird.base.dpi.ait.ac.th"
PROD_FQDN="netbird.dpi.ait.ac.th"
ACME_EMAIL="admin@dpi.ait.ac.th"
SINGLE_ACCOUNT_MODE_DOMAIN="dpi.ait.ac.th"

log_step "🚀 [1/3] Preparing NetBird Application Configuration..."

echo -e "Target VM:      ${BOLD}$VM_NAME${NC} (Project: ${CYAN}$VPN_PROJECT${NC}, Zone: ${CYAN}$ZONE${NC})"
echo -e "Base FQDN:      ${BOLD}$NETBIRD_FQDN${NC}"
echo -e "Prod FQDN:      ${BOLD}$PROD_FQDN${NC}"
echo -e "Account Domain: ${BOLD}$SINGLE_ACCOUNT_MODE_DOMAIN${NC}"
echo ""

# 1. Fetch Google OAuth Client ID & Secret from Secret Manager
OAUTH_ID_CMD="gcloud secrets versions access latest --secret=google-oauth-client-id --project=$MGMT_PROJECT"
log_cmd "$OAUTH_ID_CMD"
OAUTH_CLIENT_ID=$($OAUTH_ID_CMD 2>/dev/null || echo "PLACEHOLDER_CLIENT_ID.apps.googleusercontent.com")
if [[ "$OAUTH_CLIENT_ID" == "PLACEHOLDER"* ]]; then
  log_warn "Secret 'google-oauth-client-id' not found in $MGMT_PROJECT; using placeholder."
else
  log_info "Retrieved Google OAuth Client ID: ${OAUTH_CLIENT_ID:0:18}... (masked)"
fi

OAUTH_SECRET_CMD="gcloud secrets versions access latest --secret=google-oauth-client-secret --project=$MGMT_PROJECT"
log_cmd "$OAUTH_SECRET_CMD"
OAUTH_CLIENT_SECRET=$($OAUTH_SECRET_CMD 2>/dev/null || echo "PLACEHOLDER_CLIENT_SECRET")
if [[ "$OAUTH_CLIENT_SECRET" == "PLACEHOLDER"* ]]; then
  log_warn "Secret 'google-oauth-client-secret' not found in $MGMT_PROJECT; using placeholder."
else
  log_info "Retrieved Google OAuth Client Secret: [secret loaded]"
fi

# 2. Check existing relay secret or generate new one
CHECK_RELAY_CMD="gcloud compute ssh $VM_NAME --project=$VPN_PROJECT --zone=$ZONE --tunnel-through-iap --command=\"grep '^NETBIRD_RELAY_SECRET=' $REMOTE_DIR/.env 2>/dev/null | cut -d'=' -f2- | tr -d '\\\"'\""
log_cmd "$CHECK_RELAY_CMD"
EXISTING_RELAY_SECRET=$(gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="grep '^NETBIRD_RELAY_SECRET=' $REMOTE_DIR/.env 2>/dev/null | cut -d'=' -f2- | tr -d '\"'" 2>/dev/null || true)

if [[ -n "$EXISTING_RELAY_SECRET" ]]; then
  RELAY_SECRET="$EXISTING_RELAY_SECRET"
  log_info "Reusing existing NetBird Relay Secret from VM."
else
  RELAY_SECRET=$(openssl rand -hex 32)
  log_info "Generated new 64-character NetBird Relay Secret."
fi

# 3. Create temporary staging directory and render configs
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log_info "Rendering configuration files into staging directory: $TMP_DIR"

cat << ENV_EOF > "$TMP_DIR/.env"
NETBIRD_FQDN="$NETBIRD_FQDN"
PROD_FQDN="$PROD_FQDN"
ACME_EMAIL="$ACME_EMAIL"
GOOGLE_OAUTH_CLIENT_ID="$OAUTH_CLIENT_ID"
GOOGLE_OAUTH_CLIENT_SECRET="$OAUTH_CLIENT_SECRET"
NETBIRD_RELAY_SECRET="$RELAY_SECRET"
SINGLE_ACCOUNT_MODE_DOMAIN="$SINGLE_ACCOUNT_MODE_DOMAIN"
ENV_EOF

sed -e "s|\$GOOGLE_OAUTH_CLIENT_ID|$OAUTH_CLIENT_ID|g" \
    -e "s|\$GOOGLE_OAUTH_CLIENT_SECRET|$OAUTH_CLIENT_SECRET|g" \
    -e "s|\$NETBIRD_RELAY_SECRET|$RELAY_SECRET|g" \
    -e "s|\$SINGLE_ACCOUNT_MODE_DOMAIN|$SINGLE_ACCOUNT_MODE_DOMAIN|g" \
    -e "s|\$NETBIRD_FQDN|$NETBIRD_FQDN|g" \
    "$SCRIPT_DIR/docker/management.json.template" > "$TMP_DIR/management.json"

cp "$SCRIPT_DIR/docker/docker-compose.yml" "$TMP_DIR/docker-compose.yml"
cp "$SCRIPT_DIR/docker/deploy.sh" "$TMP_DIR/deploy.sh"
chmod +x "$TMP_DIR/deploy.sh"
log_info "Staged .env, docker-compose.yml, management.json, and deploy.sh successfully."

log_step "📦 [2/3] Uploading Stack Configs to VM via IAP..."

SCP_CMD="gcloud compute scp --project=$VPN_PROJECT --zone=$ZONE --tunnel-through-iap $TMP_DIR/docker-compose.yml $TMP_DIR/.env $TMP_DIR/management.json $TMP_DIR/deploy.sh $VM_NAME:/tmp/"
log_cmd "$SCP_CMD"
gcloud compute scp --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap \
  "$TMP_DIR/docker-compose.yml" "$TMP_DIR/.env" "$TMP_DIR/management.json" "$TMP_DIR/deploy.sh" \
  "$VM_NAME:/tmp/"

log_info "Uploaded stack files to /tmp on $VM_NAME."

log_step "⚡ [3/3] Executing Remote Deployer (/opt/dpi/deploy.sh) on VM..."

RUN_DEPLOY_CMD="gcloud compute ssh $VM_NAME --project=$VPN_PROJECT --zone=$ZONE --tunnel-through-iap --command=\"sudo mv /tmp/deploy.sh $REMOTE_DIR/deploy.sh && sudo chmod +x $REMOTE_DIR/deploy.sh && sudo $REMOTE_DIR/deploy.sh\""
log_cmd "$RUN_DEPLOY_CMD"

gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="
  sudo mv /tmp/deploy.sh $REMOTE_DIR/deploy.sh
  sudo chmod +x $REMOTE_DIR/deploy.sh
  sudo $REMOTE_DIR/deploy.sh
"

log_step "🎉 Deployment Complete!"
echo -e "NetBird Mesh VPN stack is live and healthy:"
echo -e "  • ${BOLD}Primary URL:${NC}       ${GREEN}https://$NETBIRD_FQDN${NC}"
echo -e "  • ${BOLD}Switchable Prod URL:${NC} ${CYAN}https://$PROD_FQDN${NC} (Active once CNAME is configured)"
echo -e "  • ${BOLD}OAuth Allowed:${NC}      ${DIM}@$SINGLE_ACCOUNT_MODE_DOMAIN, @ait.asia, @ait.ac.th, approved @gmail.com${NC}"
echo -e "==========================================================\n"
