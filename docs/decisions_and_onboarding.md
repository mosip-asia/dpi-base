# DPI Center — Team Onboarding & Architecture Decision Records (ADR)

Welcome to the **DPI Center (Digital Public Infrastructure Center)** cloud engineering hub. This document serves as the single source of truth for all foundational architecture decisions, access policies, and operational runbooks for team members.

---

## 🏛️ 1. Google Cloud Organization & Resource Hierarchy

```text
Organization: dpi.ait.ac.th (350922776586)
│
├── 📁 Folder: dpi-base (Mirroring repository structure 1:1)
│   ├── 📦 Project: dpi-mgmt (189731855526) — Remote State (gs://dpi-mgmt-tfstate), Secrets, IAM
│   ├── 📦 Project: dpi-vpn — 24/7 Mesh VPN Tier (NetBird, WireGuard overlay, static IP)
│   └── 📦 Project: dpi-kube-ops — On-Demand Control Plane (Rancher, Observability)
│
└── 📁 Folder: dpi-workloads (Transient / Research Workloads)
    ├── 📦 Project: dpi-workload-mosip — MOSIP Demonstrator Testbed
    ├── 📦 Project: dpi-workload-dlms — Driver Licensing Demonstrator
    └── 📦 Project: dpi-workload-sandbox — Developer & Student Sandboxes
```

| Resource | Value / Identifier | Notes |
| :--- | :--- | :--- |
| **GCP Organization** | **`dpi.ait.ac.th`** | Governed under **Cloud Identity Free** ($0/month base). |
| **Organization ID** | **`350922776586`** | Root node for all center projects and folders. |
| **Directory Customer ID** | **`C0164ixfv`** | Google Workspace / Cloud Identity tenant identifier. |
| **Active Billing Account** | **`0199A6-1E141B-DC72A5`** | `My Billing Account` (prepaid credit balance + card). |
| **Root Management Folder** | **`dpi-base`** | Matches Git repository name 1:1; inherits admin IAM & consolidates billing. |
| **Core Management Project**| **`dpi-mgmt`** (`189731855526`)| Permanent anchor for remote state (`gs://dpi-mgmt-tfstate`), CI/CD SA, and Secret Manager. |
| **Network Fabric Project** | **`dpi-vpn`** *(Phase 2)* | 24/7 Mesh VPN Tier (NetBird `e2-small`, static IP, WireGuard overlay). |
| **Control Plane Project**  | **`dpi-kube-ops`** *(Phase 3)*| On-demand K8s management (Rancher `e2-standard-4`, VictoriaMetrics, Loki, Grafana). |
| **Authoritative DNS Anchor**| **`ait-brainlab-mgmt`** | Current host of `dpi-center` zone (Shard A `ns-cloud-a1`-`a4`) delegated from `ait.ac.th`. |

---

## 👥 2. Identity & Access Governance (IAM)

To prevent accidental outages and credential leaks, we enforce a strict **"Break-Glass Root vs. Daily Operating Admin"** model:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DPI IDENTITY ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┴──────────────────────────────┐
        ▼                                                             ▼
