#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Mesh VPN Zero-Downtime Deployer
# ==============================================================================
# Deploys or updates the Traefik & NetBird stack on the running VM without
# touching Terraform or recreating infrastructure.
#
# Usage:
#   ./base-vpn/deploy.sh
# ==============================================================================
set -euo pipefail

VPN_PROJECT="base-vpn"
MGMT_PROJECT="base-mgmt"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-a"
REMOTE_DIR="/opt/dpi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "🚀 [1/4] Preparing NetBird Application Configuration..."
echo "=========================================================="

# 1. Fetch or fallback Google OAuth Client ID
OAUTH_CLIENT_ID=$(gcloud secrets versions access latest --secret=google-oauth-client-id --project="$MGMT_PROJECT" 2>/dev/null || echo "PLACEHOLDER_CLIENT_ID.apps.googleusercontent.com")
OAUTH_CLIENT_SECRET=$(gcloud secrets versions access latest --secret=google-oauth-client-secret --project="$MGMT_PROJECT" 2>/dev/null || echo "PLACEHOLDER_CLIENT_SECRET")

# 2. Check if a relay secret already exists on the VM, otherwise generate a secure 64-char token
EXISTING_RELAY_SECRET=$(gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="grep '^NETBIRD_RELAY_SECRET=' $REMOTE_DIR/.env 2>/dev/null | cut -d'=' -f2- | tr -d '\"'" 2>/dev/null || true)
if [[ -n "$EXISTING_RELAY_SECRET" ]]; then
  RELAY_SECRET="$EXISTING_RELAY_SECRET"
else
  RELAY_SECRET=$(openssl rand -hex 32)
fi

# 3. Create a temporary staging directory for rendered configs
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

NETBIRD_FQDN="netbird.base.dpi.ait.ac.th"
ACME_EMAIL="admin@dpi.ait.ac.th"
SINGLE_ACCOUNT_MODE_DOMAIN="dpi.ait.ac.th"

cat << ENV_EOF > "$TMP_DIR/.env"
NETBIRD_FQDN="$NETBIRD_FQDN"
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

echo "=========================================================="
echo "📦 [2/4] Uploading Stack Configs to VM via IAP..."
echo "=========================================================="
gcloud compute scp --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap \
  "$TMP_DIR/docker-compose.yml" "$TMP_DIR/.env" \
  "$VM_NAME:/tmp/"

gcloud compute scp --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap \
  "$TMP_DIR/management.json" \
  "$VM_NAME:/tmp/management.json"

echo "=========================================================="
echo "⚡ [3/4] Installing Configs & Pulling Containers..."
echo "=========================================================="
gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="
  sudo mv /tmp/docker-compose.yml $REMOTE_DIR/docker-compose.yml
  sudo mv /tmp/.env $REMOTE_DIR/.env
  sudo mv /tmp/management.json $REMOTE_DIR/netbird/management.json
  sudo chmod 600 $REMOTE_DIR/.env $REMOTE_DIR/netbird/management.json
  sudo chown root:root $REMOTE_DIR/docker-compose.yml $REMOTE_DIR/.env $REMOTE_DIR/netbird/management.json
  
  cd $REMOTE_DIR
  sudo docker compose pull --quiet
  sudo docker compose up -d --remove-orphans
"

echo "=========================================================="
echo "✅ [4/4] Verifying Running Services..."
echo "=========================================================="
gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="
  cd $REMOTE_DIR && sudo docker compose ps
"

echo "=========================================================="
echo "🎉 NetBird Mesh VPN stack successfully deployed!"
echo "🌐 URL: https://netbird.base.dpi.ait.ac.th"
echo "=========================================================="
