# DPI Center Base (`dpi-base`) — AI Assistant Guidelines

## 📌 Repository Overview
This repository serves as the central knowledge base, infrastructure runbook, organization management plane, and GitOps configuration repository for the **DPI Center (Digital Public Infrastructure Center)**.

---

## 🏗 System Architecture & Key Domains

### 1. Core Management Plane (`dpi-mgmt/`) — `dpi-mgmt`
- **Purpose**: Permanent, decoupled, low-cost (~$0.20/mo base), 100% Stateless GitOps management control plane.
- **Organization Boundary**: Governed by the Google Cloud Organization for **`dpi.ait.ac.th`** (Org ID: `350922776586`) using **Cloud Identity Free** ($0/month base, up to 50 managed identities with free quota scaling).
- **Decoupled Architecture & GCP Resource Hierarchy**:
  - **Root Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`) under Cloud Identity Free.
  - **Root Management Folder**: **`dpi-base`** directly mirrors this repository structure 1:1, consolidating management billing and admin IAM.
  - **Management Projects inside `dpi-base`**:
    1. **Foundation (`dpi-mgmt/`)**: Root IAM governance, remote state (`gs://dpi-mgmt-tfstate`), and Secret Manager prerequisite keys for `dpi-base` only.
    2. **Network Fabric (`dpi-vpn/`)**: 24/7 NetBird Mesh VPN tier.
    3. **Control Plane (`dpi-kube-ops/`)**: On-demand Rancher and central observability tier.
  - **Sovereign Domain Pattern for Workloads**: `dpi-mgmt` is strictly scoped to `dpi-base`. Workload initiatives (MOSIP, DLMS, research testbeds) MUST NEVER store state or secrets in `dpi-mgmt`. Each domain maintains its own GCP folder, a dedicated `<domain>-mgmt` anchor project, and an isolated state bucket (`gs://<domain>-tfstate`).
  - **Flattened Terraform Layout**: Infrastructure code inside management anchors must live directly at `<project>/terraform/` without nested subdirectories (e.g. avoid `terraform/foundation/`).
  - **Folder-Level IAM Governance**: Grant team member access at the GCP Folder level using additive bindings (`google_folder_iam_member`) so permissions cleanly inherit to all child projects (`<domain>-mgmt`, `<domain>-*`) without duplicating project-level IAM.
- **GCS Remote State Backend**: `dpi-base` Terraform modules target `backend "gcs"` with bucket `gs://dpi-mgmt-tfstate` and prefix `foundation`.
- **Authoritative DNS Invariant**: Public apex domain `dpi.ait.ac.th` is delegated by AIT to Cloud DNS Shard A (`ns-cloud-a1`–`a4`) and anchored in project `ait-brainlab-mgmt`. DNS records point to static IPs across the decoupled projects. Changes follow a strict 3-tier governance policy (Tier 1 GitOps PRs for apex/core; Tier 2 Kubernetes external-dns; Tier 3 delegated subdomains).

### 2. Identity & Access Governance
- **AuthN (Google OAuth2 / OIDC)**: Handles identity verification, SSO, and 2FA across DPI web portals, APIs, and administrative dashboards.
- **Super Administrator**: `admin@dpi.ait.ac.th` is the root break-glass recovery account for the Google Admin Console.
- **Operating Administrators**: `akraradet@ait.asia` and `nuttasit@ait.asia` are the primary technical operating identities, holding `roles/resourcemanager.organizationAdmin`, `roles/resourcemanager.projectCreator`, and `roles/billing.admin`.
- **External IAM Collaboration**: Project contributors and researchers authenticate using their existing university or authorized Google accounts directly in GCP IAM without consuming internal Cloud Identity licenses.
- **Cross-Domain Org Policy**: The organization policy `constraints/iam.allowedPolicyMemberDomains` must maintain `allValues: ALLOW` to allow institutional collaboration with `@ait.asia` accounts.
- **Multi-Domain OAuth Whitelist**: Human authentication via Google OAuth2 / OIDC is configured with User Type **"External"** in GCP Console to accept logins across four designated domains: (1) internal Cloud Identity (`@dpi.ait.ac.th`), (2) university operations (`@ait.asia`), (3) academic institutional (`@ait.ac.th`), and (4) designated personal accounts (`@gmail.com`). Downstream services (specifically NetBird Mesh VPN) MUST enforce an administrator approval workflow so that unapproved public Google accounts cannot obtain network routing.
- **No Shared Accounts Invariant**: Administrative accounts must never be shared across team members. All team members must authenticate via their own individual Google/university accounts with personal 2FA.

