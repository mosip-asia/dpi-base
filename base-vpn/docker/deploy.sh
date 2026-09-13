#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — NetBird Stack VM Service Deployer
# ==============================================================================
# This script executes directly on the VM (in /opt/dpi).
# It installs newly uploaded configs, ensures 2GB swap is active,
# pulls the container images, and starts/restarts the Docker Compose stack.
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
mkdir -p "$DPI_DIR/netbird" "$DPI_DIR/traefik" "$DPI_DIR/scripts"

# 1. Install newly uploaded configurations from /tmp if present
echo -e "\n${BOLD}--- [1/4] Installing Configuration Files ---${NC}"
if [ -f /tmp/docker-compose.yml ]; then
  log_cmd "mv /tmp/docker-compose.yml $DPI_DIR/docker-compose.yml"
  sudo mv /tmp/docker-compose.yml "$DPI_DIR/docker-compose.yml"
fi

if [ -f /tmp/.env ]; then
  log_cmd "mv /tmp/.env $DPI_DIR/.env"
  sudo mv /tmp/.env "$DPI_DIR/.env"
fi

if [ -f /tmp/management.json ]; then
  log_cmd "mv /tmp/management.json $DPI_DIR/netbird/management.json"
  sudo mv /tmp/management.json "$DPI_DIR/netbird/management.json"
fi

# 2. Permissions & Security
echo -e "\n${BOLD}--- [2/4] Securing File Permissions ---${NC}"
log_cmd "chmod 600 $DPI_DIR/.env $DPI_DIR/netbird/management.json"
sudo chmod 600 "$DPI_DIR/.env" "$DPI_DIR/netbird/management.json" 2>/dev/null || true
log_cmd "chown root:root on all stack configs"
sudo chown root:root "$DPI_DIR/docker-compose.yml" "$DPI_DIR/.env" "$DPI_DIR/netbird/management.json" "$DPI_DIR/deploy.sh" 2>/dev/null || true
log_info "Configuration permissions locked down (0600 root:root)."

# 3. Swapfile Memory Protection (2GB swap for e2-micro 1GB RAM)
echo -e "\n${BOLD}--- [3/4] Memory Protection (Swapfile Check) ---${NC}"
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

# 4. Pull Images & Launch Compose Stack
echo -e "\n${BOLD}--- [4/4] Container Lifecycle & Health Check ---${NC}"
cd "$DPI_DIR"

log_info "Pulling latest container images..."
log_cmd "docker compose pull"
sudo docker compose pull

log_info "Starting NetBird containers (detached)..."
log_cmd "docker compose up -d --remove-orphans"
sudo docker compose up -d --remove-orphans

echo -e "\n${BOLD}--- Current Service Status ---${NC}"
sudo docker compose ps
