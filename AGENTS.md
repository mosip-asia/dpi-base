# DPI Center Base (`dpi-base`) — AI Assistant Guidelines

## 📌 Repository Overview
This repository serves as the central knowledge base, infrastructure runbook, organization management plane, and GitOps configuration repository for the **DPI Center (Digital Public Infrastructure Center)**.

---

## 🏗 System Architecture & Key Domains

### 1. Core Management Plane (`base-mgmt/`) — `base-mgmt`
- **Purpose**: Permanent, decoupled, low-cost (~$0.20/mo base), 100% Stateless GitOps management control plane.
- **Organization Boundary**: Governed by the Google Cloud Organization for **`dpi.ait.ac.th`** (Org ID: `350922776586`) using **Cloud Identity Free** ($0/month base, up to 50 managed identities with free quota scaling).
- **Decoupled Architecture & GCP Resource Hierarchy**:
  - **Root Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`) under Cloud Identity Free.
  - **Root Management Folder**: **`base`** directly mirrors this repository structure 1:1, consolidating management billing and admin IAM.
  - **Management Projects inside `base`**:
    1. **Foundation (`base-mgmt/`)**: Root IAM governance, remote state (`gs://base-dpi-ait-ac-th-tfstate`), and Secret Manager prerequisite keys for `base` only.
    2. **Network Fabric (`base-vpn/`)**: 24/7 NetBird Mesh VPN tier.
    3. **Control Plane (`dpi-kube-ops/`)**: On-demand Rancher and central observability tier.
  - **Sovereign Domain Pattern for Workloads**: `base-mgmt` is strictly scoped to `base`. Workload initiatives (MOSIP, DLMS, research testbeds) MUST NEVER store state or secrets in `base-mgmt`. Each domain maintains its own GCP folder, a dedicated `<domain>-mgmt` anchor project, and an isolated state bucket (`gs://<domain>-<parent-domain-slug>-tfstate`).
  - **Flattened Terraform Layout**: Infrastructure code inside management anchors must live directly at `<project>/terraform/` without nested subdirectories (e.g. avoid `terraform/foundation/`).
  - **Folder-Level IAM Governance**: Grant team member access at the GCP Folder level using additive bindings (`google_folder_iam_member`) so permissions cleanly inherit to all child projects (`<domain>-mgmt`, `<domain>-*`) without duplicating project-level IAM.
- **GCS Remote State Backend**: `base-mgmt` Terraform modules target `backend "gcs"` with bucket `gs://base-dpi-ait-ac-th-tfstate` and prefix `foundation`.
- **Authoritative DNS Invariant**: Public apex domain `dpi.ait.ac.th` is delegated by AIT to Cloud DNS Shard A (`ns-cloud-a1`–`a4`) and anchored in project `ait-brainlab-mgmt`. DNS records point to static IPs across the decoupled projects. Changes follow a strict 3-tier governance policy (Tier 1 GitOps PRs for apex/core; Tier 2 Kubernetes external-dns; Tier 3 delegated subdomains).

