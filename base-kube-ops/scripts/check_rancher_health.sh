#!/usr/bin/env bash
# ==============================================================================
# 🩺 DPI Center — Rancher Health Check (read-only, from the laptop)
# ==============================================================================
# PASS when /healthz answers 200 with a trusted certificate issued by Let's Encrypt
# production (a staging certificate is accepted only with --allow-staging).
#
# Usage:
#   ./base-kube-ops/scripts/check_rancher_health.sh [url] [--allow-staging]
#     url  default https://rancher.dpi.ait.ac.th
#
# Exit codes: 0 healthy · 1 not healthy
# ==============================================================================
set -uo pipefail

URL="https://rancher.dpi.ait.ac.th"
ALLOW_STAGING=0
for arg in "$@"; do
  case "$arg" in
    --allow-staging) ALLOW_STAGING=1 ;;
    https://*) URL="$arg" ;;
    *) echo "unknown argument: $arg"; exit 1 ;;
  esac
done

FAILED=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }
warn() { echo "  WARN  $1"; }

host="${URL#https://}"; host="${host%%/*}"
echo "Rancher health check for ${URL}"

code="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' "${URL}/healthz" 2>/dev/null || true)"
if [ "$code" = "200" ]; then
  pass "${URL}/healthz -> 200 with a trusted certificate"
else
  code_k="$(curl -sSk --max-time 15 -o /dev/null -w '%{http_code}' "${URL}/healthz" 2>/dev/null || true)"
  if [ "$code_k" = "200" ]; then
    if [ "$ALLOW_STAGING" = 1 ]; then warn "/healthz is 200 only without certificate checks (staging certificate?)"
    else fail "/healthz is 200 only without certificate checks: the certificate is not trusted"; fi
  else
    fail "${URL}/healthz -> ${code:-no answer} (VM running? The schedule stops it 18:30-08:30 Asia/Bangkok and on weekends)"
  fi
fi

if command -v openssl >/dev/null 2>&1; then
  issuer="$(openssl s_client -servername "$host" -connect "${host}:443" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -enddate 2>/dev/null | tr -d '\r' | tr '\n' ' ')"
  if [ -z "$issuer" ]; then
    fail "no certificate presented on ${host}:443"
  elif printf '%s' "$issuer" | grep -q STAGING; then
    if [ "$ALLOW_STAGING" = 1 ]; then warn "Let's Encrypt STAGING certificate (${issuer})"
    else fail "Let's Encrypt STAGING certificate (${issuer})"; fi
  elif printf '%s' "$issuer" | grep -qi "Let's Encrypt"; then
    pass "certificate: ${issuer}"
  else
    warn "unexpected issuer: ${issuer}"
  fi
else
  warn "openssl not found: issuer not checked"
fi

echo
if [ "$FAILED" = 0 ]; then echo "RANCHER HEALTHY"; else echo "RANCHER NOT HEALTHY"; fi
exit "$FAILED"
