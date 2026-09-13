# `base-vpn` — 24/7 Mesh Network Tier (NetBird)

**GCP Project**: `base-vpn`  
**Purpose**: 24/7 WireGuard Mesh VPN fabric connecting all downstream K3s clusters, management endpoints, and telemetry streams.

---

## 🏗 Architecture
* **Core Service**: NetBird Mesh VPN Control Plane (Management API, Signal service, Relay service, Dashboard UI)
* **Edge Proxy**: Traefik v3 with automated Let's Encrypt SSL (`acme.json` via HTTP-01 challenge)
* **Compute Host**: `e2-small` (2 vCPU, 2 GB RAM, 30 GB `pd-balanced` disk) running Ubuntu 24.04 LTS
* **Provisioning Method**: Declarative `cloud-init` (`#cloud-config`) via `user-data`
* **Operating Mode**: **24/7 Always-On** (~$14/month)
* **Public Static IP**: Attached for WebRTC signaling and Traefik edge routing
* **DNS FQDN**: `netbird.base.dpi.ait.ac.th` (anchored in `base-mgmt` Cloud DNS zone `dpi-base`)
* **Persistence & Hydration**: SQLite database (`store.db`) auto-hydrated from `gs://base-dpi-ait-ac-th-tfstate/backups/netbird/store.db` on boot, with 6-hourly automated snapshots and graceful shutdown backup

---

## 📁 Directory Structure
```text
base-vpn/
├── README.md              # Architecture and operating runbook
├── remote-deploy.sh       # Zero-downtime deployer & stack updater (runs locally over IAP)
├── ssh.sh                 # Fast IAP SSH connector (interactive shell or remote command)
├── update_oauth.sh        # Helper script to inject Google OAuth credentials
├── netbird/               # Canonical application stack & service manifests (monitored by Dependabot)
│   ├── deploy.sh          # VM-side service runner and compose manager (/opt/netbird/deploy.sh)
│   ├── backup_to_gcs.sh   # State & certificate snapshot script to GCS (/opt/netbird/backup_to_gcs.sh)
│   ├── docker-compose.yml # Traefik v3 + NetBird services with pinned versions
│   ├── .env.template      # Environment variables template
│   └── management.json.template # NetBird management & OIDC config template
└── terraform/             # Decoupled infrastructure code
    ├── backend.tf         # GCS backend (gs://base-dpi-ait-ac-th-tfstate/base-vpn)
    ├── main.tf            # Provider configuration
    ├── variables.tf       # Parameter declarations
    ├── network.tf         # Regional static IP & zero-trust firewall rules
    ├── compute.tf         # e2-small VM, service account, and cloud-init rendering
    ├── dns.tf             # Decoupled DNS record in base-mgmt
    ├── outputs.tf         # Static IP, NetBird URL, VM outputs
    └── templates/
        └── cloud-init.yaml.tftpl # OS bootstrapping, Docker CE, and backup systemd unit
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
1. **External Consent Screen**: The Google OAuth Web Client (stored in `base-mgmt` Secret Manager) is configured with user type **External** in GCP Console so users across all 4 domains can sign in.
2. **Admin Approval Gate**: In NetBird Dashboard, **Auto-registration is restricted** (or User Approval is required). While anyone with a valid Google account can reach the Google login screen, **mesh VPN network access is only granted after an administrator (`akraradet@ait.asia` or `nuttasit@ait.asia`) explicitly approves the peer account**.
3. **Setup Keys for Automation**: Downstream K3s clusters do not use human OAuth logins; they join using pre-shared Setup Keys (`k3s-control-enroll`, `k3s-downstream-enroll`) injected via Terraform/Secret Manager.

See complete setup instructions in [`base-mgmt/oauth_setup.md`](../base-mgmt/oauth_setup.md).

---

## 🚀 Deployment & Operations

### Step 1: Provision Infrastructure (Terraform)
Provisions the permanent regional static IP, firewall rules, decoupled DNS record, and the `e2-small` VM.
```bash
# Validate pre-flight environment
./scripts/check_env.sh

# Deploy base-vpn infrastructure
terraform -chdir=base-vpn/terraform init
terraform -chdir=base-vpn/terraform apply
```

### Step 2: Deploy Container Stack (Zero-Downtime)
Uploads service manifests to `/tmp/`, and executes `netbird/deploy.sh` on the VM over secure IAP:
```bash
./base-vpn/remote-deploy.sh
```

### Step 3: Automated Major Version Alerts (Dependabot)
GitHub Dependabot (`.github/dependabot.yml`) monitors `base-vpn/netbird/docker-compose.yml`.
- Patch and minor updates are ignored to prevent noise.
- Dependabot will automatically open a Pull Request when a **MAJOR** version of Traefik or NetBird is released.
- When a major version update PR is merged, deploy the update instantly with **zero VM recreation**:
  ```bash
  git pull
  ./base-vpn/remote-deploy.sh
  ```

### Step 4: Inject Google OAuth Credentials
Once the OAuth Web Client ID and Secret are created in GCP Console (per [`oauth_setup.md`](../base-mgmt/oauth_setup.md)):
```bash
./base-vpn/update_oauth.sh "<CLIENT_ID>" "<CLIENT_SECRET>"
```
This automatically saves credentials to Secret Manager in `base-mgmt` and re-deploys NetBird with the active OAuth provider.

### Step 5: Direct VM Access via IAP (`ssh.sh`)
Connect securely to the VPN VM without exposing port 22 to the public internet:
```bash
# Interactive shell session
./base-vpn/ssh.sh

# Run remote commands directly
./base-vpn/ssh.sh "cd /opt/netbird && sudo docker compose ps"
./base-vpn/ssh.sh "sudo docker logs traefik --tail 50"
```
