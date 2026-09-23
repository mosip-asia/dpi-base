# DPI Center Base (`dpi-base`) — Current Situation & Status

**Last Updated**: 2026-09-23  
**Active Git Branch**: `main`  
**Target Organization**: `dpi.ait.ac.th` (Org ID: `350922776586`)  

---

## 🚦 Executive Summary

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DPI CENTER ROADMAP OVERVIEW                           │
└─────────────────────────────────────────────────────────────────────────────────┘
  Phase 0: Cloud Organization & Identity Foundation      [🟢 COMPLETED]
  Phase 1: Foundation Management Plane (base-mgmt)       [🟢 COMPLETED]
  Phase 2: Network Fabric Tier (base-vpn / NetBird)      [🟢 COMPLETED]
  Phase 3: Multi-Cluster Control Plane (base-kube-ops)   [🟢 COMPLETED]
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
| `1.7` | Domain Scaffolding & Seed Bootstrap | `scripts/scaffold_domain.sh`, `scripts/bootstrap_domain.sh` | 🟢 Verified | Standalone offline workspace generator & cloud seed bootstrapper; auto-scaffolds `<domain>-mgmt/` from `template-mgmt/` |
| `1.8` | Root `.env` & `.env.example` Workflow | Root `.env.example` | 🟢 Verified | Sanitized, gitignored, public billing privacy enforced |
| `1.9` | Deploy GitOps Foundation via Terraform | Project `base-mgmt` | 🟢 Verified | 13 resources deployed (DNS zone, lien, Secret Manager, Folder IAM) |
| `1.10`| Authoritative Parent DNS Delegation Handshake | `ait-brainlab-mgmt` | 🟢 Verified | Shard E NS records delegated; resolving worldwide |

---

