#!/usr/bin/env bash
# ==============================================================================
# 🚀 DPI Center — Rancher Host Local Orchestrator & Deployer
# ==============================================================================
# Uploads the Rancher stack configuration to base-kube-ops-vm over the Google IAP
# tunnel, then runs the VM-side deployer (/opt/rancher/deploy.sh), which installs or
# upgrades K3s, Helm, cert-manager, the NetBird client and Rancher at the versions in rancher/.env.template.
#
# Usage:
#   ./base-kube-ops/remote-deploy.sh                            # install or apply unchanged pins
#   ./base-kube-ops/remote-deploy.sh --confirm-rancher-upgrade  # after bumping RANCHER_CHART_VERSION
#
# Exit codes are the deployer's: 0 healthy · 1 failure · 3 waiting for the Rancher DNS name.
# On Windows run it from Git Bash, not from PowerShell's bash (WSL).
# ==============================================================================
set -euo pipefail

if grep -qi 'microsoft' /proc/version 2>/dev/null; then
  echo "This is WSL's bash, where gcloud and your Google login do not exist."
  echo "Open a Git Bash terminal, or from PowerShell: & 'C:\\Program Files\\Git\\bin\\bash.exe' base-kube-ops/remote-deploy.sh"
  exit 1
fi
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ------------------------------------------------------------------------------
# UI & Formatting Helpers
# ------------------------------------------------------------------------------
BOLD='\033[1m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

log_step() {
  echo -e "\n${BOLD}${BLUE}==========================================================${NC}"
  echo -e "${BOLD}${BLUE}$1${NC}"
  echo -e "${BOLD}${BLUE}==========================================================${NC}"
}
log_cmd()  { echo -e "${CYAN}▶ [EXEC]${NC} ${DIM}$1${NC}"; }
log_info() { echo -e "${GREEN}✔ [INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠ [WARN]${NC} $1"; }
log_fail() { echo -e "${RED}✖ [FAIL]${NC} $1"; }

KUBE_OPS_PROJECT="base-kube-ops"
VM_NAME="base-kube-ops-vm"
ZONE="asia-southeast1-b"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR/rancher"
REMOTE_DIR="/opt/rancher"
if [ -f "$STACK_DIR/.env.template" ]; then
  TEMPLATE_DIR=$(grep '^RANCHER_DIR=' "$STACK_DIR/.env.template" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '\r')
  [ -n "$TEMPLATE_DIR" ] && REMOTE_DIR="$TEMPLATE_DIR"
fi

CONFIRM_ENV=""
for arg in "$@"; do
  case "$arg" in
    --confirm-rancher-upgrade) CONFIRM_ENV="CONFIRM_RANCHER_UPGRADE=yes" ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_fail "unknown argument: $arg"; exit 2 ;;
  esac
done

# Windows (Git Bash): gcloud needs native paths for local files.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# A CRLF deploy.sh fails on the VM. base-kube-ops/.gitattributes keeps LF; this catches stray edits.
FILES=("$STACK_DIR/.env.template" "$STACK_DIR/rancher-values.yaml" "$STACK_DIR/netbird-join.sh" "$STACK_DIR/deploy.sh")
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { log_fail "missing $f"; exit 1; }
  if [ "$(tr -cd '\r' < "$f" | wc -c)" -gt 0 ]; then
    log_fail "$f has CRLF line endings. Convert it to LF (e.g. sed -i 's/\\r\$//' \"$f\") and try again."
    exit 1
  fi
done

# The instance schedule stops the VM at 18:30 Asia/Bangkok (UTC+7, no DST); a first install takes about 15 minutes.
BKK_MINUTE=$(( ( ( $(date -u +%s) + 7 * 3600 ) % 86400 ) / 60 ))
if (( BKK_MINUTE >= 17 * 60 + 45 && BKK_MINUTE <= 18 * 60 + 45 )); then
  log_warn "It is close to the 18:30 scheduled stop (Asia/Bangkok); a long install may be cut off. Re-running later is safe."
fi

log_step "📦 [1/2] Uploading Rancher Stack Configuration to VM via IAP..."
echo -e "Target VM:   ${BOLD}$VM_NAME${NC} (Project: ${CYAN}$KUBE_OPS_PROJECT${NC}, Zone: ${CYAN}$ZONE${NC})"
echo -e "Source Dir:  ${BOLD}$STACK_DIR${NC}"
echo -e "Remote Dir:  ${BOLD}$REMOTE_DIR${NC}"
echo ""

log_cmd "gcloud compute scp --project=$KUBE_OPS_PROJECT --zone=$ZONE --tunnel-through-iap rancher/{.env.template,rancher-values.yaml,netbird-join.sh,deploy.sh} $VM_NAME:/tmp/"
gcloud compute scp --project="$KUBE_OPS_PROJECT" --zone="$ZONE" --tunnel-through-iap \
  "$(winpath "$STACK_DIR/.env.template")" \
  "$(winpath "$STACK_DIR/rancher-values.yaml")" \
  "$(winpath "$STACK_DIR/netbird-join.sh")" \
  "$(winpath "$STACK_DIR/deploy.sh")" \
  "$VM_NAME:/tmp/"
log_info "Files uploaded to /tmp on $VM_NAME."

log_step "⚡ [2/2] Executing Remote Deployer ($REMOTE_DIR/deploy.sh) on VM..."
REMOTE_CMD="sudo mkdir -p $REMOTE_DIR && sudo mv /tmp/deploy.sh $REMOTE_DIR/deploy.sh && sudo chmod 755 $REMOTE_DIR/deploy.sh && sudo env $CONFIRM_ENV $REMOTE_DIR/deploy.sh"
log_cmd "gcloud compute ssh $VM_NAME --project=$KUBE_OPS_PROJECT --zone=$ZONE --tunnel-through-iap --command=\"$REMOTE_CMD\""

set +e
gcloud compute ssh "$VM_NAME" --project="$KUBE_OPS_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="$REMOTE_CMD"
RC=$?
set -e

case "$RC" in
  0)
    log_step "🎉 Deployment Complete!"
    echo -e "Rancher is live and healthy: ${GREEN}https://$(grep '^RANCHER_FQDN=' "$STACK_DIR/.env.template" | cut -d'=' -f2- | tr -d '"')${NC}"
    ;;
  3)
    log_step "⏳ Waiting for DNS"
    echo -e "K3s, cert-manager and the NetBird client are deployed. Rancher waits until its server URL resolves to the VM (see the message above)."
    ;;
  *)
    log_step "❌ Deployment Failed (exit $RC)"
    echo -e "Read the deployer output above. Re-running is safe: every step is idempotent."
    ;;
esac
exit "$RC"
