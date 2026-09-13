# DPI Center — Standard Operating Procedures (SOP)
## Workload Project & Compute Lifecycle Runbook

**Document ID**: `SOP-OPS-WORKLOAD-001`  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  
**Audience**: Workload Engineers, Developers, Researchers  

---

## 🧭 Overview & Core Principles

When a domain needs compute resources (e.g. a Kubernetes cluster, microservices, databases, or test sandboxes), developers create a dedicated workload project under their domain's GCP folder.

```
<domain>/
├── <domain>-mgmt/                 # Anchor plane (DNS zone, secrets, prj-*.tf envelopes)
└── <domain>-<workload>/           # Compute plane (VMs, IPs, firewall, NetBird mesh)
    ├── terraform/                 # Compute & network resources + decoupled DNS
    └── docker/ or helm/           # Application & workload stack
```

**Key Advantages**:
1. **Decoupled Billing & IAM**: Developers only need `roles/editor` on their project. They do not need Billing Admin permissions.
2. **Decoupled DNS Record Ownership**: Workload projects declare their own DNS records directly in their own Terraform code targeting `<domain>-mgmt`.
3. **Zero Blast Radius**: Workload compute can be destroyed or rebuilt without affecting the domain management plane or billing linkage.

---

## 🚀 Step 1: Developer Workspace Setup

Before working on any project, developers set up their local workstation:

1. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
2. **Configure Local Environment (`.env`)**:
   ```bash
   cp .env.example .env
   ```
   *Note: For workload development, you can leave `BILLING_ACCOUNT_ID=""`. All project envelopes (`prj-*.tf`) fetch billing dynamically from Secret Manager at runtime.*
3. **Verify Environment**:
   ```bash
   ./scripts/check_env.sh
   ```


---

## 🏷️ Step 2: Workload Project Naming Convention

Follow the standard naming format:
```text
<domain>-<workload>
```
*Examples*:
- `base-vpn` (NetBird Mesh VPN tier in `base`)
- `base-kube-ops` (Rancher & Observability in `base`)
- `mosip-asia-k3s` (Downstream MOSIP K3s cluster in `mosip-asia`)
- `dlms-api` (Driver Licensing Management API backend in `dlms`)

---

## 📦 Step 3: Project Envelope Creation (`prj-<workload>.tf`)

Do **not** run manual `gcloud projects create` commands. Instead, create a declarative project envelope in `<domain>-mgmt/terraform/`:

1. Create `<domain>-mgmt/terraform/prj-<workload>.tf`:
   ```hcl
   # 1. Project Container & Billing Link
   resource "google_project" "my_workload" {
     name            = "DPI <Domain> - <Workload Name>"
     project_id      = "<domain>-<workload>"
     folder_id       = var.folder_id
     billing_account = local.billing_account_id  # Automatically queried from Secret Manager!
   }

   # 2. Enable Required APIs
   resource "google_project_service" "my_workload_services" {
     for_each = toset([
       "compute.googleapis.com",
       "container.googleapis.com", # If using GKE
     ])
     project            = google_project.my_workload.project_id
     service            = each.key
     disable_on_destroy = false
   }

   # 3. Project Deletion Protection Lien
   resource "google_resource_manager_lien" "my_workload_lien" {
     parent       = "projects/${google_project.my_workload.project_id}"
     restrictions = ["resourcemanager.projects.delete"]
     origin       = "terraform"
     reason       = "Permanent anchor for <Workload Name>"
   }
   ```
2. Open a Pull Request and run `terraform apply` in `<domain>-mgmt/terraform/`. The GCP project container is provisioned with billing and APIs enabled.

---

## 💻 Step 4: Workload Compute & Network (`<domain>-<workload>/terraform/`)

Inside the workload directory, initialize your Terraform module:

```hcl
# <domain>-<workload>/terraform/main.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "<domain>-dpi-ait-ac-th-tfstate"
    prefix = "<workload>"
  }
}

provider "google" {
  project = "<domain>-<workload>"
  region  = "asia-southeast1"
}
```

---

## 🛡️ Step 5: Standard VM Security, Access & Secrets Protocol

All Compute Engine instances across the DPI Center must adhere to the 3-pillar security and access invariant:

### Pillar 1: Zero SSH Keys on Disk (GCP OS Login + IAP)
* **Never bake SSH public keys** into `cloud-init`, instance metadata, or local files.
* **Enforce OS Login**: In `google_compute_instance`, always set `metadata = { "enable-oslogin" = "TRUE" }`.
* **Zero-Trust Ingress**: Allow SSH (port 22) **strictly** from Google Cloud Identity-Aware Proxy (`35.235.240.0/20`).
* **Operator Access**: Team members authenticate using their individual Google accounts (`@ait.asia`) with personal 2FA via:
  ```bash
  gcloud compute ssh <instance-name> --tunnel-through-iap
  ```
  GCP automatically generates short-lived, ephemeral SSH certificates tied to verified IAM identities.

### Pillar 2: Zero Plaintext Secrets in Cloud-Init (Secret Manager + IAM)
* **Never embed plain-text secrets**, API tokens, OAuth credentials, or private keys inside `cloud-init` user-data (which is stored in plaintext metadata and inspectable via the GCP console or instance metadata server).
* **Service Account Binding**: Attach a dedicated service account (`<domain>-<workload>-sa`) to the VM.
* **Granular Least Privilege**: Grant the service account read access to specific secrets in `<domain>-mgmt` using `google_secret_manager_secret_iam_member`:
  ```hcl
  resource "google_secret_manager_secret_iam_member" "oauth_secret_access" {
    project   = "<domain>-mgmt"
    secret_id = "my-secret-id"
    role      = "roles/secretmanager.secretAccessor"
    member    = "serviceAccount:${google_service_account.vm_sa.email}"
  }
  ```
* **Runtime Hydration**: The VM securely fetches secrets at runtime or deployment using `gcloud secrets versions access latest ...` into root-owned, mode `0600` files.

### Pillar 3: Decoupled Compute vs. Application Lifecycle
* **Host Infrastructure**: `cloud-init` strictly provisions the OS environment, Docker CE, directories, and systemd units.
* **Container Workloads**: Application stacks (e.g. `docker-compose.yml`) are deployed and updated independently without recreating the VM.
* **Zero VM Recreation**: Bumping Docker images or rotating secrets never destroys or rebuilds the VM.

---

## 🌐 Step 6: Decoupled DNS Record Ownership

To prevent `<domain>-mgmt` from becoming a bottleneck, **workload projects manage their own DNS records directly in their own Terraform code**:

```hcl
# Inside <domain>-<workload>/terraform/dns.tf

# 1. Allocate Workload Static IP
resource "google_compute_address" "service_ip" {
  name   = "service-static-ip"
  region = "asia-southeast1"
}

# 2. Directly create and bind the A record in the domain's central zone
resource "google_dns_record_set" "service" {
  project      = "<domain>-mgmt"                  # Anchor project where zone resides
  managed_zone = "dpi-<domain>"                   # Central managed zone name
  name         = "service.<domain>.dpi.ait.ac.th."# FQDN
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.service_ip.address]
}
```

*Benefits*:
- When a VM or static IP is recreated, its DNS record updates automatically.
- Developers do not need to modify `<domain>-mgmt` code to point DNS to their new IP.

---

## 🔒 Step 7: NetBird Mesh VPN Enrollment

All downstream nodes join the private NetBird WireGuard overlay mesh (`100.64.0.0/16`):

1. Obtain a **Setup Key** from NetBird Admin Console ([`https://netbird.dpi.ait.ac.th`](https://netbird.dpi.ait.ac.th) or [`https://netbird.base.dpi.ait.ac.th`](https://netbird.base.dpi.ait.ac.th)).
2. Run on the VM (or add to `cloud-init` / user-data startup script):
   ```bash
   curl -fsSL https://pkgs.netbird.io/install.sh | sh
   netbird up --management-url https://netbird.dpi.ait.ac.th:443 --setup-key <SETUP_KEY>
   ```
3. Verify connection:
   ```bash
   netbird status
   # Output: Connected, IP: 100.64.X.Y
   ```
4. Now the node can securely communicate with Rancher (`base-kube-ops`) and central telemetry without public IP exposure.