### 2. Identity & Access Governance
- **AuthN (Google OAuth2 / OIDC)**: Handles identity verification, SSO, and 2FA across DPI web portals, APIs, and administrative dashboards.
- **Super Administrator**: `admin@dpi.ait.ac.th` is the root break-glass recovery account for the Google Admin Console.
- **Operating Administrators**: `akraradet@ait.asia` and `nuttasit@ait.asia` are the primary technical operating identities, holding `roles/resourcemanager.organizationAdmin`, `roles/resourcemanager.projectCreator`, and `roles/billing.admin`.
- **External IAM Collaboration**: Project contributors and researchers authenticate using their existing university or authorized Google accounts directly in GCP IAM without consuming internal Cloud Identity licenses.
- **Cross-Domain Org Policy**: The organization policy `constraints/iam.allowedPolicyMemberDomains` must maintain `allValues: ALLOW` to allow institutional collaboration with `@ait.asia` accounts.
- **Multi-Domain OAuth Whitelist**: Human authentication via Google OAuth2 / OIDC is configured with User Type **"External"** in GCP Console to accept logins across four designated domains: (1) internal Cloud Identity (`@dpi.ait.ac.th`), (2) university operations (`@ait.asia`), (3) academic institutional (`@ait.ac.th`), and (4) designated personal accounts (`@gmail.com`). Downstream services (specifically NetBird Mesh VPN) MUST enforce an administrator approval workflow so that unapproved public Google accounts cannot obtain network routing.
- **No Shared Accounts Invariant**: Administrative accounts must never be shared across team members. All team members must authenticate via their own individual Google/university accounts with personal 2FA.
- **Terraform Quota & Auth Architecture**: Human operators authenticating via Application Default Credentials (ADC) require an active quota project (`gcloud auth application-default set-quota-project base-mgmt`). For delegated multi-user domain teams or CI/CD, use dedicated domain service accounts (`<domain>-mgmt-terraform`) with additive folder-level permissions (`google_folder_iam_member`) and Workload Identity Federation / SA impersonation to eliminate local workstation quota drift.

### 3. Multi-Cluster Control Plane & Network Fabric Architecture
- **2-Tier Decoupled Compute Model**:
  1. **24/7 Persistent Network Tier (`base-vpn`)**: NetBird (Mesh VPN) and central telemetry ingestion (VictoriaMetrics) run on a minimal, low-cost instance (`e2-small`, ~$14/mo) in GCP project **`base-vpn`** and must remain online 24/7 to maintain the WireGuard overlay across all clusters.
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
- **Root & Stack Environment Configuration**:
  - Repository-wide variables must reside at the repo root in `.env.example` (tracked) and `.env` (gitignored). Tooling must auto-detect target Terraform paths instead of requiring explicit path variables.
  - VM service stacks must maintain a `.env.template` in git as the Single Source of Truth for all paths, project IDs, bucket names, and domain variables, with empty placeholders for dynamic secrets (`FOO=""`).
  - Deployment scripts must source `.env.template` / `.env` for defaults and purge temporary `/tmp` staging files after moving them so no operator-owned (`ext_*`) files linger on the host.
- **Pre-Flight Validation & DRY**: All environment validation logic must reside in `scripts/check_env.sh`. Bootstrap scripts must invoke `check_env.sh` as Step 0 rather than duplicating checks.
- **Dry-Run & Idempotent Apply**: Seed bootstrap scripts must support a `--plan` / `--dry-run` preview flag and be 100% idempotent (safe to run repeatedly without duplicating resources or errors).
- **Local Org Admin Execution**: Seed bootstrapping (creating folders, linking billing accounts) must be executed locally by human Organization Administrators with 2FA, never delegated to high-privilege CI/CD service accounts.

### 6. Documentation Standard & Issue-Driven GitOps Workflow
- **The Consolidated 4-Document Standard**:
  To prevent documentation drift and fragmented sprawling files, all repository documentation is strictly consolidated into four canonical files:
  1. **`README.md`**: What the repo is for (purpose, decoupled architecture, platform vs. sovereign domains, core projects, IAM governance, quickstart developer setup, and repo layout).
  2. **`STATUS.md`**: Current situation of the repo (phase roadmap 0–4, live asset inventory, master task tracking checklist, and immediate next steps).
  3. **`docs/sop-domain-mgmt.md`**: Sovereign Domain Landing Zone & Management Plane Runbook (Grant billing setup, seed bootstrap, `<domain>-mgmt`, Secret Manager integration, parent DNS handshake, and `prj-*.tf` project container envelopes).
  4. **`docs/sop-workload.md`**: Workload Project & Compute Lifecycle Runbook (Workload naming `<domain>-<workload>`, workspace setup via `.env`, compute provisioning in `<domain>-<workload>/terraform/`, decoupled DNS records, and NetBird mesh VPN joining).

  - *Anti-Sprawl Rule*: AI assistants must NEVER create fragmented markdown files in nested `docs/` folders. All documentation updates must directly update `README.md`, `STATUS.md`, `docs/sop-domain-mgmt.md`, or `docs/sop-workload.md`.

