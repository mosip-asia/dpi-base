#!/usr/bin/env bash
# ==========================================================
# 🔑 Update Google OAuth Credentials for NetBird VPN
# ==========================================================
# Usage:
#   ./base-vpn/update_oauth.sh <CLIENT_ID> <CLIENT_SECRET>
# ==========================================================
set -euo pipefail

CLIENT_ID="${1:-}"
CLIENT_SECRET="${2:-}"

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "Usage: $0 <GOOGLE_OAUTH_CLIENT_ID> <GOOGLE_OAUTH_CLIENT_SECRET>"
  echo "Example: $0 123456789-abc.apps.googleusercontent.com GOCSPX-mysecret"
  exit 1
fi

MGMT_PROJECT="base-mgmt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 🔐 [1/2] Storing OAuth credentials in GCP Secret Manager ($MGMT_PROJECT)..."
echo -n "$CLIENT_ID" | gcloud secrets versions add google-oauth-client-id --project="$MGMT_PROJECT" --data-file=-
echo -n "$CLIENT_SECRET" | gcloud secrets versions add google-oauth-client-secret --project="$MGMT_PROJECT" --data-file=-

echo "==> 🚀 [2/2] Re-deploying NetBird stack with updated credentials..."
"$SCRIPT_DIR/remote-deploy.sh"

