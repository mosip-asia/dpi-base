# DPI Center Base (`dpi-base`) — Current Situation & Status

**Last Updated**: 2026-09-13  
**Active Git Branch**: `feat/issue-4-vpn`  
**Linked Pull Request**: [PR #7: feat(vpn): [Phase 2] Deploy base-vpn infrastructure & NetBird Mesh VPN (Draft)](https://github.com/mosip-asia/dpi-base/pull/7)  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  

---

## 🚦 Executive Summary

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DPI CENTER ROADMAP OVERVIEW                           │
└─────────────────────────────────────────────────────────────────────────────────┘
  Phase 0: Cloud Organization & Identity Foundation      [🟢 COMPLETED]
  Phase 1: Foundation Management Plane (base-mgmt)       [🟢 COMPLETED]
  Phase 2: Network Fabric Tier (base-vpn / NetBird)      [🟡 IN PROGRESS]
  Phase 3: Multi-Cluster Control Plane (base-kube-ops)   [🔴 PLANNED]
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

### Phase 1: Foundation Management Plane (`base-mgmt`) (Closed / Verified Live)
* **Lead**: `@akraradets`
* **Tracking Issue**: [Issue #3](https://github.com/mosip-asia/dpi-base/issues/3)
* **Active Branch**: `feat/issue-3-foundation`

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `1.1` | Create management project `base-mgmt` | `base-mgmt` (`892879827967`) | 🟢 Verified | Linked to Core Billing Account `0199A6-XXXXXX-XXXXXX` |
| `1.2` | Create root GCP Folder `base` | GCP Resource Manager | 🟢 Verified | Folder `folders/740224775327`; consolidates base billing & IAM |
| `1.3` | Enable Core GCP APIs | Project `base-mgmt` | 🟢 Verified | `compute`, `dns`, `iam`, `secretmanager`, `storage` enabled |
| `1.4` | GCS Remote State Bucket | `gs://base-dpi-ait-ac-th-tfstate` | 🟢 Verified | Singapore (`asia-southeast1`), Object Versioning ON |
| `1.5` | Flatten Terraform Code Layout | `base-mgmt/terraform/` | 🟢 Verified | Code moved directly to `base-mgmt/terraform/` (13 resources applied) |
| `1.6` | Pre-flight Environment Validator | `scripts/check_env.sh` | 🟢 Verified | Validates syntax, placeholders, and live GCP auth |
| `1.7` | Domain Seed Bootstrap Script | `scripts/bootstrap_domain.sh`| 🟢 Verified | Supports `--plan`, idempotent apply, auto-detects paths |
| `1.8` | Root `.env` & `.env.example` Workflow | Root `.env.example` | 🟢 Verified | Sanitized, gitignored, public billing privacy enforced |
| `1.9` | Deploy GitOps Foundation via Terraform | Project `base-mgmt` | 🟢 Verified | 13 resources deployed (DNS zone, lien, Secret Manager, Folder IAM) |
| `1.10`| Authoritative Parent DNS Delegation Handshake | `ait-brainlab-mgmt` | 🟢 Verified | Shard E NS records delegated; resolving worldwide |

---

### Phase 2: Network Fabric Tier (`base-vpn`) (In Progress)
* **Lead**: `@akraradets`
* **Tracking Issue**: [Issue #4](https://github.com/mosip-asia/dpi-base/issues/4)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :--- | :--- |
| `2.1` | Create Project `base-vpn` & Link Billing | `base-vpn` (`945976338321`) | 🟢 Verified | Created via `prj-base-vpn.tf`, billing linked from Secret Manager, lien active |
| `2.2` | Terraform Infrastructure & Cloud-Init | `base-vpn/terraform/` | 🟢 Verified | VM (`e2-micro`), regional static IP (`35.240.138.109`), zero-trust firewalls, 2GB swap |
| `2.3` | Decoupled DNS Record | `base-mgmt` Cloud DNS zone | 🟢 Verified | `netbird.base.dpi.ait.ac.th` -> `35.240.138.109` active & resolving worldwide |
| `2.4` | NetBird Docker Stack & Traefik v3 Proxy | `base-vpn/docker/` | 🟢 Verified | Traefik v3, NetBird stack, and Dependabot major-only filter |
| `2.5` | Zero-Downtime Stack Deployer | `base-vpn/remote-deploy.sh` | 🟡 Ready to Deploy | Push deploy over IAP tunnel, auto-renders `.env` & `management.json`, runs `docker/deploy.sh` |
| `2.6` | NetBird OAuth SSO & Admin Approval | Google OAuth2 Web Client | 🟢 Credentials Seeded | Client ID & Secret seeded into Secret Manager in `base-mgmt` |
| `2.7` | Canonical Production CNAME Pointer | Parent Zone `dpi-center` (`ait-brainlab-mgmt`) | 🔴 Planned (TODO) | Point `netbird.dpi.ait.ac.th` CNAME $\rightarrow$ `netbird.base.dpi.ait.ac.th` (TTL 60s) |

---



### Phase 3: Multi-Cluster Control Plane (`base-kube-ops`) (Planned)
* **Lead**: Nuttasit (`@BossNP` / `@nuttasit`)
* **Tracking Issue**: [Issue #5](https://github.com/mosip-asia/dpi-base/issues/5)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `3.1` | Create Project `base-kube-ops` | GCP Resource Manager | 🔴 Planned | Inside `base` folder, linked to base billing |
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
| **Root Management Folder** | `base` (`folders/740224775327`) | Org Root | Active |
| **Foundation Project** | `base-mgmt` (`892879827967`) | Folder `base` | Active |
| **State Storage Bucket** | `gs://base-dpi-ait-ac-th-tfstate` | `base-mgmt` (`asia-southeast1`) | Active (Versioning ON) |
| **Parent Authoritative DNS** | Zone `dpi-center` (Shard A) | `ait-brainlab-mgmt` | Active (Delegated from `ait.ac.th`) |
| **Foundation DNS Subzone** | `base.dpi.ait.ac.th.` (Shard E) | `base-mgmt` | 🟢 Active & Resolving Worldwide |
| **Network Fabric Project** | `base-vpn` (`945976338321`) | Folder `base` | 🟢 Active |
| **VPN Regional Static IP** | `35.240.138.109` | `base-vpn` (`asia-southeast1`) | 🟢 Allocated & Attached |
| **NetBird DNS Endpoint** | `netbird.base.dpi.ait.ac.th.` | `base-mgmt` (Zone `dpi-base`) | 🟢 Resolving to `35.240.138.109` |
| **NetBird Host VM** | `base-vpn-vm` (`e2-micro`, ~$7.30/mo) | `base-vpn` (`asia-southeast1-b`) | 🟢 Running |

---

## 🎯 Immediate Next Actions

1. **Merge Pull Request #6**:
   - Merge `feat/issue-3-foundation` into `main` (Resolves Issue #3).
2. **Kick off Phase 2 (`base-vpn`)**:
   - Create branch `feat/issue-4-vpn` (linked to Issue #4).
   - Provision NetBird WireGuard mesh VPN tier on `e2-small` instance.
