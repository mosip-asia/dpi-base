#!/usr/bin/env bash
# ==============================================================================
# 🕸️ DPI Center — Join base-kube-ops-vm to the NetBird mesh (from the laptop)
# ==============================================================================
# Opens a terminal on the VM over IAP that runs /opt/rancher/netbird-join.sh, which
# asks for the NetBird setup key with input hidden and runs `netbird up`. The key
# is typed only into that terminal and is never shown, logged, or written to disk.
# Create the key in the NetBird dashboard first (README: "Join the NetBird mesh").
#
# Usage:
#   ./base-kube-ops/netbird-join.sh            # terminal on the VM; paste the key there
#   ./base-kube-ops/netbird-join.sh --check    # prerequisites on the VM; no key, no join
#
# On Windows (Git Bash) gcloud opens the terminal in a PuTTY window; on macOS and
# Linux it runs in the current terminal. Not from PowerShell's bash (WSL).
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

case "${1:-}" in
  --check)
    exec gcloud compute ssh "$VM_NAME" \
      --project="$KUBE_OPS_PROJECT" \
      --zone="$ZONE" \
      --tunnel-through-iap \
      --command="sudo $REMOTE_SCRIPT --check"
    ;;
  "") ;;
  -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown argument: $1"; exit 2 ;;
esac

# gcloud on Windows runs a command through plink with a closed standard input, so a
# prompt needs the PuTTY window instead: PuTTY takes the remote command from a file (-m).
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    CMD_FILE="$(mktemp)"
    printf 'sudo %s\n' "$REMOTE_SCRIPT" > "$CMD_FILE"
    echo "A PuTTY window opens and asks for the setup key (input hidden). Paste it there and press Enter."
    gcloud compute ssh "$VM_NAME" \
      --project="$KUBE_OPS_PROJECT" \
      --zone="$ZONE" \
      --tunnel-through-iap \
      -- -t -m "$(cygpath -w "$CMD_FILE")"
    rm -f "$CMD_FILE"
    ;;
  *)
    exec gcloud compute ssh "$VM_NAME" \
      --project="$KUBE_OPS_PROJECT" \
      --zone="$ZONE" \
      --tunnel-through-iap \
      -- -t "sudo $REMOTE_SCRIPT"
    ;;
esac