- **Billing Account Naming Invariant**:
  All Google Cloud Billing Accounts must strictly adhere to the naming format: `DPI Center - <Team or Grant Name>` (e.g. `DPI Center - Base Platform`, `DPI Center - MOSIP Asia Grant`). This ensures that official Google Cloud PDF tax invoices and prepaid top-up receipts match grant budget lines verbatim for institutional university reimbursement.
- **Issue-Driven vs. PR-Driven GitOps Standard**:
  1. **Separation of Concerns (Issue vs. PR)**:
     - **GitHub Issue = Specification & Requirements Contract ("WHAT & WHY")**: Defines the problem statement, architecture decisions, acceptance criteria / definition of done, scope boundaries, and high-level milestones. Avoid turning the issue into a micro-commit log or transient scratchpad.
     - **Pull Request = Implementation & Verification Artifact ("HOW & PROOF")**: Created on a dedicated feature branch (`feat/issue-<number>-<description>` or `fix/issue-<number>-<description>`). Open a **Draft PR on Day 1** as soon as work begins. The PR description contains the implementation approach, atomic commit history with verification proofs/plans, and explicit issue closing keywords (`Closes #<number>`).
  2. **Draft PR on Day 1**:
     - As soon as a branch is created and initial scaffolding begins, push and open a Draft PR immediately (`gh pr create --draft`).
     - Enables continuous asynchronous collaboration, transparent progress visibility, peer review of in-flight design, and prevents duplicate work across team members and AI assistants.
     - When all tasks and acceptance criteria are fulfilled, convert the PR to Ready for Review (`gh pr ready`).
  3. **Atomic Commits & Plan-Verification Rule**:
     - Keep commits atomic and logically self-contained using Conventional Commits (`feat(...)`, `fix(...)`, `docs(...)`, `chore(...)`).
     - Major changes (e.g., Terraform infrastructure, security configurations, network topologies) should be verified with dry-run/plan execution logs and diff summaries documented in commit messages or PR comments.
  4. **Task Checklist Synchronization**:
     - Maintain strict alignment between the GitHub Issue acceptance criteria, the master task tracking checklist in `STATUS.md`, and the PR implementation checklist. Task completion checklists in `STATUS.md` must be kept in lockstep with GitHub Issues.
  5. **Issue Specification Revision & Handover Delineation**:
     - When updating or handing over an existing GitHub Issue specification, clearly delineate new/revised active specifications from historical original drafts.
     - Place the active specification at the top with an `[!IMPORTANT]` alert block, clear assignee, and current live status.
     - Preserve the original historical draft at the bottom inside an expandable `<details><summary>📜 Original Draft Specification (Historical Archive - Click to Expand)</summary>` block to maintain a full audit trail without confusing collaborators.


---

