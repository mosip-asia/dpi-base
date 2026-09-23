#!/usr/bin/env bash
# ==============================================================================
# 🕸️ DPI Center — NetBird join (runs on the VM: /opt/rancher/netbird-join.sh)
# ==============================================================================
# Joins this host to the NetBird mesh with a setup key typed at a hidden prompt in
# the operator's terminal (opened by base-kube-ops/netbird-join.sh over IAP). The
# key is used once and never stored: it sits in a file in memory (/dev/shm) for the
# length of one `netbird up` call. NetBird keeps only its own peer identity
# afterwards (/etc/netbird/config.json, root only).
#
# Usage (on the VM, as root):
#   sudo /opt/rancher/netbird-join.sh            # prompt for the key and join
#   sudo /opt/rancher/netbird-join.sh --check    # prerequisites only, no key, no join
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

# NetBird 0.78 resolves the sudo invoking user (SUDO_USER) for its profile feature and
# refuses to run when that user cannot be looked up. OS Login users exist only through
# NSS, which NetBird's static binary does not use, so run it as plain root instead.
nb() {
  env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND netbird "$@"
}

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# The PuTTY window closes as soon as this script ends; keep the result readable.
pause_if_terminal() {
  if [ -t 0 ]; then
    read -r -p "Press Enter to close this session." _ || true
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0"
  pause_if_terminal
  exit 1
fi

ok=1
if command -v netbird >/dev/null 2>&1; then
  echo "client: netbird $(nb version 2>/dev/null || dpkg-query -W -f='${Version}' netbird)"
else
  echo "client: MISSING (run ./base-kube-ops/remote-deploy.sh first)"
  ok=0
fi
if systemctl is-active --quiet netbird; then
  echo "daemon: active"
else
  echo "daemon: NOT active"
  ok=0
fi
mgmt_host="${NETBIRD_MANAGEMENT_URL#*://}"
mgmt_host="${mgmt_host%%/*}"
if curl -sf --max-time 10 -o /dev/null "https://${mgmt_host}/"; then
  echo "management: ${NETBIRD_MANAGEMENT_URL} reachable"
else
  echo "management: ${NETBIRD_MANAGEMENT_URL} NOT reachable"
  ok=0
fi
status="$(nb status 2>/dev/null || true)"
if printf '%s' "$status" | grep -q '^Management: Connected'; then
  echo "already joined:"
  printf '%s\n' "$status" | grep -E '^(NetBird IP|Management|Signal)'
  pause_if_terminal
  exit 0
fi
echo "status: $(printf '%s' "$status" | grep -E '^Daemon status' || echo 'not joined')"

if [ "$CHECK_ONLY" = "1" ]; then
  if [ "$ok" = "1" ]; then
    echo "check: ready to join (create the setup key, then run ./base-kube-ops/netbird-join.sh)"
    exit 0
  fi
  echo "check: NOT ready"
  exit 1
fi
if [ "$ok" != "1" ]; then
  pause_if_terminal
  exit 1
fi
if [ ! -t 0 ]; then
  echo "the setup key must be typed in a terminal: use ./base-kube-ops/netbird-join.sh"
  exit 2
fi

key=""
read -rs -p "NetBird setup key (input hidden, then Enter): " key
echo
key="${key//[[:space:]]/}"
if [ -z "$key" ]; then
  echo "no key entered"
  pause_if_terminal
  exit 2
fi

keyfile="$(mktemp -p /dev/shm netbird-key.XXXXXX)"
chmod 0600 "$keyfile"
printf '%s' "$key" > "$keyfile"
unset key
trap 'rm -f "$keyfile"' EXIT

echo "netbird up --management-url ${NETBIRD_MANAGEMENT_URL} --setup-key-file <memory file>"
set +e
nb up --management-url "$NETBIRD_MANAGEMENT_URL" --setup-key-file "$keyfile"
rc=$?
set -e
rm -f "$keyfile"
if [ "$rc" -ne 0 ]; then
  echo "netbird up failed (exit $rc)"
  pause_if_terminal
  exit "$rc"
fi

for _ in $(seq 1 12); do
  if nb status 2>/dev/null | grep -q '^Management: Connected'; then
    break
  fi
  sleep 5
done
nb status | grep -E '^(NetBird IP|Management|Signal|Relays|Peers)' || true
if nb status | grep -q '^Management: Connected'; then
  echo "joined."
  pause_if_terminal
  exit 0
fi
echo "not connected yet; check the NetBird dashboard and 'netbird status' on the VM."
pause_if_terminal
exit 1
