# 🔑 Google OAuth2 / OIDC Setup Guide (`oauth_setup.md`)

> **Single Sign-On (SSO)**: If this domain hosts user-facing web services or admin dashboards requiring Google authentication, follow this one-time console runbook.

---

## 🛡️ Why This is a One-Time Console Step

Google Cloud Platform enforces a strict security boundary: **Generic OAuth 2.0 Web Client IDs cannot be created via Terraform or API**. 

Google intentionally requires a human project owner to approve the **OAuth Consent Screen** (branding, privacy policy, contact email) in the Google Cloud Console. 

Once created, the credentials are saved into **GCP Secret Manager** in `<domain>-mgmt`, and all subsequent deployments and applications read them automatically via configuration.

---

## 📋 Step-by-Step Operator Runbook

### Step 1: Configure OAuth Consent Screen
1. Open the [**GCP OAuth Consent Screen**](https://console.cloud.google.com/apis/credentials/consent) in project `<domain>-mgmt`.
2. Select **User Type**: **External** (REQUIRED to support multi-domain institutional users).
3. Fill in application registration:
   - **App Name**: `DPI Center - <Domain Name> Services`
   - **User Support Email**: `akraradet@ait.asia`
   - **Authorized Domains**: `dpi.ait.ac.th`
   - **Developer Contact Information**: `akraradet@ait.asia`, `nuttasit@ait.asia`
4. Under **Scopes**, select standard OIDC scopes:
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`
   - `openid`
5. Click **Save and Continue**.

---

### Step 2: Create the OAuth 2.0 Web Client ID
1. Navigate to the [**GCP Credentials Page**](https://console.cloud.google.com/apis/credentials) in `<domain>-mgmt`.
2. Click **`+ CREATE CREDENTIALS`** $\rightarrow$ **OAuth client ID**.
3. Set **Application type**: **Web application**.
4. Set **Name**: `DPI <Domain Name> SSO`.
5. Configure **Authorized JavaScript Origins** and **Authorized Redirect URIs** for your domain's services (e.g. `https://<service>.<domain>.dpi.ait.ac.th/callback`).
6. Click **CREATE**.

---

### Step 3: Store Client ID & Secret in GCP Secret Manager

Once generated, save credentials into Secret Manager:

```bash
# Seed Google OAuth Client Credentials:
echo -n "YOUR_CLIENT_ID" | gcloud secrets versions add google-oauth-client-id \
  --project="<domain>-mgmt" \
  --data-file=-

echo -n "YOUR_CLIENT_SECRET" | gcloud secrets versions add google-oauth-client-secret \
  --project="<domain>-mgmt" \
  --data-file=-
```
