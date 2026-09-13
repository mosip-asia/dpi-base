# DPI Center Base (`dpi-base`) — Operations & Infrastructure Hub

Welcome to the **DPI Center (Digital Public Infrastructure Center)** central operations repository, infrastructure runbook, organization management plane, and GitOps hub.

---

## 📌 What This Repository Is For

This repository acts as the **single source of truth** and **Platform Engine** for the DPI Center under Google Cloud Organization **`dpi.ait.ac.th`** (Org ID: `350922776586`).

It manages:
1. **Core Management Plane (`base-mgmt`)**: Authoritative Cloud DNS subzones, IAM governance, automated Secret Manager storage, and GCS remote state for platform foundation.
2. **Network Fabric (`base-vpn`)**: 24/7 NetBird WireGuard mesh VPN connecting all distributed clusters and developer workstations over private overlay IPs (`100.64.0.0/16`).
3. **Multi-Cluster Control Plane (`dpi-kube-ops`)**: On-demand Rancher Kubernetes manager (with GCP Instance Schedules for 65–75% cost savings) and ultra-low overhead telemetry (VictoriaMetrics + Grafana Loki).
4. **Landing Zone Automation (`scripts/`)**: Idempotent bootstrap tooling (`bootstrap_domain.sh`, `check_env.sh`) that provisions new Sovereign Domains in 60 seconds.

---

## 🏗️ Architecture: Platform Engine vs. Sovereign Domains

DPI Center enforces a **Federated Domain Landing Zone Pattern**:
* **`base` (This Repository & Folder)**: The **Platform Engine**. Contains only shared network fabric, cluster management, and base foundation. Remote state (`gs://base-dpi-ait-ac-th-tfstate`) and secrets in `base-mgmt` are **strictly scoped to `base` only**.
* **Workload Domains (`mosip-asia`, `dlms`, `ai-team`, etc.)**: Autonomous product initiatives. Each domain receives its own GCP Folder, dedicated grant billing account, and dedicated **`<domain>-mgmt` anchor project** (`gs://<domain>-tfstate`) with zero blast radius to `base`.

```mermaid
flowchart TD
    ORG["🏢 Google Cloud Organization: dpi.ait.ac.th (350922776586)"]

    subgraph FOLDER_BASE ["📁 Folder: base (Platform Provider — THIS REPO)"]
        direction TB
        P_MGMT["📦 Project: base-mgmt<br/>• gs://base-dpi-ait-ac-th-tfstate (Base state ONLY)<br/>• Base secrets (OAuth, VPN tokens)<br/>• Subzone: base.dpi.ait.ac.th"]
        P_VPN["📦 Project: base-vpn (24/7 NetBird Mesh VPN)"]
        P_KUBE["📦 Project: dpi-kube-ops (Rancher & Observability)"]
    end

    subgraph FOLDER_MOSIP ["📁 Folder: mosip-asia (Identity Domain)"]
        direction TB
        M_MGMT["📦 Project: mosip-asia-mgmt<br/>• gs://mosip-asia-tfstate<br/>• Dedicated Secret Manager<br/>• Dedicated CI/CD SA"]
        M_WORK["📦 Project: mosip-asia-k3s"]
    end

    subgraph FOLDER_DLMS ["📁 Folder: dlms (Driving License Domain)"]
        direction TB
        D_MGMT["📦 Project: dlms-mgmt<br/>• gs://dlms-tfstate<br/>• Dedicated Secret Manager"]
        D_WORK["📦 Project: dlms-workload"]
    end

    ORG --> FOLDER_BASE
    ORG --> FOLDER_MOSIP
    ORG --> FOLDER_DLMS

    P_VPN -.->|WireGuard Overlay Mesh| M_WORK
    P_VPN -.->|WireGuard Overlay Mesh| D_WORK
    P_KUBE -.->|Kubernetes Management| M_WORK
    P_KUBE -.->|Kubernetes Management| D_WORK
```

---

## 👥 Identity & Governance Model

We enforce a strict separation between break-glass recovery and daily operational identities:

| Identity | Entity | Role in Infrastructure | Governance Standard |
| :--- | :--- | :--- | :--- |
| **`admin@dpi.ait.ac.th`** | Cloud Identity Root | **Super Administrator** | Root break-glass recovery account for Google Admin Console and Org policies. Never used for daily CLI operations. |
| **`akraradet@ait.asia`** | DPI Operations | **Operating Administrator** | Daily administrative identity. Holds `roles/resourcemanager.organizationAdmin`, `roles/billing.admin`, `roles/resourcemanager.projectCreator`. |
| **`nuttasit@ait.asia`** | DPI Operations | **Operating Administrator** | Daily administrative identity. Holds `roles/resourcemanager.organizationAdmin`, `roles/billing.admin`, `roles/resourcemanager.projectCreator`. |
| **`dpi.ait.ac.th`** | Apex Domain | **Cloud Identity Free** | Free identity tier ($0/mo, Org ID: `350922776586`) governing all DPI projects, folders, and IAM policies. |

---

## 🚀 Quickstart: Developer Workspace Setup

When onboarding as a contributor or cloning this repository, follow these steps to configure your local environment:

### 1. Authenticate with Google Cloud
Ensure your local `gcloud` CLI and Application Default Credentials (ADC) are authenticated with your authorized operating identity (e.g. `@ait.asia`):
```bash
gcloud auth login
gcloud auth application-default login
```

### 2. Configure Local Environment (`.env`)
Copy the environment template:
```bash
cp .env.example .env
```
* **For Workload Developers & Contributors**:  
  You can leave `BILLING_ACCOUNT_ID` blank (`BILLING_ACCOUNT_ID=""`). Child project envelopes (`prj-*.tf`) automatically query the billing account dynamically from GCP Secret Manager at runtime, so you do not need the billing ID on disk.
* **For Management Plane Operators (Day-0 Bootstrap, Relinking Billing, or Secret Management)**:  
  If you are an authorized administrator managing `<domain>-mgmt`, manually retrieve the billing ID from Secret Manager and set it in `.env`:
  ```bash
  gcloud secrets versions access latest --secret=billing-account-id --project=base-mgmt
  ```

### 3. Verify Configuration
Run pre-flight checks to ensure your workstation and IAM permissions are ready:
```bash
./scripts/check_env.sh
```

---

## 📁 Repository Directory Structure

```text
dpi-base/
├── README.md                      # What this repository is for (this file)
├── STATUS.md                      # Current situation, deployment checklist & roadmap
├── AGENTS.md                      # AI Assistant operating guidelines & invariants
├── GEMINI.md                      # Pointer to AGENTS.md
├── .env.example                   # Domain configuration template (copy to .env)
│
├── scripts/                       # Platform Automation & Admin Tooling
│   ├── check_env.sh               # Pre-flight environment & GCP API validator
│   └── bootstrap_domain.sh        # Seed bootstrap with --plan & idempotent apply
│
├── docs/                          # Standard Operating Procedures (Runbooks)

│   ├── sop-domain-mgmt.md         # Domain Landing Zone & Management Plane Runbook
│   └── sop-workload.md            # Workload Project & Compute Lifecycle Runbook
│
├── base-mgmt/                     # GCP Project: base-mgmt (Cloud DNS & Governance)
│   ├── oauth_setup.md             # Google OAuth2 / OIDC console setup SOP
│   └── terraform/                 # Foundation Cloud DNS, IAM, Secrets, GCS State
│
├── base-vpn/                      # GCP Project: base-vpn (NetBird Mesh VPN)
│   ├── terraform/                 # e2-small VM, static IP, firewall rules
│   └── docker/                    # NetBird docker-compose & reverse proxy configs
│
└── base-kube-ops/                 # GCP Project: base-kube-ops (Rancher & Observability)
    ├── terraform/                 # e2-standard-4 VM, Instance Schedule, K3s startup
    └── helm/                      # Rancher Community, VictoriaMetrics & Grafana values
```

---

## 🔗 Quick Navigation

* 🚦 **Current Situation & Deployment Progress**: See [`STATUS.md`](STATUS.md).
* 🏛️ **How to Provision a New Domain Landing Zone**: Follow [`docs/sop-domain-mgmt.md`](docs/sop-domain-mgmt.md).
* 💻 **How to Deploy a Workload Project**: Follow [`docs/sop-workload.md`](docs/sop-workload.md).
* 🎯 **GitHub Milestones & Tracking**: [GitHub Epic #1](https://github.com/mosip-asia/dpi-base/issues/1).

