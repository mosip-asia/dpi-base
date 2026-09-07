# DPI Center Base (`dpi-base`) — Operations & Infrastructure Hub

Welcome to the **DPI Center (Digital Public Infrastructure Center)** central knowledge base, infrastructure runbook, organization management plane, and GitOps configuration repository.

---

## 📌 Repository Overview

This repository serves as the single source of truth for:
* **GCP Organization Governance**: Google Cloud Identity Free & Organization administration for **`dpi.ait.ac.th`** (Org ID: `350922776586`).
* **Team Onboarding & Decisions**: See complete Architecture Decision Records in [`docs/decisions_and_onboarding.md`](docs/decisions_and_onboarding.md).
* **Cloud Management Plane (`dpi-mgmt/`)**: Authoritative Cloud DNS, root IAM governance, automated Secret Manager key storage, and Single Sign-On (SSO) credentials.
* **Domain Landscape**: Public DNS records, routing, and email routing for `dpi.ait.ac.th` and managed subdomains.
* **Service Admin & Workload Runbooks**: Infrastructure definitions and deployment guides for DPI research platforms, identity infrastructure, and digital public goods (including **MOSIP** and **DLMS**).

---

## 🏗️ Architecture & Domain Landscape

DPI Center operates as an independent organization with dedicated cloud governance:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DPI DOMAIN & IDENTITY LANDSCAPE                       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                         │
        ┌────────────────────────────────┴────────────────────────────────┐
        ▼                                                                 ▼
┌────────────────────────────────────────┐      ┌────────────────────────────────────────┐
│          Operating Admins              │      │            DPI Apex Domain             │
│  `akraradet@ait.asia` & `nuttasit@...` │      │            `dpi.ait.ac.th`             │
├────────────────────────────────────────┤      ├────────────────────────────────────────┤
│ - Primary Technical & IAM Admins       │      │ - Google Cloud Organization Root       │
│ - Non-expiring operational identities  │      │ - Authoritative Cloud DNS Apex         │
│ - Org Admins & Billing Admins in GCP   │      │ - `admin@dpi.ait.ac.th` (Super Admin)  │
└────────────────────────────────────────┘      └────────────────────────────────────────┘
```

### Identity & Governance Matrix

| Identity / Domain | Entity | Role in Infrastructure | Governance Standard |
| :--- | :--- | :--- | :--- |
| **`admin@dpi.ait.ac.th`** | Cloud Identity Root | **Super Administrator** | Root break-glass recovery account for Google Admin Console and Org policies. |
| **`akraradet@ait.asia`** | DPI Operations | **Operating Admin** | Daily administrative identity. Holds `roles/resourcemanager.organizationAdmin`, `roles/billing.admin`, `roles/resourcemanager.projectCreator`. |
| **`nuttasit@ait.asia`** | DPI Operations | **Operating Admin** | Daily administrative identity. Holds `roles/resourcemanager.organizationAdmin`, `roles/billing.admin`, `roles/resourcemanager.projectCreator`. |
| **`dpi.ait.ac.th`** | DPI Apex Domain | **Google Cloud Organization** | Standalone Cloud Identity Free organization ($0/mo, Org ID: `350922776586`) governing all DPI projects, folders, and IAM policies. |


---

### 🛡️ Decoupled Infrastructure Model

To guarantee 100% uptime, zero single points of failure, and strict cost controls, infrastructure is decoupled into three dedicated GCP projects:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        3-PROJECT DECOUPLED GOVERNANCE MODEL                            │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
          ┌─────────────────────────────────┼─────────────────────────────────┐
          ▼                                 ▼                                 ▼
┌──────────────────────────────┐ ┌──────────────────────────────┐ ┌──────────────────────────────┐
│  ANCHOR PLANE: `dpi-mgmt`    │ │   NETWORK TIER: `dpi-vpn`    │ │ K8S & OBS: `dpi-kube-ops`    │
├──────────────────────────────┤ ├──────────────────────────────┤ ├──────────────────────────────┤
│ - Org: `dpi.ait.ac.th`       │ │ - NetBird Mesh VPN (WireGuard│ │ - Rancher Community (MOSIP)  │
│ - Monthly Cost: ~$0.20/mo    │ │ - 24/7 Always-On (e2-small)  │ │ - VictoriaMetrics & Loki     │
│ - DNS: Authoritative CloudDNS│ │ - Monthly Cost: ~$14.00/mo   │ │ - Schedulable (e2-standard-4)│
│ - Terraform Remote State     │ │ - Overlay: 100.64.0.0/16     │ │ - Monthly Cost: ~$25.00/mo   │
└──────────────────────────────┘ └──────────────────────────────┘ └──────────────────────────────┘
```

