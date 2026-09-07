# `dpi-vpn` — 24/7 Mesh Network Tier (NetBird)

**GCP Project**: `dpi-vpn`  
**Purpose**: 24/7 WireGuard Mesh VPN fabric connecting all downstream K3s clusters, management endpoints, and telemetry streams.

---

## 🏗 Architecture
* **Core Service**: NetBird Mesh VPN (Management API, Signal service, Coturn STUN/TURN, Dashboard UI)
* **Compute Host**: `e2-small` (2 vCPU, 2 GB RAM)
* **Operating Mode**: **24/7 Always-On** (~$14/month)
* **Public Static IP**: Attached for WebRTC signaling and STUN/TURN UDP traversal
* **DNS FQDN**: `netbird.dpi.ait.ac.th` (and `signal.dpi.ait.ac.th`)

---

## 📁 Directory Structure
```text
dpi-vpn/
├── README.md              # This documentation
├── terraform/             # VPC, firewall rules (UDP 3478, 10000, 51820), static IP, e2-small VM
└── docker/                # NetBird docker-compose.yml, Caddy/Nginx reverse proxy, OIDC configs
```

---

## 🔑 Identity & Multi-Domain Authentication Policy

NetBird uses **Google OAuth2 / OIDC** for single sign-on (SSO), allowing operators, researchers, and contributors to authenticate using their respective organizational or personal accounts.

### Accepted Email Domains:
* **`@dpi.ait.ac.th`**: Internal DPI Center Cloud Identity accounts.
* **`@ait.asia`**: AIT university faculty, researchers, and technical administrators.
* **`@ait.ac.th`**: Institutional academic accounts.
* **`@gmail.com`**: Designated external partners and personal Google accounts.

### 🛡️ Security & Zero-Trust Access Control
1. **External Consent Screen**: The Google OAuth Web Client (stored in `dpi-mgmt` Secret Manager) is configured with user type **External** in GCP Console so users across all 4 domains can sign in.
2. **Admin Approval Gate**: In NetBird Dashboard, **Auto-registration is restricted** (or User Approval is required). While anyone with a valid Google account can reach the Google login screen, **mesh VPN network access is only granted after an administrator (`akraradet@ait.asia` or `nuttasit@ait.asia`) explicitly approves the peer account**.
3. **Setup Keys for Automation**: Downstream K3s clusters do not use human OAuth logins; they join using pre-shared Setup Keys (`k3s-control-enroll`, `k3s-downstream-enroll`) injected via Terraform/Secret Manager.

See complete setup instructions in [`dpi-mgmt/oauth_setup.md`](../dpi-mgmt/oauth_setup.md).