### 3. Multi-Cluster Control Plane & Network Fabric Architecture
- **2-Tier Decoupled Compute Model**:
  1. **24/7 Persistent Network Tier (`dpi-vpn`)**: NetBird (Mesh VPN) and central telemetry ingestion (VictoriaMetrics) run on a minimal, low-cost instance (`e2-small`, ~$14/mo) in GCP project **`dpi-vpn`** and must remain online 24/7 to maintain the WireGuard overlay across all clusters.
  2. **On-Demand Management Tier (`dpi-kube-ops`)**: Rancher Manager runs in a dedicated control project **`dpi-kube-ops`** on an `e2-standard-4` instance. Because downstream K3s clusters run 100% autonomously, Rancher SHOULD be configured with GCP Instance Schedules (or stopped when inactive) to save ~65–75% compute costs.

- **MOSIP Compatibility & Migration Guardrail**: Rancher is maintained primarily for MOSIP platform automation and API compatibility. All documentation and runbooks MUST maintain an evaluation of lightweight alternatives (e.g., Headlamp OSS, ArgoCD, Lens/k9s) for future decoupling.
- **Zero-Touch K3s Enrollment**: Downstream K3s clusters auto-enroll into the NetBird mesh using Setup Keys (`netbird up --setup-key <KEY>`) and import into Rancher via token manifests over private overlay IPs.
- **Ultra-Low Overhead Observability**: Telemetry uses VictoriaMetrics (Single) + Grafana Loki centrally, with `vmagent` and `promtail` on downstream K3s nodes (retaining <100MB RAM overhead per cluster).

### 4. Canonical Domain Taxonomy & Anti-Drift Invariant
AI assistants and documentation templates MUST strictly adhere to the DPI domain taxonomy:
- **`dpi.ait.ac.th`**: Apex domain, public portal, and Cloud Identity organization namespace.
- **`mgmt.dpi.ait.ac.th`**: Administrative management endpoints and ingress routing.
- **`demo.dpi.ait.ac.th`** / **`*.demo.dpi.ait.ac.th`**: Live demonstration services and digital public goods prototypes.
- **`api.dpi.ait.ac.th`**: Public API gateway endpoints.
- **Domain Identifier Invariant (`DOMAIN_NAME`)**:
  The domain slug defines the GCP Folder name, the Cloud DNS namespace (`<domain>.dpi.ait.ac.th`), and the mandatory prefix for all projects in that domain (`<domain>-mgmt`, `<domain>-k3s`). The slug must use lowercase alphanumeric characters and hyphens only, with a strict maximum of **24 characters** to keep `<domain>-mgmt` under GCP's 30-character project ID limit.

### 5. Automation & Landing Zone Bootstrap Tooling
- **Root Environment Configuration**: Repository-wide variables must reside at the repo root in `.env.example` (tracked) and `.env` (gitignored). Tooling must auto-detect target Terraform paths instead of requiring explicit path variables.
- **Pre-Flight Validation & DRY**: All environment validation logic must reside in `scripts/check_env.sh`. Bootstrap scripts must invoke `check_env.sh` as Step 0 rather than duplicating checks.
- **Dry-Run & Idempotent Apply**: Seed bootstrap scripts must support a `--plan` / `--dry-run` preview flag and be 100% idempotent (safe to run repeatedly without duplicating resources or errors).
- **Local Org Admin Execution**: Seed bootstrapping (creating folders, linking billing accounts) must be executed locally by human Organization Administrators with 2FA, never delegated to high-privilege CI/CD service accounts.

---

## 🔒 Security & Safe Operating Protocols
1. **No Hardcoded Secrets**: Never commit plain-text passwords, API tokens, OAuth client secrets, or private keys to version control.
2. **Terraform Safety**: Always apply `lifecycle { prevent_destroy = true }` on Cloud DNS zones, GCP Secret Manager keys, and permanent static IP resources.
3. **Decoupled Workload Plane**: Transient research workloads, containerized sandboxes, and heavy compute MUST NEVER run inside the management plane project (`dpi-mgmt`). They must run in dedicated workload projects (`dpi-workload-*`).
4. **Cloud Identity Cost Protection**: Always ensure user provisioning uses **Cloud Identity Free** ($0/month). Never activate paid Google Workspace subscriptions unless explicitly authorized with dedicated funding.
5. **Deterministic Version Pinning**: Pin all Terraform providers, modules, and container images to explicit versions.
6. **Timezone Standard**: Enforce `Asia/Bangkok` (ICT / UTC+7) across all infrastructure configurations, logs, and services.
7. **Control Plane Schedulability**: Any heavy management instance (e.g. Rancher) must support scheduled stopping without impacting workload clusters.
8. **Per-Project Least Privilege**: Workload contributors, researchers, and developers MUST ONLY receive access at the Project level (e.g. `roles/editor`), never at the Organization level, to prevent uncontrolled resource creation.
9. **Billing Protection Model**: Protect against unintended cloud spend by maintaining a prepaid credit balance via manual early top-ups ("Make a payment") and configuring budget threshold alerts before launching new workloads.
10. **Public Billing Privacy**: In public repositories, never commit real GCP Billing Account IDs in code, documentation, or `.env.example`. Always use masked placeholders (`01XXXX-XXXXXX-XXXXXX`).