┌─────────────────────────────────────────┐     ┌─────────────────────────────────────────┐
│       Root / Break-Glass Admin          │     │        Daily Operating Admins           │
│        `admin@dpi.ait.ac.th`            │     │  `akraradet@ait.asia` & `nuttasit@...`  │
├─────────────────────────────────────────┤     ├─────────────────────────────────────────┤
│ • Used ONLY for emergency recovery      │     │ • Daily CLI and GCP Console operations │
│ • Cloud Identity Free Super Admin       │     │ • Organization Administrators           │
│ • No day-to-day coding or CLI runs      │     │ • Project Creators & Billing Admins     │
│ • Stored in secure password vault       │     │ • Receive all GCP alerts in real inboxes│
└─────────────────────────────────────────┘     └─────────────────────────────────────────┘
```

### Team Member Roster & Assigned Roles

| Identity | Entity | Organization Role | Billing Role | Project Access |
| :--- | :--- | :--- | :--- | :--- |
| **`admin@dpi.ait.ac.th`** | DPI SuperAdmin | Super Admin (Root) | `billing.admin` | `Owner` (`dpi-mgmt`) |
| **`akraradet@ait.asia`** | Akraradet S. | `organizationAdmin`, `projectCreator` | `billing.admin` | `Editor` (`dpi-mgmt`) |
| **`nuttasit@ait.asia`** | Nuttasit S. | `organizationAdmin`, `projectCreator` | `billing.admin` | `Editor` (`dpi-mgmt`) |

> [!IMPORTANT]
> **No Shared Accounts Policy**: Team members must **never** share passwords or 2FA tokens for `admin@dpi.ait.ac.th`. Everyone authenticates using their personal university email (`@ait.asia`) directly in GCP Console and `gcloud`.

---

## 💡 3. Key Architecture Decisions (ADR)

### Decision 1: Cloud Identity Free ($0/mo) vs. Google Workspace
* **Context**: Google pushes paid Google Workspace subscriptions ($6–$18/user/mo).
* **Decision**: We use **Cloud Identity Free** ($0.00/month forever). Inbound email forwarding for `@dpi.ait.ac.th` is handled at the DNS layer (MX records forwarding to university emails), completely eliminating paid mailbox fees.
* **Organization Policy**: The `constraints/iam.allowedPolicyMemberDomains` constraint was updated to allow `@ait.asia` users to hold root administrative roles.

### Decision 2: The 2-Tier Decoupled Compute Model
* **Context**: Running multi-cluster Kubernetes control planes and observability can easily cost $200–$400/month if unoptimized.
* **Decision**: We split infrastructure into two decoupled tiers:
  1. **Tier 1 (24/7 Persistent Network Fabric)**: NetBird (Mesh VPN) and central metric collection (VictoriaMetrics) run on a minimal `e2-small` VM (**~$14/month**). This ensures the WireGuard overlay across all clusters never drops.
  2. **Tier 2 (On-Demand Management Plane)**: Rancher Manager runs in `dpi-kube-ops` on an `e2-standard-4` instance. Because downstream K3s clusters run 100% autonomously, Rancher is configured with **GCP Instance Schedules** (e.g. 08:30–18:30 Mon–Fri or stopped when idle), saving **~65% to 75%** compute spend.

```
┌────────────────────────────────────────────────────────────────────────┐
│               TIER 1: 24/7 PERSISTENT NETWORK TIER                     │
│               - NetBird Mesh VPN (Signal, Management, Coturn)          │
│               - VictoriaMetrics TSDB (lightweight telemetry ingestion) │
│               Host: e2-small (~$14/month) — ALWAYS ONLINE              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ WireGuard Encrypted Mesh (100.64.0.0/16)
┌───────────────────────────────────▼────────────────────────────────────┐
│               TIER 2: ON-DEMAND MANAGEMENT TIER                        │
│               - Rancher Community Manager (MOSIP compatibility)        │
│               - Grafana UI & Loki Dashboards                           │
│               Host: e2-standard-4 (~$25/mo with auto-schedule)         │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ Cluster Registration & Metrics
    ┌───────────────────────────────┴──────────────────────────────┐
    ▼                                                              ▼
