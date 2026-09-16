# `base-kube-ops` — K8s Cluster Management Control Plane (Rancher)

**GCP Project**: `base-kube-ops`
**Purpose**: Centralized multi-cluster Kubernetes management (Rancher Community) for the DPI Center clusters.
**Tracking**: [Issue #5](https://github.com/mosip-asia/dpi-base/issues/5) (Phase 3)

---

## 🏗 Architecture
* **Kubernetes Manager**: Rancher Community Server (Apache 2.0, $0 license fee) on a single-node K3s, for MOSIP platform compatibility.
* **Compute Host**: `base-kube-ops-vm`, `e2-standard-4` (4 vCPU, 16 GB RAM + 2 GB swap), 50 GB `pd-balanced`, Ubuntu 24.04 LTS, Shielded VM, in `asia-southeast1-b`.
* **Provisioning Method**: Terraform for the infrastructure; `cloud-init` for the OS layer only; `rancher/deploy.sh`, pushed over IAP, installs and upgrades K3s, Helm, cert-manager and Rancher without recreating the VM.
* **Operating Mode**: **On-Demand / Scheduled**. A GCP instance schedule starts the VM at 08:30 and stops it at 18:30 `Asia/Bangkok`, Monday to Friday. Downstream K3s clusters keep running while Rancher is off; this was proven on the predecessor project on 2026-09-14 (17 hours off, the cluster agent reconnected by itself).
* **Public Static IP**: `base-kube-ops-static-ip`. Ports 80 (Let's Encrypt HTTP-01) and 443 (UI, API, downstream agents) are public; 22 only through IAP; 6443 closed, because downstream agents only dial out to 443.
* **DNS FQDNs**:
  * **Server URL**: `rancher.dpi.ait.ac.th`, a CNAME in parent zone `dpi-center` (`ait-brainlab-mgmt`), created by hand like `netbird.dpi.ait.ac.th`. Downstream clusters store this name.
  * **Base Infrastructure**: `rancher.base.dpi.ait.ac.th`, an A record in `base-mgmt` zone `dpi-base`, owned by `terraform/dns.tf`.
* **Observability** (VictoriaMetrics, Grafana Loki, Grafana OSS): proposed in issue #5 to move to its own issue, where its placement is decided.
* **NetBird Mesh**: joining the `100.64.0.0/16` overlay (STATUS task 3.4) follows once the setup-key handling is agreed in issue #5.

---

## 📁 Directory Structure
```text
base-kube-ops/
├── README.md              # Architecture and operating runbook (this file)
├── remote-deploy.sh       # Uploads rancher/ over IAP and runs deploy.sh on the VM
├── ssh.sh                 # IAP SSH connector as 'ubuntu' (interactive shell or remote command)
├── rancher/               # Application stack, synced flat to /opt/rancher on the VM
│   ├── deploy.sh          # VM-side deployer: K3s, Helm, cert-manager, Rancher (idempotent)
│   ├── .env.template      # Single source of truth: names, version pins, Rancher settings (no secrets)
│   └── rancher-values.yaml # Static Rancher chart values (Traefik ingress, Let's Encrypt)
├── scripts/
│   ├── check_record.sh    # DNS-over-HTTPS check of the A record and the canonical CNAME
│   ├── check_rancher_health.sh # /healthz and certificate issuer, from the laptop
│   └── precommit-check.sh # Blocks secrets, state, billing IDs and CRLF before a commit
└── terraform/             # Infrastructure (state: gs://base-dpi-ait-ac-th-tfstate, prefix base-kube-ops)
    ├── main.tf            # Terraform backend & provider (google 5.45.2, exact pin)
    ├── variables.tf       # Parameter declarations with public defaults
    ├── network.tf         # Static IP (prevent_destroy) & firewall rules
    ├── compute.tf         # Service account, operator IAM, VM and cloud-init rendering
    ├── schedule.tf        # Instance schedule & the Compute service agent grant it needs
    ├── dns.tf             # Decoupled DNS record in base-mgmt
    ├── outputs.tf         # Static IP, FQDNs, CNAME request, VM outputs
    └── templates/
        └── cloud-init.yaml.tftpl # OS layer only: packages, time zone, swap, /opt/rancher
```
The project container itself (billing, APIs, deletion lien) is `base-mgmt/terraform/prj-base-kube-ops.tf`.

---

## 🚀 Deployment & Operations

Run everything from a Git Bash terminal on Windows (PowerShell's `bash` is WSL, which has no gcloud login).

### Step 0: Workstation & Access
```bash
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project base-mgmt
./scripts/check_env.sh
```
Operators whose Google accounts live outside the `dpi.ait.ac.th` organization (e.g. `@ait.asia`) need `roles/compute.osLoginExternalUser` on the organization before IAP SSH works. It exists only at organization level; both admins received it on 2026-09-13.

### Step 1: Project Envelope (`base-mgmt`)
`base-mgmt/terraform/prj-base-kube-ops.tf` creates the project in folder `base`, links billing from Secret Manager, enables Compute Engine and adds a deletion lien. It is applied in `base-mgmt/terraform` by an operator who can read the `billing-account-id` secret. The plan must show only the new project, its API and its lien, and **0 to destroy**.

### Step 2: Provision Infrastructure (Terraform)
Provisions the static IP, firewall rules, service account, VM, instance schedule and the `rancher.base.dpi.ait.ac.th` record. Not between 17:45 and 18:45 Bangkok time, when the schedule stops the VM.
```bash
terraform -chdir=base-kube-ops/terraform init
terraform -chdir=base-kube-ops/terraform plan -out=plan.tfplan
terraform -chdir=base-kube-ops/terraform apply plan.tfplan
./base-kube-ops/scripts/check_record.sh            # rancher.base.dpi.ait.ac.th -> static IP
terraform -chdir=base-kube-ops/terraform output cname_request
```

### Step 3: Canonical Name (manual, parent zone)
Create the CNAME printed by `cname_request` in zone `dpi-center` of `ait-brainlab-mgmt`, then:
```bash
./base-kube-ops/scripts/check_record.sh rancher.dpi.ait.ac.th
```

### Step 4: Deploy Rancher (Zero VM Recreation)
```bash
./base-kube-ops/remote-deploy.sh
./base-kube-ops/scripts/check_rancher_health.sh
```
The deployer installs K3s and cert-manager first. If `rancher.dpi.ait.ac.th` does not resolve to the VM yet, it stops with exit code 3 and prints the CNAME to request; re-run it once the name resolves.

### Step 5: First Login
Rancher generates its bootstrap password. Read it once in your own terminal and paste it only into the Rancher login page:
```bash
./base-kube-ops/ssh.sh
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
```
Set the admin password (12+ characters) and confirm the server URL `https://rancher.dpi.ait.ac.th`.

### Step 6: Direct VM Access via IAP (`ssh.sh`)
```bash
./base-kube-ops/ssh.sh                                   # interactive shell as ubuntu
./base-kube-ops/ssh.sh "kubectl -n cattle-system get pods"
./base-kube-ops/ssh.sh "helm list -A"
```

---

## ⬆️ Upgrades

Versions are pinned in `rancher/.env.template` (`K3S_VERSION`, `HELM_VERSION`, `CERT_MANAGER_VERSION`, `RANCHER_CHART_VERSION`). Terraform state is not involved: an upgrade is a pin change, a commit and `./base-kube-ops/remote-deploy.sh`.

**Rancher** upgrades are one-way. Rancher supports only going from the latest patch of the running minor to the latest patch of the next minor, and rolling back means restoring a backup taken before the upgrade. Before bumping `RANCHER_CHART_VERSION`:
1. Read the release notes and the support matrix; the K3s version must be supported by the target Rancher version.
2. Snapshot the boot disk (the disk carries K3s's datastore, Rancher and the certificates):
   ```bash
   gcloud compute disks snapshot base-kube-ops-vm --zone asia-southeast1-b --project base-kube-ops \
     --snapshot-names base-kube-ops-before-rancher-<new-version>
   ```
3. Bump the pin, commit, and run `./base-kube-ops/remote-deploy.sh --confirm-rancher-upgrade`. The deployer refuses downgrades, skipped minors, and any version change without that flag.

**K3s** is upgraded only through `K3S_VERSION` and the deployer. Do not also upgrade the local cluster from the Rancher UI, or the next deploy would undo it.

---

## 🧯 Stock-Out Recovery (`ZONE_RESOURCE_POOL_EXHAUSTED`)

A scheduled start does not retry. If a zone runs out of capacity for the machine type, the VM simply stays off (seen for e2 in `asia-southeast1-a` on 2026-09-13/14). Check after 08:45 with `./base-kube-ops/scripts/check_rancher_health.sh`, then:
```bash
gcloud compute instances start base-kube-ops-vm --zone asia-southeast1-b --project base-kube-ops   # retry a few times
# Still no capacity: switch the stopped VM to another 4-vCPU family; the disk and Rancher's data are untouched
gcloud compute instances set-machine-type base-kube-ops-vm --zone asia-southeast1-b --project base-kube-ops --machine-type n2-standard-4
gcloud compute instances start base-kube-ops-vm --zone asia-southeast1-b --project base-kube-ops
```
Afterwards `terraform plan` shows the machine type as drift: set it back while the VM is stopped once capacity returns, or change `machine_type` in `terraform/variables.tf`.

## ⏰ Changing the Schedule

Instance schedule fields are immutable, and a policy cannot be replaced while attached. Detach first, then change the cron variables and apply:
```bash
gcloud compute instances remove-resource-policies base-kube-ops-vm --zone asia-southeast1-b --project base-kube-ops \
  --resource-policies base-kube-ops-schedule
terraform -chdir=base-kube-ops/terraform apply
```

---

## 🔑 Authentication & Single Sign-On (SSO)

Rancher does **not** maintain an isolated user directory. It connects to the central **Google OAuth2 / OIDC** client provisioned in `base-mgmt`:

* **Shared Credentials**: `google-oauth-client-id` and `google-oauth-client-secret` in `base-mgmt` Secret Manager.
* **Provider**: Generic OIDC against `https://accounts.google.com`. Rancher's built-in Google provider expects a Google Workspace admin and a service-account key, which the Cloud Identity Free organization does not use.
* **Redirect URIs**: `https://rancher.dpi.ait.ac.th/verify-auth` (server URL) and `https://rancher.base.dpi.ait.ac.th/verify-auth`.
* **Accepted Domains**: `@dpi.ait.ac.th`, `@ait.asia`, `@ait.ac.th`, and `@gmail.com` (enabled by the **External** OAuth consent screen).
* **Kubernetes RBAC Access Mode**: **"Restricted"**. Anyone with an accepted Google account can authenticate, but **they are granted zero permissions until an administrator explicitly binds their account to specific clusters or projects**.

See [`base-mgmt/oauth_setup.md`](../base-mgmt/oauth_setup.md) for the client configuration.

---

## 🔄 Alternatives to Rancher (Migration Guardrail)

Rancher is kept for MOSIP platform automation and API compatibility. Because downstream K3s clusters run fully autonomously when Rancher is off (proven 2026-09-14), the management layer can be replaced without touching workloads. Lighter options, evaluated for future decoupling:

| Alternative | What it would cover | What it lacks compared to Rancher |
|---|---|---|
| **Headlamp** (OSS) | Web UI per cluster or multi-cluster via kubeconfigs; plugins; OIDC login | Cluster import/registration, central RBAC across clusters, app catalog |
| **Argo CD** | GitOps delivery of workloads to many clusters, with SSO and RBAC | Interactive cluster administration, cluster lifecycle |
| **Lens / k9s** | Operator desktop or terminal tools on individual kubeconfigs | Any shared, central control plane or SSO |