### Phase 2: Network Fabric Tier (`base-vpn`) (Closed / Verified Live)
* **Lead**: `@akraradets`
* **Tracking Issue**: [Issue #4](https://github.com/mosip-asia/dpi-base/issues/4)
* **Active Branch**: `feat/issue-4-vpn`
* **Pull Request**: [PR #7](https://github.com/mosip-asia/dpi-base/pull/7)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `2.1` | Create Project `base-vpn` & Link Billing | `base-vpn` (`945976338321`) | 🟢 Verified | Created via `prj-base-vpn.tf`, billing linked from Secret Manager, lien active |
| `2.2` | Terraform Infrastructure & Cloud-Init | `base-vpn/terraform/` | 🟢 Verified | VM (`e2-micro`), regional static IP (`35.240.138.109`), zero-trust firewalls, 2GB swap |
| `2.3` | Decoupled DNS Record | `base-mgmt` Cloud DNS zone | 🟢 Verified | `netbird.base.dpi.ait.ac.th` -> `35.240.138.109` active & resolving worldwide |
| `2.4` | NetBird Docker Stack & Traefik v3 Proxy | `base-vpn/netbird/` | 🟢 Verified | Traefik v3, NetBird stack, and Dependabot major-only filter |
| `2.5` | Zero-Downtime Stack Deployer & Hot Backup | `base-vpn/remote-deploy.sh` | 🟢 Verified | Live over IAP; all 5 containers Up; GCS hot snapshots verified |
| `2.6` | NetBird OAuth SSO & Admin Approval | Google OAuth2 Web Client | 🟢 Verified Live | Secret Manager keys fetched by VM SA; Google OIDC auth enabled |
| `2.7` | Canonical Production CNAME Pointer | Parent Zone `dpi-center` (`ait-brainlab-mgmt`) | 🟢 Verified Live | `netbird.dpi.ait.ac.th` CNAME $\rightarrow$ `netbird.base.dpi.ait.ac.th`; Let's Encrypt TLS active |
| `2.8` | Systemd Service Lifecycle & Condition Guard | `dpi-vpn.service` | 🟢 Verified Live | [Issue #12](https://github.com/mosip-asia/dpi-base/issues/12) / [PR #13](https://github.com/mosip-asia/dpi-base/pull/13): `ConditionPathExists` & active tracking verified |

---

### Phase 3: Multi-Cluster Control Plane (`base-kube-ops`) (Closed / Verified Live)
* **Lead**: Nuttasit (`@BossNP` / `@nuttasit`)
* **Tracking Issue**: [Issue #5](https://github.com/mosip-asia/dpi-base/issues/5) (Closed via [PR #15](https://github.com/mosip-asia/dpi-base/pull/15))
* **Pull Request**: [PR #15](https://github.com/mosip-asia/dpi-base/pull/15) (Merged)

| Task ID | Task Description | Target Resource | Status | Notes / Output |
| :---: | :--- | :--- | :---: | :--- |
| `3.1` | Create Project `base-kube-ops` | GCP Resource Manager | 🟢 Verified | Envelope `base-mgmt/terraform/prj-base-kube-ops.tf` applied 2026-09-17: project in folder `base`, billing from Secret Manager, Compute API, deletion lien. Budget `base-platform-monthly` (THB 3,500, 50/80/100 % alerts) on "DPI Center - Base Platform" |
| `3.2` | Provision Rancher Instance | Compute Engine (`e2-standard-4`) | 🟢 Verified Live | `base-kube-ops/terraform/` applied 2026-09-17 (static IP `34.21.247.4`, firewall, VM, instance schedule 08:30–18:30, `rancher.base.dpi.ait.ac.th`); `rancher/deploy.sh` installed K3s v1.36.3+k3s1, cert-manager v1.21.1 and Rancher 2.15.1 on `https://rancher.dpi.ait.ac.th` (Let's Encrypt, `agentTLSMode: system-store`); first login done; scheduled stop and start observed |
| `3.3` | Deploy Central Observability | VictoriaMetrics & Grafana Loki | ⏸️ Proposed Split | Moved to follow-up issue for observability placement (scheduled `base-kube-ops` vs 24/7 `base-vpn`) |
| `3.4` | Connect to NetBird VPN Mesh | NetBird Client Setup Key | 🟢 Verified Live | Joined 2026-09-18 with a one-off setup key (`k3s-control-enroll`, group `kube-ops`, ephemeral off) typed once over IAP (`base-kube-ops/netbird-join.sh`); client 0.78.1 pinned by `deploy.sh`; `base-kube-ops-vm` = `100.70.173.242` on the mesh (network `100.70.0.0/16`), Management and Signal connected |

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
| **NetBird Canonical Endpoint** | `netbird.dpi.ait.ac.th.` | `ait-brainlab-mgmt` (Zone `dpi-center`) | 🟢 Active CNAME with Let's Encrypt TLS |
| **NetBird Host VM** | `base-vpn-vm` (`e2-micro`, ~$7.30/mo) | `base-vpn` (`asia-southeast1-b`) | 🟢 Running (2GB Swap active) |
| **TLS Certificates** | Let's Encrypt (`netbird.base.*`, `netbird.dpi.*`) | Traefik v3 (`/opt/netbird/traefik/acme.json`) | 🟢 Valid through Dec 2026 |
| **Docker Compose Stack** | 5 containers (Traefik, Dashboard, Signal, Mgmt, Relay) | `/opt/netbird` (`base-vpn-vm`) | 🟢 5/5 Up & Healthy |
| **Automated State Backup** | `gs://base-dpi-ait-ac-th-tfstate/backups/netbird/` | GCS (`store.db`, `acme.json`) | 🟢 Active (6-hourly cron) |
| **Control Plane Project** | `base-kube-ops` (`365194416805`) | Folder `base` | 🟢 Active (deletion lien) |
| **Rancher Static IP** | `34.21.247.4` | `base-kube-ops` (`asia-southeast1`) | 🟢 Allocated & Attached |
| **Rancher DNS Endpoint** | `rancher.base.dpi.ait.ac.th.` | `base-mgmt` (Zone `dpi-base`) | 🟢 Resolving to `34.21.247.4`; redirects to canonical name |
| **Rancher Canonical Endpoint** | `rancher.dpi.ait.ac.th.` | `ait-brainlab-mgmt` (Zone `dpi-center`) | 🟢 Active CNAME with Let's Encrypt TLS |
| **Rancher Host VM** | `base-kube-ops-vm` (`e2-standard-4`, 08:30–18:30 Mon–Fri, ~$48/mo) | `base-kube-ops` (`asia-southeast1-b`) | 🟢 Running on schedule (2GB Swap active) |
| **Rancher Stack** | K3s `v1.36.3+k3s1`, cert-manager `v1.21.1`, Rancher `2.15.1` | `/opt/rancher` (`base-kube-ops-vm`) | 🟢 Healthy; Google SSO (Generic OIDC) |
| **Rancher NetBird Peer** | `base-kube-ops-vm` = `100.70.173.242` | NetBird mesh (`100.70.0.0/16`) | 🟢 Connected |
| **Base Platform Budget** | `base-platform-monthly` (THB 3,500; alerts 50/80/100 %) | Billing "DPI Center - Base Platform" | 🟢 Active |
| **Domain Management Template** | `template-mgmt/` | Repository Root | 🟢 Available (`scripts/scaffold_domain.sh`) |

---

## 🎯 Immediate Next Actions

1. **Platform Operations & Follow-ups**:
   - **OAuth Consent Screen**: Publish the OAuth consent screen in Google Cloud Console so external `@ait.ac.th` and `@gmail.com` accounts can sign into NetBird and Rancher without adding each test user.
   - **Observability Plane**: Open dedicated issue for VictoriaMetrics + Grafana Loki placement (scheduled `base-kube-ops` vs 24/7 `base-vpn`).
   - **Downstream NetBird Rehearsal**: Spin up test downstream node over NetBird mesh ([Issue #14](https://github.com/mosip-asia/dpi-base/issues/14)).
2. **Sovereign Domain Onboarding (First Demonstrator)**:
   - Run `./scripts/scaffold_domain.sh ait-vc` and `./scripts/bootstrap_domain.sh` to provision the **AIT Verifiable Credentials (`ait-vc`)** landing zone under Billing Account `DPI Center - AIT Verifiable Credentials`.
3. **Review & Prioritize Proposals (Unconfirmed)**:
   - [Issue #10](https://github.com/mosip-asia/dpi-base/issues/10): `[GitOps] Configure Terraform Service Account (base-mgmt-terraform) & Workload Identity Federation for base Domain` (`status: unconfirmed`)
   - [Issue #11](https://github.com/mosip-asia/dpi-base/issues/11): `[Platform] Design and Publish "domain-template" Repository for Sovereign Domain Onboarding` (`status: in progress / template-mgmt delivered`)
