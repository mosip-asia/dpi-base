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
VPN_PROJECT="base-vpn"
VM_NAME="base-vpn-vm"
ZONE="asia-southeast1-a"

echo "==> 🔐 [1/3] Storing OAuth credentials in GCP Secret Manager ($MGMT_PROJECT)..."
echo -n "$CLIENT_ID" | gcloud secrets versions add google-oauth-client-id --project="$MGMT_PROJECT" --data-file=-
echo -n "$CLIENT_SECRET" | gcloud secrets versions add google-oauth-client-secret --project="$MGMT_PROJECT" --data-file=-

echo "==> 🖥️ [2/3] Updating credentials on VM ($VM_NAME via IAP)..."
gcloud compute ssh "$VM_NAME" --project="$VPN_PROJECT" --zone="$ZONE" --tunnel-through-iap --command="
  sudo sed -i 's|^GOOGLE_OAUTH_CLIENT_ID=.*|GOOGLE_OAUTH_CLIENT_ID=\"$CLIENT_ID\"|' /opt/dpi/.env
  sudo sed -i 's|^GOOGLE_OAUTH_CLIENT_SECRET=.*|GOOGLE_OAUTH_CLIENT_SECRET=\"$CLIENT_SECRET\"|' /opt/dpi/.env
  sudo jq '.HttpConfig.AuthClientID = \"$CLIENT_ID\" | .HttpConfig.AuthAudience = \"$CLIENT_ID\" | .PKCEAuthorizationFlow.ProviderConfig.ClientID = \"$CLIENT_ID\" | .PKCEAuthorizationFlow.ProviderConfig.ClientSecret = \"$CLIENT_SECRET\" | .PKCEAuthorizationFlow.ProviderConfig.Audience = \"$CLIENT_ID\"' /opt/dpi/netbird/management.json > /tmp/mgmt.json && sudo mv /tmp/mgmt.json /opt/dpi/netbird/management.json
  sudo chmod 600 /opt/dpi/.env
  sudo systemctl restart dpi-vpn.service
"

echo "==> 🔄 [3/3] NetBird services restarted with new OAuth credentials!"
echo "==> 🌐 Access NetBird Dashboard: https://netbird.base.dpi.ait.ac.th"
