#!/usr/bin/env bash
# ==============================================================================
# 🕸️ DPI Center — Join base-kube-ops-vm to the NetBird mesh (from the laptop)
# ==============================================================================
# Asks for a NetBird setup key (input hidden) and sends it over the IAP SSH channel
# to /opt/rancher/netbird-join.sh on the VM, which runs `netbird up` with it. The
# key is never shown, logged, or written to disk on either side. Create the key in
# the NetBird dashboard first (README: "Join the NetBird mesh").
#
# Usage:
#   ./base-kube-ops/netbird-join.sh            # prompt for the key and join
#   ./base-kube-ops/netbird-join.sh --check    # only test the path to the VM; no join
#
# On Windows run it from Git Bash, not from PowerShell's bash (WSL).
# ==============================================================================
set -euo pipefail

if grep -qi 'microsoft' /proc/version 2>/dev/null; then
  echo "This is WSL's bash, where gcloud and your Google login do not exist. Use a Git Bash terminal."
  exit 1
fi
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

KUBE_OPS_PROJECT="base-kube-ops"
VM_NAME="base-kube-ops-vm"
ZONE="asia-southeast1-b"
REMOTE_SCRIPT="/opt/rancher/netbird-join.sh"

CHECK_ARG=""
case "${1:-}" in
  --check) CHECK_ARG="--check" ;;
  "") ;;
  -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown argument: $1"; exit 2 ;;
esac

if [ -n "$CHECK_ARG" ]; then
  KEY="check-only-placeholder"
else
  read -rs -p "NetBird setup key (input hidden, then Enter): " KEY
  echo
fi
if [ -z "$KEY" ]; then
  echo "no key entered"
  exit 2
fi

set +e
printf '%s\n' "$KEY" | gcloud compute ssh "$VM_NAME" \
  --project="$KUBE_OPS_PROJECT" \
  --zone="$ZONE" \
  --tunnel-through-iap \
  --command="sudo $REMOTE_SCRIPT $CHECK_ARG"
RC=$?
set -e
unset KEY
exit "$RC"
