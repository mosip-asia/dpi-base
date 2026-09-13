# DPI Center — Standard Operating Procedures (SOP)
## Infrastructure, Sovereign Domains & Workload Projects Runbook

**Document ID**: `SOP-OPS-001`  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  
**Audience**: Operating Administrators, Principal Investigators (PIs), Domain Leads, Infrastructure Engineers  

---

## 🧭 Overview & Core Principles

This unified runbook provides complete operational procedures for managing cloud infrastructure across the Digital Public Infrastructure Center (DPI Center):

1. **Part 1: New Sovereign Domain Landing Zone** — How to onboard a new grant or initiative (e.g. `mosip-asia`, `ai-team`).
2. **Part 2: New Workload Project** — How to deploy a new project (K3s cluster, database, sandbox) under an existing domain.
3. **Part 3: Base Platform Operations** — How to update core infrastructure (`dpi-mgmt`, `dpi-vpn`, `dpi-kube-ops`) and DNS.

---

## 🏛️ Part 1: Provisioning a New Sovereign Domain (Landing Zone)

Every major initiative, research grant, or partner demonstrator operates as an autonomous **Sovereign Domain**.  
**The Core Rule**: `dpi-mgmt` is strictly scoped to `dpi-base`. Workload domains **never** share state buckets, secrets, or billing accounts with `dpi-base`.

```
[New Domain: e.g. mosip-asia]
├── 📁 GCP Folder: mosip-asia                     (Resource & IAM Boundary)
│   ├── 📦 Project: mosip-asia-mgmt               (Anchor Plane: State, Secrets, DNS)
│   │   ├── 🪣 Bucket: gs://mosip-asia-dpi-ait-ac-th-tfstate (State Backend, Versioning ON)
│   │   ├── 🔑 Secret Manager                     (Application Secrets & Keys)
│   │   └── 🌐 Cloud DNS: mosip-asia.dpi.ait.ac.th
│   │
│   └── 📦 Workload Projects (Part 2)             (Compute Plane)
│       └── mosip-asia-k3s                        (Downstream cluster joining VPN)
```

---

### Step 1.1: Grant Billing Account Setup (Model A)

Each grant maintains its own dedicated Google Cloud Billing Account for clean financial auditing and zero personal liability.

1. **Naming Standard**:
   ```text
   DPI Center - <Team or Grant Name>
   ```
   *Examples*:
   - `DPI Center - MOSIP Asia Grant`
   - `DPI Center - AI Team Grant`
   - `DPI Center - Sandbox & Training`

   > [!IMPORTANT]
   > **Why Naming Matters**: Google Cloud prints the Billing Account Name verbatim on official monthly PDF invoices and top-up receipts. Having the explicit grant name on receipts allows immediate university reimbursement.

