#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Stack VM Service Deployer
# ==============================================================================
# This script executes directly on the VM (/opt/dpi/deploy.sh).
# It pulls secrets from Secret Manager using the VM's service account,
# renders /opt/dpi/.env and /opt/dpi/netbird/management.json, configures swap,
# and starts/updates the Docker Compose stack.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Formatting Helpers
# ------------------------------------------------------------------------------
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✔ [VM]${NC} $1"; }
log_cmd()  { echo -e "${CYAN}▶ [VM RUN]${NC} ${DIM}$1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ [VM WARN]${NC} $1"; }

DPI_DIR="/opt/dpi"
MGMT_PROJECT="base-mgmt"
NETBIRD_FQDN="netbird.base.dpi.ait.ac.th"
PROD_FQDN="netbird.dpi.ait.ac.th"
ACME_EMAIL="admin@dpi.ait.ac.th"
SINGLE_ACCOUNT_MODE_DOMAIN="dpi.ait.ac.th"

mkdir -p "$DPI_DIR/netbird" "$DPI_DIR/traefik" "$DPI_DIR/scripts"

# 1. Move uploaded files from /tmp to /opt/dpi
echo -e "\n${BOLD}--- [1/5] Syncing Application Manifests ---${NC}"
if [ -f /tmp/docker-compose.yml ]; then
  log_cmd "mv /tmp/docker-compose.yml $DPI_DIR/docker-compose.yml"
  sudo mv /tmp/docker-compose.yml "$DPI_DIR/docker-compose.yml"
fi

if [ -f /tmp/management.json.template ]; then
  log_cmd "mv /tmp/management.json.template $DPI_DIR/netbird/management.json.template"
  sudo mv /tmp/management.json.template "$DPI_DIR/netbird/management.json.template"
fi

# 2. Fetch Secrets from Secret Manager via VM Attached Service Account
echo -e "\n${BOLD}--- [2/5] Resolving Secrets from GCP Secret Manager ---${NC}"
log_info "Fetching Google OAuth Client ID & Secret from project '$MGMT_PROJECT'..."

OAUTH_CLIENT_ID=$(gcloud secrets versions access latest --secret=google-oauth-client-id --project="$MGMT_PROJECT" 2>/dev/null || echo "PLACEHOLDER_CLIENT_ID.apps.googleusercontent.com")
if [[ "$OAUTH_CLIENT_ID" == "PLACEHOLDER"* ]]; then
  log_warn "Secret 'google-oauth-client-id' not found in $MGMT_PROJECT; using placeholder."
else
  log_info "Retrieved Google OAuth Client ID: ${OAUTH_CLIENT_ID:0:18}... (masked)"
fi

OAUTH_CLIENT_SECRET=$(gcloud secrets versions access latest --secret=google-oauth-client-secret --project="$MGMT_PROJECT" 2>/dev/null || echo "PLACEHOLDER_CLIENT_SECRET")
if [[ "$OAUTH_CLIENT_SECRET" == "PLACEHOLDER"* ]]; then
  log_warn "Secret 'google-oauth-client-secret' not found in $MGMT_PROJECT; using placeholder."
else
  log_info "Retrieved Google OAuth Client Secret: [secret loaded from Secret Manager]"
fi

# Relay Secret (keep existing or generate a secure 64-char token)
EXISTING_RELAY_SECRET=$(grep '^NETBIRD_RELAY_SECRET=' "$DPI_DIR/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
if [[ -n "$EXISTING_RELAY_SECRET" ]]; then
  RELAY_SECRET="$EXISTING_RELAY_SECRET"
  log_info "Preserving existing NetBird Relay Secret."
else
  RELAY_SECRET=$(openssl rand -hex 32)
  log_info "Generated new 64-character NetBird Relay Secret."
fi

# 3. Render Configuration Files (.env and management.json)
echo -e "\n${BOLD}--- [3/5] Rendering Configuration Files ---${NC}"
log_cmd "Rendering $DPI_DIR/.env"
cat << ENV_EOF | sudo tee "$DPI_DIR/.env" > /dev/null
NETBIRD_FQDN="$NETBIRD_FQDN"
PROD_FQDN="$PROD_FQDN"
ACME_EMAIL="$ACME_EMAIL"
GOOGLE_OAUTH_CLIENT_ID="$OAUTH_CLIENT_ID"
GOOGLE_OAUTH_CLIENT_SECRET="$OAUTH_CLIENT_SECRET"
NETBIRD_RELAY_SECRET="$RELAY_SECRET"
SINGLE_ACCOUNT_MODE_DOMAIN="$SINGLE_ACCOUNT_MODE_DOMAIN"
ENV_EOF

if [ -f "$DPI_DIR/netbird/management.json.template" ]; then
  log_cmd "Rendering $DPI_DIR/netbird/management.json from template"
  sed -e "s|\$GOOGLE_OAUTH_CLIENT_ID|$OAUTH_CLIENT_ID|g" \
      -e "s|\$GOOGLE_OAUTH_CLIENT_SECRET|$OAUTH_CLIENT_SECRET|g" \
      -e "s|\$NETBIRD_RELAY_SECRET|$RELAY_SECRET|g" \
      -e "s|\$SINGLE_ACCOUNT_MODE_DOMAIN|$SINGLE_ACCOUNT_MODE_DOMAIN|g" \
      -e "s|\$NETBIRD_FQDN|$NETBIRD_FQDN|g" \
      "$DPI_DIR/netbird/management.json.template" | sudo tee "$DPI_DIR/netbird/management.json" > /dev/null
fi

log_cmd "chmod 600 $DPI_DIR/.env $DPI_DIR/netbird/management.json"
sudo chmod 600 "$DPI_DIR/.env" "$DPI_DIR/netbird/management.json" 2>/dev/null || true
log_cmd "chown root:root on all stack configs"
sudo chown root:root "$DPI_DIR/docker-compose.yml" "$DPI_DIR/.env" "$DPI_DIR/netbird/management.json" "$DPI_DIR/deploy.sh" 2>/dev/null || true
log_info "Configuration rendered and permissions locked down (0600 root:root)."

# 4. Swapfile Memory Protection (2GB swap for e2-micro 1GB RAM)
echo -e "\n${BOLD}--- [4/5] Memory Protection (Swapfile Check) ---${NC}"
if ! swapon --show | grep -q '/swapfile'; then
  log_warn "Swap is not currently active. Configuring 2GB swapfile..."
  if [ ! -f /swapfile ]; then
    log_cmd "fallocate -l 2G /swapfile"
    sudo fallocate -l 2G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    log_cmd "chmod 600 /swapfile && mkswap /swapfile"
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
  fi
  log_cmd "swapon /swapfile"
  sudo swapon /swapfile
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  fi
  log_info "2GB swapfile activated successfully."
else
  log_info "2GB swapfile is active."
fi

# 5. Container Lifecycle (Pull & Up)
echo -e "\n${BOLD}--- [5/5] Container Lifecycle & Verification ---${NC}"
cd "$DPI_DIR"

log_info "Pulling latest container images..."
log_cmd "sudo docker compose pull"
sudo docker compose pull

log_info "Starting NetBird containers (sudo docker compose up -d --remove-orphans)..."
log_cmd "sudo docker compose up -d --remove-orphans"
sudo docker compose up -d --remove-orphans

echo -e "\n${BOLD}--- Service Health Status ---${NC}"
sudo docker compose ps