### 🗄️ Centralized Governance vs. Compute Separation Matrix

To eliminate confusion across team members, the table below defines exactly where shared state, DNS records, secrets, and compute workloads reside:

| Infrastructure Asset | Target GCP Project | State / Configuration Location | Architecture & Operational Invariant |
| :--- | :--- | :--- | :--- |
| **Authoritative Cloud DNS (`dpi.ait.ac.th`)** | **`dpi-mgmt`** | `dpi-mgmt/terraform/foundation/dns.tf` | **Centralized in `dpi-mgmt`**. All public subdomains (`vpn.mgmt.*`, `rancher.mgmt.*`, `demo.*`, `api.*`) are provisioned exclusively in the central Cloud DNS zone in `dpi-mgmt`. Sub-projects do not manage public DNS zones. |
| **Terraform Remote State Backend** | **`dpi-mgmt`** | GCS Bucket: `gs://dpi-mgmt-tfstate` | **Centralized in `dpi-mgmt`**. A single versioned, uniform-access GCS bucket stores state across all three tiers with distinct state prefixes: `foundation/`, `vpn/`, and `kube-ops/`. |
| **Root Secrets & Master OAuth** | **`dpi-mgmt`** | Google Secret Manager (`dpi-mgmt`) | **Centralized in `dpi-mgmt`**. Organization-level secrets (OAuth credentials, master WireGuard keys, recovery tokens) reside in `dpi-mgmt`. Compute instances read authorized secrets via IAM service accounts. |
| **Mesh VPN Gateway (NetBird)** | **`dpi-vpn`** | `dpi-vpn/terraform/` & `dpi-vpn/docker/` | **Isolated Compute in `dpi-vpn`**. Minimal `e2-small` VM running 24/7 to maintain the WireGuard overlay network. Pure network fabric; never polluted by Kubernetes or storage state. |
| **Cluster Ops & Observability (Rancher / Grafana)** | **`dpi-kube-ops`** | `dpi-kube-ops/terraform/` & `helm/` | **Isolated Compute in `dpi-kube-ops`**. Compute instance (`e2-standard-4`) scheduled to sleep when inactive (~65–75% savings). Can be stopped or rebuilt without affecting DNS or mesh VPN. |

---

## 📁 Repository Directory Structure

The repository structure matches our GCP projects with 1-to-1 symmetry:

```text
dpi-base/
├── README.md                      # Central landing page & architecture overview (this file)
├── AGENTS.md                      # AI Assistant context, system architecture, and operating rules
├── GEMINI.md                      # Shortcut pointer to AGENTS.md
│
├── docs/                          # 📋 Operational SOPs, ADRs & Infrastructure Runbooks
│   ├── decisions_and_onboarding.md # Complete team onboarding guide & architecture decisions
│   └── infra/network/             # DNS topology and network runbooks
│
├── dpi-mgmt/                      # 🛡️ GCP Project: `dpi-mgmt` (Cloud DNS & Governance)
│   ├── checklist.md               # Master phase tracking checklist
│   ├── oauth_setup.md             # Google OAuth2 / OIDC console setup SOP
│   └── terraform/                 # Foundation Cloud DNS, IAM, Secrets, GCS State
│
├── dpi-vpn/                       # 🌐 GCP Project: `dpi-vpn` (NetBird Mesh VPN)
│   ├── terraform/                 # e2-small VM, static IP, firewall rules
│   └── docker/                    # NetBird docker-compose & reverse proxy configs
│
└── dpi-kube-ops/                  # 📊 GCP Project: `dpi-kube-ops` (Rancher & Observability)
    ├── terraform/                 # e2-standard-4 VM, Instance Schedule, K3s startup
    └── helm/                      # Rancher Community, VictoriaMetrics & Grafana values
```

---

## 🚀 Quick Start & Next Steps

1. Read the **Team Onboarding & Architecture Decisions** in [`docs/decisions_and_onboarding.md`](docs/decisions_and_onboarding.md).
2. Review the implementation checklist in [`dpi-mgmt/checklist.md`](dpi-mgmt/checklist.md).
3. Track active milestones on **[GitHub Epic #1](https://github.com/mosip-asia/dpi-base/issues/1)**.

