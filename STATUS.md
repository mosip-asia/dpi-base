# DPI Center Base (`dpi-base`) — Current Situation & Status

**Last Updated**: 2026-09-13  
**Active Git Branch**: `feat/issue-3-foundation`  
**Linked Pull Request**: [PR #6: feat: initialize foundation management plane (dpi-mgmt)](https://github.com/mosip-asia/dpi-base/pull/6)  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  

---

## 🚦 Executive Summary

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DPI CENTER ROADMAP OVERVIEW                           │
└─────────────────────────────────────────────────────────────────────────────────┘
  Phase 0: Cloud Organization & Identity Foundation      [🟢 COMPLETED]
  Phase 1: Foundation Management Plane (dpi-mgmt)        [🟡 READY TO APPLY]
  Phase 2: Network Fabric Tier (dpi-vpn / NetBird)       [🔴 PLANNED]
  Phase 3: Multi-Cluster Control Plane (dpi-kube-ops)    [🔴 PLANNED]
  Phase 4: Sovereign Workload Initiatives (MOSIP, DLMS)  [🔴 PLANNED]
```

---

## 🏛️ Phase & Milestone Tracking

### Phase 0: Cloud Organization & Identity (Closed / Verified Live)
* **Lead**: Operating Admins (`akraradet@ait.asia`, `nuttasit@ait.asia`)
* **Tracking Issue**: [Issue #2](https://github.com/mosip-asia/dpi-base/issues/2) (Closed)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `0.1` | Sign up Google Cloud Identity Free | `dpi.ait.ac.th` | 🟢 Verified | Org ID: `350922776586` ($0/mo, 50 free seats) |
| `0.2` | Verify Domain Ownership | Google Admin Console | 🟢 Verified | Verified via TXT record; SuperAdmin: `admin@dpi.ait.ac.th` |
| `0.3` | Unlock Org Policy for Institutional Sharing | `constraints/iam.allowedPolicyMemberDomains` | 🟢 Verified | Allowed all domains so `@ait.asia` accounts can hold admin roles |
| `0.4` | Assign Organization Administrators | IAM Policy at Org root | 🟢 Verified | `akraradet@ait.asia`, `nuttasit@ait.asia` granted Org Admin & Billing Admin |

---

### Phase 1: Foundation Management Plane (`dpi-mgmt`) (Active / In Progress)
* **Lead**: `@akraradets`
* **Tracking Issue**: [Issue #3](https://github.com/mosip-asia/dpi-base/issues/3)
* **Active Branch**: `feat/issue-3-foundation`

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `1.1` | Create management project `dpi-mgmt` | `dpi-mgmt` (`189731855526`) | 🟢 Verified | Linked to Core Billing Account `0199A6-XXXXXX-XXXXXX` |
| `1.2` | Create root GCP Folder `dpi-base` | GCP Resource Manager | 🟢 Verified | Mirrors repository 1:1; consolidates base billing & IAM |
| `1.3` | Enable Core GCP APIs | Project `dpi-mgmt` | 🟢 Verified | `compute`, `dns`, `iam`, `secretmanager`, `storage` enabled |
| `1.4` | GCS Remote State Bucket | `gs://dpi-mgmt-tfstate` | 🟢 Verified | Singapore (`asia-southeast1`), Object Versioning ON |
| `1.5` | Flatten Terraform Code Layout | `dpi-mgmt/terraform/` | 🟢 Verified | Code moved directly to `dpi-mgmt/terraform/` (15 resources planned) |
| `1.6` | Pre-flight Environment Validator | `scripts/check_env.sh` | 🟢 Verified | Validates syntax, placeholders, and live GCP auth |
| `1.7` | Domain Seed Bootstrap Script | `scripts/bootstrap_domain.sh`| 🟢 Verified | Supports `--plan`, idempotent apply, auto-detects paths |
| `1.8` | Root `.env` & `.env.example` Workflow | Root `.env.example` | 🟢 Verified | Sanitized, gitignored, public billing privacy enforced |
| `1.9` | Deploy GitOps Foundation via Terraform | Project `dpi-mgmt` | 🟡 Ready | `terraform plan` clean (15 to add: DNS zone, lien, CI/CD SA) |
| `1.10`| Authoritative Parent DNS Delegation Handshake | `ait-brainlab-mgmt` | 🔴 Pending | Awaiting `terraform apply` output for `base.dpi.ait.ac.th.` NS |

---

### Phase 2: Network Fabric Tier (`dpi-vpn`) (Planned)
* **Lead**: `@akraradets`
* **Tracking Issue**: [Issue #4](https://github.com/mosip-asia/dpi-base/issues/4)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `2.1` | Create Project `dpi-vpn` | GCP Resource Manager | 🔴 Planned | Inside `dpi-base` folder, linked to base billing |
| `2.2` | Provision NetBird Controller VM | Compute Engine (`e2-small`) | 🔴 Planned | ~$14/mo, 24/7 online, static external IP |
| `2.3` | Configure NetBird Docker Services | `dpi-vpn/docker/` | 🔴 Planned | NetBird management, signal, and STUN/TURN (coturn) |
| `2.4` | Configure NetBird OAuth SSO | Google OAuth2 Web Client | 🔴 Planned | Integrated with Google Identity with admin-approval workflow |
| `2.5` | DNS Records in `ait-brainlab-mgmt` | `netbird.dpi.ait.ac.th`, `signal...` | 🔴 Planned | Pointing to static IP in `dpi-vpn` |

---

### Phase 3: Multi-Cluster Control Plane (`dpi-kube-ops`) (Planned)
* **Lead**: Nuttasit (`@nuttasit`)
* **Tracking Issue**: [Issue #5](https://github.com/mosip-asia/dpi-base/issues/5)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `3.1` | Create Project `dpi-kube-ops` | GCP Resource Manager | 🔴 Planned | Inside `dpi-base` folder, linked to base billing |
| `3.2` | Provision Rancher Instance | Compute Engine (`e2-standard-4`) | 🔴 Planned | Configured with GCP Instance Schedule (saving ~65-75% compute) |
| `3.3` | Deploy Central Observability | VictoriaMetrics & Grafana Loki | 🔴 Planned | Ultra-low overhead metrics and chunked log ingestion |
| `3.4` | Connect to NetBird VPN Mesh | NetBird Client Setup Key | 🔴 Planned | Joins 100.64.0.0/16 overlay mesh for secure cluster communication |

---

### Phase 4: Sovereign Workload Initiatives (Future Roadmap)
* **Tracking Epic**: [Epic #1: Multi-Cluster Control & Observability Plane](https://github.com/mosip-asia/dpi-base/issues/1)

| Task ID | Initiative | Scope & Description | Status |
| :---: | :--- | :--- | :---: |
| `4.1` | **MOSIP Asia** | Deploy downstream K3s cluster for digital identity demonstration | 🔴 Planned |
| `4.2` | **DLMS** | Driver Licensing Management System demonstrator deployment | 🔴 Planned |
| `4.3` | **AI & Research Sandboxes** | Autonomous testbed projects with delegated subdomains | 🔴 Planned |

---

## 📋 Live Inventory of Assets

| Resource Type | Resource Identifier | Location / Project | Status |
| :--- | :--- | :--- | :---: |
| **GCP Organization** | `dpi.ait.ac.th` (`350922776586`) | Root | Active |
| **Customer ID** | `C0164ixfv` | Google Workspace / Identity | Active |
| **Core Billing Account** | `0199A6-XXXXXX-XXXXXX` | Google Cloud Billing | Active |
| **Root Management Folder** | `dpi-base` (`folders/755694218880`) | Org Root | Active |
| **Foundation Project** | `dpi-mgmt` (`189731855526`) | Folder `dpi-base` | Active |
| **State Storage Bucket** | `gs://dpi-mgmt-tfstate` | `dpi-mgmt` (`asia-southeast1`) | Active (Versioning ON) |
| **Parent Authoritative DNS** | Zone `dpi-center` (Shard A) | `ait-brainlab-mgmt` | Active (Delegated from `ait.ac.th`) |
| **Foundation DNS Subzone** | `base.dpi.ait.ac.th.` | `dpi-mgmt` | Defined in Terraform (Ready to apply) |

---

## 🎯 Immediate Next Actions

1. **Apply Foundation Terraform**:
   ```bash
   cd dpi-mgmt/terraform
   terraform init
   terraform apply
   ```
2. **Perform Parent DNS Delegation**:
   - Capture nameservers from `terraform output name_servers`.
   - Add the 4 nameservers as an `NS` record for `base.dpi.ait.ac.th.` in project `ait-brainlab-mgmt` (Zone: `dpi-center`).
3. **Merge Pull Request #6**:
   - Merge `feat/issue-3-foundation` into `main` once `terraform apply` and DNS validation pass.
4. **Kick off Phase 2 (`dpi-vpn`)**:
   - Create branch `feat/issue-4-vpn` and begin NetBird mesh VPN deployment.
