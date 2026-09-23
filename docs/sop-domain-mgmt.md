# DPI Center — Standard Operating Procedures (SOP)
## Domain Landing Zone & Management Plane Runbook

**Document ID**: `SOP-OPS-DOMAIN-001`  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  
**Audience**: Organization Administrators, Principal Investigators (PIs), Domain Leads  

---

## 🧭 Overview & Architecture

Every major initiative, research grant, or partner demonstrator operates as an autonomous **Sovereign Domain** (e.g. `base`, `mosip-asia`, `dlms`).

```
[Sovereign Domain: e.g. mosip-asia]
├── 📁 GCP Folder: mosip-asia                     (Resource & IAM Boundary)
│   ├── 📦 Project: mosip-asia-mgmt               (Anchor Plane: State, Secrets, DNS)
│   │   ├── 🪣 Bucket: gs://mosip-asia-dpi-ait-ac-th-tfstate (State Backend, Versioning ON)
│   │   ├── 🔑 Secret Manager                     (billing-account-id, OAuth keys)
│   │   └── 🌐 Cloud DNS: mosip-asia.dpi.ait.ac.th
│   │
│   └── 📦 Workload Projects                      (Compute Plane — see sop-workload.md)
│       └── mosip-asia-k3s                        (Downstream cluster joining VPN)
```

**The Core Rule**: `base-mgmt` is strictly scoped to `base`. Workload domains **never** share state buckets, secrets, or billing accounts with `base`.

---

## 🏛️ Step 1: Grant Billing Account Setup (Model A)

Each grant maintains its own dedicated Google Cloud Billing Account for clean financial auditing and zero personal liability.

1. **Naming Standard**:
   ```text
   DPI Center - <Team or Grant Name>
   ```
   *Examples*:
   - `DPI Center - Base Platform`
   - `DPI Center - MOSIP Asia Grant`
   - `DPI Center - AI Team Grant`

   > [!IMPORTANT]
   > **Why Naming Matters**: Google Cloud prints the Billing Account Name verbatim on official monthly PDF invoices and top-up receipts. Having the explicit grant name on receipts allows immediate university reimbursement.

