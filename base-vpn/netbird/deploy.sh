#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Stack VM Service Deployer
# ==============================================================================
# This script executes directly on the VM (/opt/netbird/deploy.sh).
# It pulls secrets from Secret Manager using the VM's service account,
# renders /opt/netbird/.env and /opt/netbird/management.json, configures swap,
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

NETBIRD_DIR="${NETBIRD_DIR:-/opt/netbird}"

# 0. Seamless migration from legacy /opt/dpi path if present
if [ -d /opt/dpi ] && [ ! -d "$NETBIRD_DIR" ]; then
  log_info "Migrating legacy /opt/dpi to $NETBIRD_DIR..."
  sudo mv /opt/dpi "$NETBIRD_DIR"
fi

mkdir -p "$NETBIRD_DIR/traefik" "$NETBIRD_DIR/data" "$NETBIRD_DIR/scripts"

# 1. Move uploaded files from /tmp to /opt/netbird
echo -e "\n${BOLD}--- [1/6] Syncing Application Manifests ---${NC}"
if [ -f /tmp/docker-compose.yml ]; then
  log_cmd "mv /tmp/docker-compose.yml $NETBIRD_DIR/docker-compose.yml"
  sudo mv /tmp/docker-compose.yml "$NETBIRD_DIR/docker-compose.yml"
fi

if [ -f /tmp/management.json.template ]; then
  log_cmd "mv /tmp/management.json.template $NETBIRD_DIR/management.json.template"
  sudo mv /tmp/management.json.template "$NETBIRD_DIR/management.json.template"
fi

if [ -f /tmp/.env.template ]; then
  log_cmd "mv /tmp/.env.template $NETBIRD_DIR/.env.template"
  sudo mv /tmp/.env.template "$NETBIRD_DIR/.env.template"
fi

if [ -f /tmp/backup_to_gcs.sh ]; then
  log_cmd "mv /tmp/backup_to_gcs.sh $NETBIRD_DIR/scripts/backup_to_gcs.sh"
  sudo mv /tmp/backup_to_gcs.sh "$NETBIRD_DIR/scripts/backup_to_gcs.sh"
  sudo chmod +x "$NETBIRD_DIR/scripts/backup_to_gcs.sh"
fi

# Clean up any leftover staging files in /tmp so no ext_* artifacts remain
sudo rm -f /tmp/docker-compose.yml /tmp/management.json.template /tmp/.env.template /tmp/backup_to_gcs.sh /tmp/deploy.sh 2>/dev/null || true

# 2. Load Configuration from .env / .env.template (Single Source of Truth)
echo -e "\n${BOLD}--- [2/6] Loading Configuration & Restoring State ---${NC}"
if [ -f "$NETBIRD_DIR/.env.template" ]; then
  # shellcheck disable=SC1090
  source "$NETBIRD_DIR/.env.template"
fi

if [ -f "$NETBIRD_DIR/.env" ]; then
  # shellcheck disable=SC1090
  source "$NETBIRD_DIR/.env"
fi

MGMT_PROJECT="${MGMT_PROJECT:-base-mgmt}"
STATE_BUCKET="${STATE_BUCKET:-base-dpi-ait-ac-th-tfstate}"
NETBIRD_FQDN="${NETBIRD_FQDN:-netbird.base.dpi.ait.ac.th}"
PROD_FQDN="${PROD_FQDN:-netbird.dpi.ait.ac.th}"
ACME_EMAIL="${ACME_EMAIL:-admin@dpi.ait.ac.th}"
SINGLE_ACCOUNT_MODE_DOMAIN="${SINGLE_ACCOUNT_MODE_DOMAIN:-dpi.ait.ac.th}"

# Ensure acme.json is a regular file with 0600 permissions (not a directory)
if [ -d "$NETBIRD_DIR/traefik/acme.json" ]; then
  log_warn "acme.json was created as a directory. Recreating as a secure 0600 file..."
  sudo rm -rf "$NETBIRD_DIR/traefik/acme.json"
fi
if [ ! -f "$NETBIRD_DIR/traefik/acme.json" ]; then
  sudo touch "$NETBIRD_DIR/traefik/acme.json"
fi
sudo chmod 600 "$NETBIRD_DIR/traefik/acme.json"

# Restore NetBird SQLite Database from GCS if it exists and local store is missing
if [ ! -f "$NETBIRD_DIR/data/store.db" ]; then
  log_info "Checking GCS for existing NetBird database snapshot..."
  if gcloud storage cp "gs://${STATE_BUCKET}/backups/netbird/store.db" "$NETBIRD_DIR/data/store.db" 2>/dev/null; then
    sudo chmod 600 "$NETBIRD_DIR/data/store.db"
    log_info "Restored NetBird store.db from GCS."
  fi
fi

# Restore Traefik acme.json from GCS if local file is empty
if [ ! -s "$NETBIRD_DIR/traefik/acme.json" ]; then
  if gcloud storage cp "gs://${STATE_BUCKET}/backups/netbird/acme.json" "$NETBIRD_DIR/traefik/acme.json" 2>/dev/null; then
    sudo chmod 600 "$NETBIRD_DIR/traefik/acme.json"
    log_info "Restored Traefik acme.json certificates from GCS."
  fi
fi

# Ensure ubuntu system user has docker group permissions
sudo usermod -aG docker ubuntu 2>/dev/null || true

# Ensure 6-hourly backup cron is configured for root
(sudo crontab -l 2>/dev/null | grep -v 'backup_to_gcs.sh' || true; echo "0 */6 * * * $NETBIRD_DIR/scripts/backup_to_gcs.sh >/dev/null 2>&1") | sudo crontab -