2. **Creation in GCP Console**:
   - Log into [GCP Console Billing](https://console.cloud.google.com/billing) as an Org Admin or Billing Creator.
   - Click **Manage Billing Accounts** → **Create Account**.
   - Enter the name using the convention above.
   - Note the **Billing Account ID** (`01XXXX-XXXXXX-XXXXXX`).

3. **Prepaid Top-Up Workflow (Zero Surprise)**:
   - Never wait for monthly automatic post-billing.
   - In GCP Console, go to **Payment overview** → **Make a payment** (Top-up).
   - Pay the approved quarterly grant amount (e.g. $150.00) using the PI or team credit card.
   - Download the instant PDF receipt and submit it to AIT Finance on the same day for reimbursement.

4. **Configure Budget Alerts**:
   - Set automated budget threshold alerts at 50%, 80%, and 100% of the prepaid balance to guarantee zero runaway spend.

---

### Step 1.2: Seed Bootstrap Configuration

The seed bootstrap script automates folder creation, anchor project setup, billing linkage, and state bucket provisioning.

1. **Prepare `.env` at Repository Root**:
   ```bash
   cp .env.example .env
   ```
2. **Edit Required Variables**:
   ```bash
   # DOMAIN_NAME: max 24 chars, lowercase alphanumeric + hyphens
   # Defines GCP folder name, project prefix (<domain>-mgmt), and DNS namespace
   DOMAIN_NAME="mosip-asia"
   BILLING_ACCOUNT_ID="01XXXX-XXXXXX-XXXXXX"
   
   # Optional overrides (defaults to dpi.ait.ac.th Org ID: 350922776586)
   ORGANIZATION_ID="350922776586"
   PARENT_DOMAIN="dpi.ait.ac.th"
   REGION="asia-southeast1"
   FOLDER_ADMINS="akraradet@ait.asia,nuttasit@ait.asia"
   ```

3. **Validate Pre-Flight Configuration**:
   ```bash
   ./scripts/check_env.sh
   ```
   *Checks static syntax, string lengths, and live GCP Org/Billing connectivity.*

4. **Preview with Dry-Run (`--plan`)**:
   ```bash
   ./scripts/bootstrap_domain.sh --plan
   ```
   *Inspect the planned actions and preview the generated `terraform.tfvars` without modifying GCP.*

5. **Execute Idempotent Apply**:
   ```bash
   ./scripts/bootstrap_domain.sh
   ```
   *Safely provisions folder, project, billing association, core APIs, and `gs://<domain>-dpi-ait-ac-th-tfstate`.*

---

### Step 1.3: Deploy Management Plane via Terraform

Once the anchor project and bucket exist, deploy the domain's Terraform modules:

```bash
# Navigate to the target terraform directory
cd <domain>-mgmt/terraform

# Initialize backend with the domain's dedicated bucket
terraform init -backend-config="bucket=<domain>-dpi-ait-ac-th-tfstate"

# Review and apply
terraform plan
terraform apply
```

This provisions:
- Project lien (prevents accidental project deletion).
- Cloud DNS Managed Zone (`<domain>.dpi.ait.ac.th.`).
- Secret Manager prerequisite placeholders.
- Dedicated domain CI/CD Service Account.

---

### Step 1.4: One-Time Parent DNS Delegation Handshake

Google Cloud DNS assigns 4 nameservers dynamically from 5 shards (A through E). The parent zone must be updated **after** the child zone is created:

1. **Retrieve Assigned Nameservers**:
   ```bash
   terraform output name_servers
   # Output: ns-cloud-b1.googledomains.com, ns-cloud-b2..., etc.
   ```

2. **Add Delegation NS Record in Parent Zone**:
   - Parent Zone: `dpi-center` in project `ait-brainlab-mgmt`
   - Record Name: `<domain>` (e.g. `mosip-asia`)
   - Type: `NS`
   - Values: The 4 nameservers returned from Step 1.

   *CLI Execution (if you have access to `ait-brainlab-mgmt`)*:
   ```bash
   gcloud dns record-sets transaction start --zone=dpi-center --project=ait-brainlab-mgmt
   gcloud dns record-sets transaction add <NS1> <NS2> <NS3> <NS4> \
     --name="<domain>.dpi.ait.ac.th." --ttl=300 --type=NS --zone=dpi-center --project=ait-brainlab-mgmt
   gcloud dns record-sets transaction execute --zone=dpi-center --project=ait-brainlab-mgmt
   ```

3. **Verify Public Resolution**:
   ```bash
   dig NS <domain>.dpi.ait.ac.th +short
   ```

---

## 🚀 Part 2: Provisioning a New Workload Project (Inside a Domain)

When a domain needs compute resources (e.g., a Kubernetes cluster, database, or test sandbox), create a dedicated workload project under the domain's GCP Folder.

### Step 2.1: Workload Project Naming Convention
Follow the standard naming pattern:
```text
<domain>-<workload>
```
*Examples*:
- `mosip-asia-k3s` (Downstream MOSIP cluster)
- `mosip-asia-db` (Managed database or backend tier)
- `ai-team-sandbox` (Developer experiment sandbox)

### Step 2.2: Provisioning the Project
Run the following using an account with `projectCreator` permissions:
```bash
# 1. Look up the domain's numeric Folder ID
FOLDER_ID=$(gcloud resource-manager folders list --organization=350922776586 --filter="displayName='<domain>'" --format="value(name)")

# 2. Create the workload project inside the folder
gcloud projects create "<domain>-<workload>" --folder="${FOLDER_ID#folders/}"

# 3. Link the project to the domain's grant billing account
gcloud billing projects link "<domain>-<workload>" --billing-account="<BILLING_ACCOUNT_ID>"

# 4. Enable required workload APIs
gcloud services enable compute.googleapis.com container.googleapis.com --project="<domain>-<workload>"
```

### Step 2.3: Enrolling Compute Nodes into NetBird Mesh VPN
All downstream VMs (e.g., K3s nodes) connect to the central control plane securely over NetBird:
1. Obtain a reusable **Setup Key** from NetBird Admin Console (`netbird.dpi.ait.ac.th`).
2. Run on the VM (or add to `cloud-init` / user-data):
   ```bash
   curl -fsSL https://pkgs.netbird.io/install.sh | sh
   netbird up --management-url https://netbird.dpi.ait.ac.th:443 --setup-key <SETUP_KEY>
   ```
3. Node receives an overlay IP in `100.64.0.0/16`.

---

## 🛡️ Part 3: Base Platform Operations (`dpi-base`)

The platform engine (`dpi-base`) provides shared services for all sovereign domains:
- `dpi-mgmt`: State, secrets, and root DNS governance.
- `dpi-vpn`: 24/7 NetBird Mesh VPN (`e2-small`, ~$14/mo).
- `dpi-kube-ops`: On-demand Rancher Manager (`e2-standard-4`, Instance Schedule).

---

### Step 3.1: 3-Tier DNS Governance Policy

To prevent outages, security takeovers, and email delivery failures, DNS records are strictly governed:

| Tier | Namespace / Scope | Method | Policy |
| :---: | :--- | :--- | :--- |
| **Tier 1** | Apex `dpi.ait.ac.th`, `netbird`, `rancher`, `MX`, `SPF` | **GitOps PR** | Strictly locked. Direct GCP Console editing is forbidden. Requires PR review by Operating Admins (`@ait.asia`). |
| **Tier 2** | `*.demo.dpi.ait.ac.th`, `*.api.dpi.ait.ac.th` | **Kubernetes external-dns** | Automated via Ingress controllers in downstream clusters. Zero manual tickets. |
| **Tier 3** | `*.sandbox-a.dpi.ait.ac.th`, `<domain>.dpi.ait.ac.th` | **Subdomain NS Delegation** | Independent Cloud DNS zones delegated to domain anchors. Full team autonomy within subzone. |

---

### Step 3.2: Terraform Workflow for Base Infrastructure

All base changes must follow standard GitOps:

1. **Branching**:
   - Always create a feature branch linked to an issue: `git checkout -b feat/issue-<number>-<description>`.
2. **Execution**:
   ```bash
   cd dpi-mgmt/terraform       # or dpi-vpn/terraform, dpi-kube-ops/terraform
   terraform init
   terraform plan
   terraform apply
   ```
3. **Safety Rules**:
   - Permanent static IPs, DNS zones, and Secret Manager secrets must have `lifecycle { prevent_destroy = true }`.
   - Never run compute workloads inside `dpi-mgmt`.
   - Never commit `.env` or real billing account IDs to version control.

---

### Step 3.3: Google OAuth2 / Single Sign-On (SSO) Setup

For services requiring team authentication (NetBird, Rancher, Grafana):
1. Configure OAuth Consent Screen in GCP Console (`dpi-mgmt`):
   - **User Type**: `External`
   - **Support Email**: `akraradet@ait.asia`
   - **Authorized Domains**: `dpi.ait.ac.th`, `ait.asia`, `ait.ac.th`.
2. Create OAuth 2.0 Web Client ID:
   - Authorized Redirect URIs:
     - NetBird: `https://netbird.dpi.ait.ac.th/oauth2/callback`
     - Rancher: `https://rancher.dpi.ait.ac.th/verify-auth`
3. Seed secrets into Secret Manager:
   ```bash
   echo -n "<CLIENT_ID>" | gcloud secrets versions add google-oauth-client-id --data-file=- --project=dpi-mgmt
   echo -n "<CLIENT_SECRET>" | gcloud secrets versions add google-oauth-client-secret --data-file=- --project=dpi-mgmt
   ```
