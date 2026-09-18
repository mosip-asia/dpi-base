#!/usr/bin/env bash
# ==============================================================================
# 🔎 DPI Center — Rancher DNS Record Check (read-only)
# ==============================================================================
# Does a public name resolve to the Rancher host's static IP? Asks Cloudflare and
# Google over DNS-over-HTTPS (no dig needed) and follows CNAMEs.
#
# Usage:
#   ./base-kube-ops/scripts/check_record.sh [fqdn] [expected-ip]
#     fqdn         default rancher.base.dpi.ait.ac.th (the A record from terraform/dns.tf)
#     expected-ip  default `terraform -chdir=base-kube-ops/terraform output -raw rancher_static_ip`
#
# Examples:
#   ./base-kube-ops/scripts/check_record.sh                          # our A record
#   ./base-kube-ops/scripts/check_record.sh rancher.dpi.ait.ac.th    # the canonical CNAME
#
# Exit codes: 0 both resolvers answer the expected IP · 2 pending · 1 error
# Run it only after the record exists: a resolver asked earlier caches NXDOMAIN
# for up to 300 seconds.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

# On Windows `python3` may be a Store alias stub: probe each candidate.
PY=""
for candidate in python3 python; do
  if "$candidate" -c 'import sys' >/dev/null 2>&1; then PY="$(command -v "$candidate")"; break; fi
done
[ -n "$PY" ] || { echo "FAIL  python not found"; exit 1; }

HOST="${1:-rancher.base.dpi.ait.ac.th}"
WANT="${2:-}"
if [ -z "$WANT" ] && command -v terraform >/dev/null 2>&1; then
  WANT="$(terraform -chdir="$TF_DIR" output -raw rancher_static_ip 2>/dev/null | tr -d '\r' || true)"
fi
[ -n "$WANT" ] || { echo "FAIL  expected IP unknown: pass it as the second argument, or run terraform apply (and init) first"; exit 1; }

# answers <url> -> "STATUS n", then "CNAME target" and "A address" lines
answers() {
  curl -sS --max-time 20 -H 'accept: application/dns-json' "$1" 2>/dev/null | "$PY" -c 'import sys, json
d = json.load(sys.stdin)
print("STATUS", d.get("Status", "?"))
for a in d.get("Answer", []):
    if a.get("type") == 5:
        print("CNAME", a["data"].strip())
    elif a.get("type") == 1:
        print("A", a["data"].strip())' 2>/dev/null | tr -d '\r'
}

RC=0
echo "Record check for ${HOST} (expected ${WANT})"
for r in "cloudflare https://cloudflare-dns.com/dns-query?name=${HOST}&type=A" "google https://dns.google/resolve?name=${HOST}&type=A"; do
  name="${r%% *}"; url="${r#* }"
  RAW="$(answers "$url")"
  ST="$(printf '%s\n' "$RAW" | awk '/^STATUS/{print $2}')"
  CHAIN="$(printf '%s\n' "$RAW" | awk '/^CNAME/{printf "%s -> ", $2}')"
  GOT="$(printf '%s\n' "$RAW" | awk '/^A /{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  case "$ST" in
    0)
      if [ "$GOT" = "$WANT" ]; then
        echo "  PASS     ${name}: ${HOST} -> ${CHAIN}${GOT}"
      else
        echo "  PENDING  ${name}: ${HOST} -> ${CHAIN}${GOT:-no A record} (expected ${WANT})"
        [ "$RC" = 0 ] && RC=2
      fi ;;
    3)
      echo "  PENDING  ${name}: NXDOMAIN (not created yet, or a cached negative answer: up to 300 s)"
      [ "$RC" = 0 ] && RC=2 ;;
    *)
      echo "  FAIL     ${name}: DoH status ${ST:-none}"
      RC=1 ;;
  esac
done

case "$RC" in
  0) echo "RESULT  record live: ${HOST} -> ${WANT} on both resolvers" ;;
  2) echo "RESULT  pending: wait a few minutes and re-run" ;;
  *) echo "RESULT  error" ;;
esac
exit "$RC"