# 3. Fetch Secrets from Secret Manager via VM Attached Service Account
echo -e "\n${BOLD}--- [3/6] Resolving Secrets from GCP Secret Manager ---${NC}"
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
RELAY_SECRET="${NETBIRD_RELAY_SECRET:-}"
if [[ -z "$RELAY_SECRET" && -f "$NETBIRD_DIR/.env" ]]; then
  RELAY_SECRET=$(grep '^NETBIRD_RELAY_SECRET=' "$NETBIRD_DIR/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
fi

if [[ -n "$RELAY_SECRET" ]]; then
  log_info "Preserving existing NetBird Relay Secret."
else
  RELAY_SECRET=$(openssl rand -hex 32)
  log_info "Generated new 64-character NetBird Relay Secret."
fi

# 4. Render Configuration Files (.env and management.json)
echo -e "\n${BOLD}--- [4/6] Rendering Configuration Files (.env & management.json) ---${NC}"
log_cmd "Writing $NETBIRD_DIR/.env"
cat << ENV_EOF | sudo tee "$NETBIRD_DIR/.env" > /dev/null
# ==============================================================================
# 📡 DPI Center — NetBird Mesh VPN Environment Configuration
# ==============================================================================

# Platform & Storage Paths
NETBIRD_DIR="$NETBIRD_DIR"
MGMT_PROJECT="$MGMT_PROJECT"
STATE_BUCKET="$STATE_BUCKET"

# Domains & ACME TLS Configuration
NETBIRD_FQDN="$NETBIRD_FQDN"
PROD_FQDN="$PROD_FQDN"
ACME_EMAIL="$ACME_EMAIL"
SINGLE_ACCOUNT_MODE_DOMAIN="$SINGLE_ACCOUNT_MODE_DOMAIN"

# Dynamic Secrets
GOOGLE_OAUTH_CLIENT_ID="$OAUTH_CLIENT_ID"
GOOGLE_OAUTH_CLIENT_SECRET="$OAUTH_CLIENT_SECRET"
NETBIRD_RELAY_SECRET="$RELAY_SECRET"
ENV_EOF

if [ -f "$NETBIRD_DIR/management.json.template" ]; then
  log_cmd "Rendering $NETBIRD_DIR/management.json from template"
  sed -e "s|\$GOOGLE_OAUTH_CLIENT_ID|$OAUTH_CLIENT_ID|g" \
      -e "s|\$GOOGLE_OAUTH_CLIENT_SECRET|$OAUTH_CLIENT_SECRET|g" \
      -e "s|\$NETBIRD_RELAY_SECRET|$RELAY_SECRET|g" \
      -e "s|\$SINGLE_ACCOUNT_MODE_DOMAIN|$SINGLE_ACCOUNT_MODE_DOMAIN|g" \
      -e "s|\$NETBIRD_FQDN|$NETBIRD_FQDN|g" \
      "$NETBIRD_DIR/management.json.template" | sudo tee "$NETBIRD_DIR/management.json" > /dev/null
fi

# Set ownership of the service directory to ubuntu:docker
log_cmd "chown -R ubuntu:docker $NETBIRD_DIR"
sudo chown -R ubuntu:docker "$NETBIRD_DIR" 2>/dev/null || true

# Sensitive credentials readable/writable by ubuntu (0600)
log_cmd "chmod 600 $NETBIRD_DIR/.env $NETBIRD_DIR/management.json"
sudo chmod 600 "$NETBIRD_DIR/.env" "$NETBIRD_DIR/management.json" 2>/dev/null || true

# Traefik requires acme.json to be strictly 0600 owned by root
if [ -f "$NETBIRD_DIR/traefik/acme.json" ]; then
  sudo chown root:root "$NETBIRD_DIR/traefik/acme.json" 2>/dev/null || true
  sudo chmod 600 "$NETBIRD_DIR/traefik/acme.json" 2>/dev/null || true
fi

# Ensure compose file and scripts are readable/executable
sudo chmod 644 "$NETBIRD_DIR/docker-compose.yml" 2>/dev/null || true
sudo chmod 755 "$NETBIRD_DIR/deploy.sh" "$NETBIRD_DIR/scripts/backup_to_gcs.sh" 2>/dev/null || true

log_info "Permissions configured: owned by 'ubuntu:docker', secrets mode 0600, acme.json mode 0600 root."

# 5. Swapfile Memory Protection (2GB swap for e2-micro 1GB RAM)
echo -e "\n${BOLD}--- [5/6] Memory Protection (Swapfile Check) ---${NC}"
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

# 6. Container Lifecycle & Verification
echo -e "\n${BOLD}--- [6/6] Container Lifecycle & Verification ---${NC}"
cd "$NETBIRD_DIR"

log_info "Pulling latest container images..."
log_cmd "sudo docker compose pull"
sudo docker compose pull

log_info "Starting NetBird containers (sudo docker compose up -d --remove-orphans)..."
log_cmd "sudo docker compose up -d --remove-orphans"
sudo docker compose up -d --remove-orphans

echo -e "\n${BOLD}--- Service Health Status ---${NC}"
sudo docker compose ps

# Snapshot current state to GCS
echo -e "\n${BOLD}--- Synchronizing State Snapshot to GCS ---${NC}"
if [ -f "$NETBIRD_DIR/scripts/backup_to_gcs.sh" ]; then
  log_cmd "sudo $NETBIRD_DIR/scripts/backup_to_gcs.sh"
  sudo "$NETBIRD_DIR/scripts/backup_to_gcs.sh" || true
fi