2. **Creation by Super Administrator (`admin@dpi.ait.ac.th`)**:
   - Log into [GCP Console Billing](https://console.cloud.google.com/billing) as **`admin@dpi.ait.ac.th`** (Cloud Identity Super Administrator).
   - Click **Manage Billing Accounts** → **Create Account**.
   - Enter the name using the convention above (e.g. `DPI Center - MOSIP Asia Grant`).
   - Complete billing profile setup and note the **Billing Account ID** (`01XXXX-XXXXXX-XXXXXX`).
   - *This guarantees permanent institutional ownership under `admin@dpi.ait.ac.th` from Day 0.*

3. **Delegate Operational Permissions (`akraradet@ait.asia`, `nuttasit@ait.asia`)**:
   - While still logged in as `admin@dpi.ait.ac.th`, select the newly created billing account.
   - In the right-hand **Permissions** panel (or **Account Management** tab), click **`+ ADD PRINCIPAL`**.
   - Add both operational administrators:
     - **`akraradet@ait.asia`**
     - **`nuttasit@ait.asia`**
   - Assign the role: **Billing Account Administrator** (`roles/billing.admin`).
   - Click **Save**.
   - *Operating administrators can now manage payments, link child projects, and execute Day-0 bootstrap CLI tooling without using the break-glass root account.*

4. **Prepaid Top-Up Workflow (Zero Surprise)**:
   - Go to **Payment overview** → **Make a payment** (Top-up).
   - Pay the approved quarterly grant amount (e.g. $150.00) using the PI or team credit card.
   - Download the instant PDF receipt and submit it to AIT Finance for reimbursement.

5. **Configure Budget Alerts**:
   - Set automated budget threshold alerts at 50%, 80%, and 100% of the prepaid balance to guarantee zero runaway spend.

---

## 🚀 Step 2: Seed Bootstrap Configuration

The seed bootstrap script (`scripts/bootstrap_domain.sh`) automates folder creation, anchor project setup, billing linkage, state bucket provisioning, and secret seeding.

### 📋 Bootstrap Input / Output Contract

Before running the bootstrap, understand exactly what inputs are consumed and what cloud assets and local artifacts are produced:

#### 📥 Inputs Required

| Input Category | Variable / Prerequisite | Description & Requirements |
| :--- | :--- | :--- |
| **Authentication** | **Active `gcloud` Account** | Authenticated as an Org Admin (e.g. `akraradet@ait.asia`) via `gcloud auth login`. |
| | **ADC Credentials** | Local Application Default Credentials via `gcloud auth application-default login`. |
| | **IAM Permissions** | `roles/resourcemanager.organizationAdmin` (or `folderCreator` + `projectCreator`) on Org `350922776586`. |
| | **Billing Permission** | `roles/billing.admin` or `roles/billing.user` on the target billing account (owned by `admin@dpi.ait.ac.th`). |
| **Domain Identity** | **`DOMAIN_NAME`** | Unique domain slug (e.g. `mosip-asia`). Lowercase alphanumeric + hyphens, max 24 characters. |
| **Billing** | **`BILLING_ACCOUNT_ID`** | Active GCP Billing Account ID (`01XXXX-XXXXXX-XXXXXX`) created in Step 1. |
| **Hierarchy (Optional)**| **`ORGANIZATION_ID`** | Target Google Cloud Org ID (defaults to `350922776586` for `dpi.ait.ac.th`). |
| | **`PARENT_DOMAIN`** | Parent DNS apex (defaults to `dpi.ait.ac.th`). |
| | **`REGION`** | Primary GCP region for storage and compute (defaults to `asia-southeast1` Singapore). |
| | **`FOLDER_ADMINS`** | Comma-separated admin emails granted Folder Admin/Editor (`akraradet@ait.asia,nuttasit@ait.asia`). |
| | **`FOLDER_MEMBERS`** | (Optional) Comma-separated member emails granted Folder Viewer. |
| | **`STATE_BUCKET`** | (Optional) Custom bucket name override (defaults to `gs://<domain>-dpi-ait-ac-th-tfstate`). |

---

#### 📤 Outputs & Produced Assets

| Output Category | Asset Produced | Details & Verification |
| :--- | :--- | :--- |
| **Cloud Hierarchy** | **📁 GCP Folder** | `folders/<id>` named `<domain>` under Org `350922776586`. Serves as the IAM and billing boundary. |
| | **📦 Anchor Project** | Project `<domain>-mgmt` created inside the `<domain>` folder. |
| | **💳 Billing Association** | `<domain>-mgmt` permanently linked to `BILLING_ACCOUNT_ID`. |
| **Core Cloud APIs** | **GCP Service APIs** | Enabled on `<domain>-mgmt`: `cloudresourcemanager`, `serviceusage`, `storage`, `secretmanager`. |
| **Terraform State** | **🪣 GCS State Bucket** | `gs://<domain>-dpi-ait-ac-th-tfstate` in `asia-southeast1` with **Object Versioning ON**. |
| **Secret Vault** | **🔑 Secret Manager Safe** | Secret `billing-account-id` created in project `<domain>-mgmt`. |
| | **🔒 Secret Version 1** | Seeded with authoritative `BILLING_ACCOUNT_ID` (permanent, read-only for future Terraform). |
| **Local Workspace** | **📁 Code Directory** | `<domain>-mgmt/` scaffolded from `template-mgmt/` via `scripts/scaffold_domain.sh`. |
| | **📄 `terraform.tfvars`** | Auto-generated `<domain>-mgmt/terraform/terraform.tfvars` with folder ID, domain, and admin arrays. |

---

### 🛠️ Bootstrap Execution Steps

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

3. **(Optional) Pre-Scaffold Local Directory**:
   You can generate `<domain>-mgmt/` locally without cloud credentials at any time:
   ```bash
   ./scripts/scaffold_domain.sh
   ```
   *(Note: If you skip this, `bootstrap_domain.sh` will automatically invoke `scaffold_domain.sh` for you).*

4. **Validate Pre-Flight Configuration**:
   ```bash
   ./scripts/check_env.sh
   ```

5. **Preview with Dry-Run (`--plan`)**:
   ```bash
   ./scripts/bootstrap_domain.sh --plan
   ```

6. **Execute Idempotent Apply**:
   ```bash
   ./scripts/bootstrap_domain.sh
   ```
   *Auto-scaffolds `<domain>-mgmt/` (if missing), provisions GCP folder, creates `<domain>-mgmt` project, links billing account, enables core APIs, creates `gs://<domain>-dpi-ait-ac-th-tfstate`, seeds Secret Manager, and writes `terraform.tfvars`.*

---

## 🔒 Step 3: Deploy Management Plane via Terraform

Once the anchor project and bucket exist, deploy the domain's Terraform modules:

```bash
cd <domain>-mgmt/terraform
terraform init
terraform plan
terraform apply
```

This provisions:
1. **Project Protection Lien**: Prevents accidental deletion of the anchor project.
2. **Cloud DNS Managed Zone**: Authoritative subzone (`<domain>.dpi.ait.ac.th.`).
3. **Secret Manager Store**:
   - `billing-account-id`: Platform prerequisite secret seeded by `bootstrap_domain.sh` on Day 0 and read via `data` source.
   - `google-oauth-client-id` & `google-oauth-client-secret`: SSO credential shells managed by Terraform.
4. **Folder-Level IAM**: Additive bindings (`roles/editor`, `roles/resourcemanager.folderAdmin`) for team members.

### Step 3.1: Seed OAuth Secret Payloads (One-Time Admin Seeding)

The `billing-account-id` secret is already created and seeded automatically by `bootstrap_domain.sh`. Once the Google OAuth Web Client credentials are generated in GCP Console (see `base-mgmt/oauth_setup.md`), the administrator seeds the OAuth secrets once out-of-band:

```bash
# Seed Google OAuth Client Credentials (once generated in GCP Console):
echo -n "YOUR_GOOGLE_CLIENT_ID" | gcloud secrets versions add google-oauth-client-id \
  --project="<domain>-mgmt" \
  --data-file=-

echo -n "YOUR_GOOGLE_CLIENT_SECRET" | gcloud secrets versions add google-oauth-client-secret \
  --project="<domain>-mgmt" \
  --data-file=-
```
*Once seeded, secret versions are permanent and immutable. All future Terraform runs query Secret Manager dynamically without needing secrets on disk.*


---

## 🔄 Step 4: Secret Management & Billing Resolution

To ensure team members never need to manually copy or store sensitive billing IDs in version control, billing is resolved directly from Secret Manager:

1. **For Workload Developers**:
   Leave `BILLING_ACCOUNT_ID=""` in `.env`. Child projects query Secret Manager directly at runtime via Terraform data sources.
2. **For Management Plane Operators (Relinking Billing or Day-0 Bootstrap)**:
   Authorized administrators can retrieve the authoritative billing ID manually from Secret Manager:
   ```bash
   gcloud secrets versions access latest --secret=billing-account-id --project=<domain>-mgmt
   ```
3. **Dynamic Terraform Resolution in Management Plane**:
   In `<domain>-mgmt/terraform/secrets.tf`:
   ```hcl
   data "google_secret_manager_secret_version" "billing_account" {
     project = var.project_id
     secret  = google_secret_manager_secret.billing_account_id.secret_id
     version = "latest"
   }

   locals {
     billing_account_id = data.google_secret_manager_secret_version.billing_account.secret_data
   }
   ```
   *Team members running Terraform never need `billing_account_id` in their local `terraform.tfvars`—Terraform queries Secret Manager dynamically.*

---

## 📦 Step 5: Child Project Container Pattern (`prj-*.tf`)

To prevent granting developers direct billing admin permissions, **project containers are declared declaratively in the management plane**:

1. Copy the standard template inside `<domain>-mgmt/terraform/prj-<workload>.tf`:
   ```hcl
   # 1. Project Container & Billing Association
   resource "google_project" "workload" {
     name            = "DPI <Domain> - <Workload Name>"
     project_id      = "<domain>-<workload>"
     folder_id       = var.folder_id
     billing_account = local.billing_account_id  # Reads from Secret Manager!
   }

   # 2. Enabled APIs for this Tier
   resource "google_project_service" "workload_services" {
     for_each = toset([
       "compute.googleapis.com",
     ])
     project            = google_project.workload.project_id
     service            = each.key
     disable_on_destroy = false
   }

   # 3. Project Deletion Protection Lien
   resource "google_resource_manager_lien" "workload_lien" {
     parent       = "projects/${google_project.workload.project_id}"
     restrictions = ["resourcemanager.projects.delete"]
     origin       = "terraform"
     reason       = "Permanent anchor for <Workload Name>"
   }
   ```
2. Open a Pull Request and run `terraform apply`. The GCP project is created with billing and APIs enabled.

---

## 🌐 Step 6: One-Time Parent DNS Delegation Handshake

Google Cloud DNS assigns 4 nameservers dynamically from 5 shards (A through E). The parent zone must be updated after the child zone is created:

1. **Retrieve Assigned Nameservers**:
   ```bash
   terraform -chdir=<domain>-mgmt/terraform output name_servers
   ```
2. **Add Delegation NS Record in Parent Zone** (`ait-brainlab-mgmt`):
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
