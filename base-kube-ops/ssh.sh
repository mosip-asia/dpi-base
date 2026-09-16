#!/usr/bin/env bash
# ==============================================================================
# 🔑 DPI Center — Rancher Host SSH Helper (Ubuntu Session via IAP)
# ==============================================================================
# Connects over the Google IAP tunnel and drops directly into the 'ubuntu' system
# user, whose kubeconfig (written by deploy.sh) lets kubectl and helm run without sudo.
#
# Usage:
#   ./base-kube-ops/ssh.sh                 # Interactive shell as 'ubuntu'
#   ./base-kube-ops/ssh.sh <command>       # Execute a command as 'ubuntu'
#
# Examples:
#   ./base-kube-ops/ssh.sh
#   ./base-kube-ops/ssh.sh "kubectl get nodes"
#   ./base-kube-ops/ssh.sh "kubectl -n cattle-system get pods"
#
# Operators outside the dpi.ait.ac.th organization (@ait.asia) need
# roles/compute.osLoginExternalUser on the organization (granted 2026-09-13).
# ==============================================================================
set -euo pipefail

if grep -qi 'microsoft' /proc/version 2>/dev/null; then
  echo "This is WSL's bash, where gcloud and your Google login do not exist. Use a Git Bash terminal."
  exit 1
fi

KUBE_OPS_PROJECT="base-kube-ops"
VM_NAME="base-kube-ops-vm"
ZONE="asia-southeast1-b"

CYAN='\033[0;36m'
NC='\033[0m'

if [ $# -gt 0 ]; then
  echo -e "${CYAN}▶ Executing on $VM_NAME as 'ubuntu' via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$KUBE_OPS_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    --command="sudo -i -u ubuntu bash -c $(printf '%q' "$*")"
else
  echo -e "${CYAN}▶ Connecting to $VM_NAME as 'ubuntu' via IAP...${NC}"
  exec gcloud compute ssh "$VM_NAME" \
    --project="$KUBE_OPS_PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    -- -t "sudo -i -u ubuntu"
fi