┌──────────────────────────────┐               ┌──────────────────────────────┐
│ Downstream K3s #01 (MOSIP)   │               │ Downstream K3s #02 (Sandbox) │
│ - netbird client             │               │ - netbird client             │
│ - cattle-cluster-agent       │               │ - cattle-cluster-agent       │
│ - vmagent & promtail         │               │ - vmagent & promtail         │
└──────────────────────────────┘               └──────────────────────────────┘
```

### Decision 3: Rancher Compatibility for MOSIP & Future Decoupling
* **Context**: MOSIP reference architecture and deployment automation (`mosip-infra` / Ansible playbooks) require Rancher's API and UI for multi-namespace microservice deployments.
* **Decision**: We run Rancher Community (100% free Apache 2.0 open-source image, $0 license fee) to guarantee 100% MOSIP compatibility.
* **Future Migration Guardrail**: We actively evaluate lightweight alternatives ([Headlamp OSS](https://headlamp-k8s.github.io/), ArgoCD GitOps, Lens/k9s) so we can decouple from Rancher when MOSIP automation permits.

### Decision 4: Ultra-Low Overhead Observability
* **Metrics**: **VictoriaMetrics Single** (uses 1/5th to 1/7th the RAM of standard Prometheus, with native remote-write).
* **Logs**: **Grafana Loki** (stores compressed chunked logs on disk/GCS without indexing full text).
* **Edge K3s Footprint**: Downstream clusters only run **`vmagent`** and **`promtail`**, keeping telemetry overhead **<100MB RAM total per cluster**.

### Decision 5: GCP Resource Hierarchy (`dpi-base` Folder & Project Decoupling)
* **Context**: Need granular invoice tracking, cost control, and a clean cognitive mapping between version control and cloud resources.
* **Decision**: We introduce a root GCP Folder named **`dpi-base`** under Organization `350922776586`, mirroring the Git repository structure 1:1:
  - `dpi-base/` (Repo) -> `dpi-base` (GCP Folder)
  - `dpi-mgmt/` -> Project `dpi-mgmt` (Remote state, Secret Manager, root IAM)
  - `dpi-vpn/` -> Project `dpi-vpn` (24/7 NetBird network fabric)
  - `dpi-kube-ops/` -> Project `dpi-kube-ops` (On-demand Rancher control plane)
* **Billing & Governance Benefits**:
  1. **Folder-Level Invoice Roll-ups**: Monthly cloud invoices cleanly separate fixed management overhead (`dpi-base` folder) from transient grant/research spending (`dpi-workloads` folder).
  2. **Project-Level Cost Caps**: Individual budget alerts configured per project (e.g. verify `dpi-vpn` remains flat at ~$14/mo, track Rancher instance schedule savings).
  3. **Inherited IAM**: Operating admins (`akraradet@ait.asia`, `nuttasit@ait.asia`) hold roles at the `dpi-base` folder level, automatically cascading down to all management tiers while strictly isolating workload developers.

### Decision 6: DNS Apex Anchoring in `ait-brainlab-mgmt` & 3-Tier DNS Governance
* **Context**:
  - The apex domain `dpi.ait.ac.th` is delegated from AIT's parent zone (`ait.ac.th`) to Google Cloud DNS Shard A (`ns-cloud-a1` to `ns-cloud-a4`).
  - Google Cloud DNS generates nameserver shards dynamically and prohibits transferring or reassigning specific nameservers across GCP projects. Recreating the zone in `dpi-mgmt` would assign a different shard (B, C, D, or E), requiring manual intervention from AIT IT to re-delegate.
  - To prevent service disruption to existing active records (MX mail forwarding, `obs.dpi.ait.ac.th`, `sandbox-a.dpi.ait.ac.th`) and eliminate the need to contact AIT IT, DNS anchoring must be deliberate.
* **Decision**:
  - The authoritative apex Cloud DNS zone remains anchored in **`ait-brainlab-mgmt`** (Zone: `dpi-center`).
  - DNS records are project-agnostic pointers: records in `ait-brainlab-mgmt` point to static external IPs in `dpi-vpn` (NetBird), `dpi-kube-ops` (Rancher), and workload ingresses.
* **Governance Standard (The 3-Tier DNS Policy)**:
  - **Tier 1 (Apex & Management)**: `dpi.ait.ac.th`, `netbird`, `rancher`, `MX`, `SPF`. Strictly locked down. Modified **ONLY via GitOps Pull Requests** in this repository. Zero direct GCP console editing.
  - **Tier 2 (Workloads & Demos)**: `*.demo.dpi.ait.ac.th`. Automated via Kubernetes **`external-dns`** controllers bound strictly to ingress resources. Automatically provisions and cleans up records.
  - **Tier 3 (Developer Sandboxes)**: High-churn development environments receive dedicated subdomain delegations (e.g. `*.sandbox-a.dpi.ait.ac.th` delegated to AWS Route 53 or dedicated test projects) granting team autonomy with zero blast radius to the root apex.

---

## 🛠️ 4. Developer Quickstart for Team Members

### Step 1: Log in with your University Account
On your personal development machine, run:
```bash
gcloud auth login yourname@ait.asia
```

### Step 2: Configure Project & Organization Context
```bash
# View the organization
gcloud organizations list
# Shows: dpi.ait.ac.th | 350922776586

# Set active project to the management plane
gcloud config set project dpi-mgmt
```

### Step 3: Git Workflow & Repository Structure
```text
dpi-base/
├── README.md                      # Central overview & architecture landing page
├── AGENTS.md                      # Operational invariants & rules for AI assistants
├── docs/
│   ├── decisions_and_onboarding.md # This onboarding & ADR guide
│   └── infra/network/             # DNS topology and network diagrams
├── dpi-mgmt/                      # Core Management Plane (dpi-mgmt)
│   ├── checklist.md               # Master phase tracking checklist
│   └── terraform/foundation/      # Cloud DNS, IAM, Secret Manager, GCS State
├── dpi-vpn/                       # 24/7 Mesh VPN Tier (dpi-vpn)
│   ├── terraform/                 # e2-small VM, static IP, firewall rules
│   └── docker/                    # NetBird docker-compose
└── dpi-kube-ops/                  # On-Demand Control Plane (dpi-kube-ops)
    ├── terraform/                 # e2-standard-4 VM, Instance Schedule
    └── helm/                      # Rancher, VictoriaMetrics, Grafana
```

---

## 📊 5. Active GitHub Project Tracking

All project milestones are tracked collaboratively on GitHub:
* 🎯 **[Epic #1: Multi-Cluster Control & Observability Plane](https://github.com/mosip-asia/dpi-base/issues/1)**
* ✅ **[Issue #2: Phase 0 - GCP Organization & Identity Foundation](https://github.com/mosip-asia/dpi-base/issues/2)** *(Closed / Done)*
* 🚀 **[Issue #3: Phase 1 - Foundation Management Plane (dpi-mgmt) & Cloud DNS](https://github.com/mosip-asia/dpi-base/issues/3)** *(Assigned: @akraradets)*
* 🌐 **[Issue #4: Phase 2 - Network Tier (dpi-vpn) & NetBird Mesh VPN](https://github.com/mosip-asia/dpi-base/issues/4)** *(Assigned: @akraradets)*
* 🐮 **[Issue #5: Phase 3 - Management Control Tier (dpi-kube-ops) & Rancher](https://github.com/mosip-asia/dpi-base/issues/5)** *(Assigned: Nuttasit)*
