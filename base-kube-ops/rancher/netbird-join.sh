#!/usr/bin/env bash
# ==============================================================================
# 🕸️ DPI Center — NetBird join (runs on the VM: /opt/rancher/netbird-join.sh)
# ==============================================================================
# Joins this host to the NetBird mesh with a setup key read from standard input,
# piped over the IAP SSH channel by base-kube-ops/netbird-join.sh. The key is used
# once and never stored: it goes to a file in memory (/dev/shm) for the length of
# one `netbird up` call. NetBird keeps only its own peer identity afterwards
# (/etc/netbird/config.json, root only).
#
# Usage (from the VM, as root):  printf '%s\n' "<setup key>" | ./netbird-join.sh
#         --check                 only report what arrived on stdin; no join
# ==============================================================================
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

RANCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$RANCHER_DIR/.env.template"
if [ -f "$RANCHER_DIR/.env" ]; then
  # shellcheck disable=SC1091
  source "$RANCHER_DIR/.env"
fi
: "${NETBIRD_MANAGEMENT_URL:?NETBIRD_MANAGEMENT_URL missing in .env.template}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0"
  exit 1
fi

# The first non-empty line that is not the "y" gcloud feeds into plink on Windows.
key=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    ""|y|Y) continue ;;
  esac
  key="$line"
  break
done
if [ -z "$key" ]; then
  echo "no setup key arrived on standard input"
  exit 2
fi
if [ "$CHECK_ONLY" = "1" ]; then
  echo "check only: received a key of ${#key} characters; nothing joined"
  exit 0
fi

if ! command -v netbird >/dev/null 2>&1; then
  echo "netbird client is not installed: run ./base-kube-ops/remote-deploy.sh first"
  exit 1
fi
if netbird status 2>/dev/null | grep -q '^Management: Connected'; then
  echo "already joined:"
  netbird status | grep -E '^(NetBird IP|Management|Signal)'
  exit 0
fi

keyfile="$(mktemp -p /dev/shm netbird-key.XXXXXX)"
chmod 0600 "$keyfile"
printf '%s' "$key" > "$keyfile"
unset key
trap 'rm -f "$keyfile"' EXIT

echo "netbird up --management-url ${NETBIRD_MANAGEMENT_URL} --setup-key-file <memory file>"
netbird up --management-url "$NETBIRD_MANAGEMENT_URL" --setup-key-file "$keyfile"
rm -f "$keyfile"

for _ in $(seq 1 12); do
  if netbird status 2>/dev/null | grep -q '^Management: Connected'; then
    break
  fi
  sleep 5
done
netbird status | grep -E '^(NetBird IP|Management|Signal|Relays|Peers)' || true
netbird status | grep -q '^Management: Connected'
