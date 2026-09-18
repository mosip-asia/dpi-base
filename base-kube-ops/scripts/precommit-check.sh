#!/usr/bin/env bash
# ==============================================================================
# 🛡️ DPI Center — Pre-Commit Guard (read-only)
# ==============================================================================
# Run before every commit in this repository. Prints paths and line numbers only,
# never a value. Fails on staged:
#   - state, plans, tfvars (except .example), .terraform/, .env files, keys,
#     kubeconfigs and credential JSON files
#   - private keys, Rancher import URLs (bearer tokens), cloud or GitHub tokens,
#     Google OAuth client secrets and full billing account IDs (AGENTS.md rules 1
#     and 10: use the masked form 01XXXX-XXXXXX-XXXXXX)
#   - CRLF line endings in base-kube-ops files, which break scripts on the VM
#
# Usage:  ./base-kube-ops/scripts/precommit-check.sh     exit 0 = SAFE TO COMMIT, 1 = STOP
# ==============================================================================
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1

FAILED=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

echo "Ignore rules"
for f in base-kube-ops/terraform/terraform.tfstate base-kube-ops/terraform/plan.tfplan base-kube-ops/terraform/tfplan \
         base-kube-ops/terraform/.terraform/x base-kube-ops/terraform/terraform.tfvars base-kube-ops/rancher/.env \
         base-kube-ops/.local/rancher-import.secret; do
  git check-ignore -q "$f" && pass "ignored: $f" || fail "NOT ignored: $f (restore the rule in .gitignore)"
done

STAGED="$(git diff --cached --name-only --diff-filter=ACMR | tr -d '\r')"

echo "Staged paths"
if [ -z "$STAGED" ]; then
  pass "nothing staged"
else
  BAD="$(printf '%s\n' "$STAGED" \
    | grep -E '\.tfstate|\.tfplan$|(^|/)tfplan$|(^|/)\.terraform/|\.tfvars$|(^|/)\.env$|\.env\.local$|\.(pem|key|p12|pfx|crt|csr)$|kubeconfig|(^|/)k3s\.yaml$|credentials\.json$|client_secret.*\.json$|service-account.*\.json$' \
    | grep -vE '\.tfvars\.example$' || true)"
  if [ -z "$BAD" ]; then pass "no secret-shaped path staged"
  else fail "secret-shaped paths staged, unstage them:"; printf '%s\n' "$BAD" | sed 's/^/          /'; fi
fi

echo "Staged content"
if [ -n "$STAGED" ]; then
  HITS="$(git diff --cached -U0 | tr -d '\r' | grep -nE '^\+' \
    | grep -E -- '-----BEGIN [A-Z ]*PRIVATE|/v3/import/[A-Za-z0-9]|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|nbp_[A-Za-z0-9]{10,}|GOCSPX-[A-Za-z0-9_-]{10,}|"private_key"[[:space:]]*:|(^|[^0-9A-Za-z])[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}([^0-9A-Za-z]|$)' \
    | cut -d: -f1 || true)"
  if [ -z "$HITS" ]; then pass "no private key, token, OAuth secret or full billing account ID in the staged diff"
  else fail "secret-shaped content in the staged diff (line numbers of 'git diff --cached -U0'):"; printf '%s\n' "$HITS" | tr '\n' ' ' | sed 's/^/          /'; echo; fi
else
  pass "nothing staged"
fi

echo "Line endings"
KO_STAGED="$(printf '%s\n' "$STAGED" | grep '^base-kube-ops/' || true)"
if [ -n "$KO_STAGED" ]; then
  # Word splitting is intended: one path per word (repository paths contain no spaces).
  # shellcheck disable=SC2086
  CRLF="$(git ls-files --eol -- $KO_STAGED 2>/dev/null | tr -d '\r' | awk '$1 == "i/crlf" {print $NF}')"
  if [ -z "$CRLF" ]; then pass "no CRLF staged under base-kube-ops/"
  else fail "CRLF staged under base-kube-ops/ (convert to LF):"; printf '%s\n' "$CRLF" | sed 's/^/          /'; fi
else
  pass "no base-kube-ops files staged"
fi

echo
if [ "$FAILED" = 0 ]; then echo "SAFE TO COMMIT"; exit 0
else echo "STOP: fix the FAIL lines before committing"; exit 1; fi
