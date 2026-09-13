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

2. **Creation in GCP Console**:
   - Log into [GCP Console Billing](https://console.cloud.google.com/billing) as an Org Admin or Billing Creator.
   - Click **Manage Billing Accounts** → **Create Account**.
   - Enter the name using the convention above.
   - Note the **Billing Account ID** (`01XXXX-XXXXXX-XXXXXX`).

3. **Prepaid Top-Up Workflow (Zero Surprise)**:
   - In GCP Console, go to **Payment overview** → **Make a payment** (Top-up).
   - Pay the approved quarterly grant amount (e.g. $150.00) using the PI or team credit card.
   - Download the instant PDF receipt and submit it to AIT Finance for reimbursement.

4. **Configure Budget Alerts**:
   - Set automated budget threshold alerts at 50%, 80%, and 100% of the prepaid balance to guarantee zero runaway spend.

---

## 🚀 Step 2: Seed Bootstrap Configuration

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

4. **Preview with Dry-Run (`--plan`)**:
   ```bash
   ./scripts/bootstrap_domain.sh --plan
   ```

5. **Execute Idempotent Apply**:
   ```bash
   ./scripts/bootstrap_domain.sh
   ```
   *Provisions folder, `<domain>-mgmt` project, billing association, core APIs, and `gs://<domain>-dpi-ait-ac-th-tfstate`.*

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
   - `billing-account-id`: Populated with the domain's billing account ID.
   - `google-oauth-client-id` & `google-oauth-client-secret`: SSO placeholders.
4. **Folder-Level IAM**: Additive bindings (`roles/editor`, `roles/resourcemanager.folderAdmin`) for team members.

---

## 🔄 Step 4: Zero-Drift Developer Synchronization

To ensure team members never need to manually copy or handle sensitive billing IDs, the billing account is pulled directly from Secret Manager:

1. **Workstation Sync Command**:
   ```bash
   ./scripts/pull_env.sh
   ```
   *Fetches `billing-account-id` from GCP Secret Manager and populates `.env` and `terraform.tfvars` automatically.*
2. **Dynamic Terraform Resolution**:
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
   *Team members running Terraform never need `billing_account_id` in their local tfvars—Terraform queries Secret Manager dynamically.*

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