## 🔒 Security & Safe Operating Protocols
1. **No Hardcoded Secrets**: Never commit plain-text passwords, API tokens, OAuth client secrets, or private keys to version control.
2. **Terraform Safety**: Always apply `lifecycle { prevent_destroy = true }` on Cloud DNS zones, GCP Secret Manager keys, and permanent static IP resources.
3. **Decoupled Workload Plane**: Transient research workloads, containerized sandboxes, and heavy compute MUST NEVER run inside the management plane project (`base-mgmt`). They must run in dedicated workload projects (`<domain>-workload-*`).
4. **Cloud Identity Cost Protection**: Always ensure user provisioning uses **Cloud Identity Free** ($0/month). Never activate paid Google Workspace subscriptions unless explicitly authorized with dedicated funding.
5. **Deterministic Version Pinning**: Pin all Terraform providers, modules, and container images to explicit versions.
6. **Timezone Standard**: Enforce `Asia/Bangkok` (ICT / UTC+7) across all infrastructure configurations, logs, and services.
7. **Control Plane Schedulability**: Any heavy management instance (e.g. Rancher) must support scheduled stopping without impacting workload clusters.
8. **Per-Project Least Privilege**: Workload contributors, researchers, and developers MUST ONLY receive access at the Project level (e.g. `roles/editor`), never at the Organization level, to prevent uncontrolled resource creation.
9. **Billing Protection Model**: Protect against unintended cloud spend by maintaining a prepaid credit balance via manual early top-ups ("Make a payment") and configuring budget threshold alerts before launching new workloads.
10. **Public Billing Privacy**: In public repositories, never commit real GCP Billing Account IDs in code, documentation, or `.env.example`. Always use masked placeholders (`01XXXX-XXXXXX-XXXXXX`).
11. **Standard VM Security, Access & Secrets Invariant**:
    - **Zero Static SSH Keys**: All Compute Engine VMs must enforce `enable-oslogin = "TRUE"` and restrict SSH (port 22) strictly to Google Identity-Aware Proxy (IAP: `35.235.240.0/20`). Never bake static SSH public keys into `cloud-init` or instance metadata. Operators authenticate via their individual Google accounts (`@ait.asia`) with personal 2FA.
    - **Zero Plaintext Secrets in Cloud-Init**: Never store passwords, OAuth credentials, API keys, or private keys inside `cloud-init` user-data (which is stored in plaintext metadata). Attach a dedicated service account with granular `roles/secretmanager.secretAccessor` on `<domain>-mgmt` Secret Manager, pulling credentials into local root-owned mode `0600` files at runtime.
    - **Decoupled Compute vs. Application Lifecycle**: `cloud-init` strictly provisions OS packages, Docker CE, directories, and systemd units. Container workloads (e.g. `docker-compose.yml`) are deployed and updated independently over secure IAP to eliminate destructive VM recreations on version bumps.
    - **Unprivileged System Operator & Permissions Model**:
      - Add the default system account (`ubuntu`) to the `docker` group (`usermod -aG docker ubuntu`).
      - The service root directory (`/opt/<service>`) and all application manifests must be owned by `ubuntu:docker`.
      - Sensitive files (`.env`, `management.json`) must be restricted to mode `0600` (readable/writable only by `ubuntu`).
      - Strict exception: Traefik certificate stores (`acme.json`) must remain `0600 root:root` because Traefik's internal security scanner rejects certificate files not owned by root.
      - Provide an IAP SSH connector (`ssh.sh`) executing `-t "sudo -i -u ubuntu"` so operators drop directly into the `ubuntu` shell with native Docker access without typing `sudo`.
      - Deployment scripts must explicitly purge `/tmp` staging files after syncing to ensure no `ext_*` artifacts remain.
    - **Strict Decoupling: OS Bootstrapping (Cloud-Init) vs. Application Lifecycle (Deployer)**:
      - `cloud-init` strictly provisions host OS prerequisites: OS packages, Docker CE, swapfile, timezone, loopback hosts, base directory skeleton, and systemd units. `cloud-init` MUST NEVER restore databases from GCS, write backup scripts, or configure crontabs.
      - `deploy.sh` owns 100% of application state & lifecycle: Resolving secrets from GCP Secret Manager, restoring databases and TLS certificates from GCS, rendering `.env`, installing the 6-hourly backup crontab for root, managing containers, and executing initial state snapshots.
    - **Flat 1:1 Service Directory Layout & Cron-Safe Scripts**:
      - All stack manifests, deployers, and backup scripts must reside directly in `/opt/<service>/` matching the repository structure 1:1 with zero nested subdirectories.
      - Scripts must dynamically discover their own directory (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`) and source `.env` locally.
      - All scripts invoked by `cron` must explicitly export a full `PATH` (`/usr/local/bin:/usr/bin:/bin:/snap/bin:${PATH:-}`) at the very top.



