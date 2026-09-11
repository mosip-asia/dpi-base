# Domain & DNS Architecture — DPI Center

## Overview
DPI Center operates under the public authoritative apex domain **`dpi.ait.ac.th`**, delegated by the Asian Institute of Technology (`ait.ac.th`) to Google Cloud DNS **Shard A** (`ns-cloud-a1.googledomains.com` – `ns-cloud-a4.googledomains.com`).

To avoid disrupting active parent delegation and prevent downtime across live services, the apex zone is permanently anchored in Google Cloud project **`ait-brainlab-mgmt`** (Managed Zone: `dpi-center`), while pointing cleanly to decoupled infrastructure across the **`dpi-base`** folder (`dpi-vpn`, `dpi-kube-ops`) and workload tiers.

---

## 🏛️ Cross-Project DNS Routing Architecture

```mermaid
flowchart TD
    PARENT["🏛️ AIT Central DNS (ait.ac.th)<br/>Hard-delegated to Shard A"] -->|NS Delegation| ANCHOR

    subgraph ANCHOR ["🌐 Project: ait-brainlab-mgmt (Zone: dpi-center)"]
        direction TB
        R_APEX["dpi.ait.ac.th (MX & SPF)"]
        R_VPN["netbird.dpi.ait.ac.th<br/>signal.dpi.ait.ac.th"]
        R_KUBE["rancher.dpi.ait.ac.th<br/>grafana.dpi.ait.ac.th"]
        R_DEMO["*.demo.dpi.ait.ac.th"]
        R_OBS["obs.dpi.ait.ac.th (NS)"]
        R_SB["sandbox-a.dpi.ait.ac.th (NS)"]
    end

    subgraph TIER_VPN ["🛡️ Project: dpi-vpn (~$14/mo)"]
        P_VPN["NetBird Management & Signal Node<br/>(Static External IP)"]
    end

    subgraph TIER_KUBE ["🎛️ Project: dpi-kube-ops (~$25-$70/mo)"]
        P_KUBE["Rancher & VictoriaMetrics / Grafana<br/>(Scheduled On-Demand Node)"]
    end

    subgraph TIER_WORKLOAD ["🚀 Workload Ingress / External"]
        P_DEMO["MOSIP / DLMS Demonstrators"]
        P_OBS["Observability Fleet (ns-cloud-c1..c4)"]
        P_SB["AWS Route53 Sandbox (ns-369.awsdns..)"]
    end

    R_VPN -->|Static IP| P_VPN
    R_KUBE -->|Static / Overlay IP| P_KUBE
    R_DEMO -->|Ingress IP| P_DEMO
    R_OBS -->|Subdomain NS| P_OBS
    R_SB -->|Subdomain NS| P_SB
```

---

## 📋 1. Managed DNS Records (`dpi.ait.ac.th`)

| Record / Hostname | Type | Target / Value | Hosting Project / Destination | Purpose |
| :--- | :---: | :--- | :--- | :--- |
| **`dpi.ait.ac.th`** | NS | `ns-cloud-a*.googledomains.com.` | `ait-brainlab-mgmt` | Authoritative parent delegation from `ait.ac.th` |
| **`dpi.ait.ac.th`** | MX | `10 mx1.improvmx.com.`, `20 mx2.improvmx.com.` | ImprovMX | Inbound email forwarding to operational admins |
| **`dpi.ait.ac.th`** | TXT | `v=spf1 include:spf.improvmx.com ~all` | Global Mail | SPF outbound mail authenticity policy |
| **`netbird.dpi.ait.ac.th`** | A | Static External IP | `dpi-vpn` | NetBird Management API & Admin Dashboard UI |
| **`signal.dpi.ait.ac.th`** | A | Static External IP | `dpi-vpn` | NetBird Signal service (WebRTC negotiation) |
| **`rancher.dpi.ait.ac.th`** | A | Static / Overlay IP | `dpi-kube-ops` | Rancher Multi-Cluster Kubernetes Manager |
| **`grafana.dpi.ait.ac.th`** | A | Static / Overlay IP | `dpi-kube-ops` | Observability & Telemetry Dashboards |
| **`obs.dpi.ait.ac.th`** | NS | `ns-cloud-c*.googledomains.com.` | Delegated GCP Zone | Central telemetry ingestion endpoints |
| **`sandbox-a.dpi.ait.ac.th`** | NS | `ns-*.awsdns-*.com/net/org/co.uk` | AWS Route 53 | Delegated developer sandbox environment |
| **`*.demo.dpi.ait.ac.th`** | A / CNAME | Workload Ingress | `dpi-workload-*` | Public demonstrator environments (MOSIP, DLMS) |
| **`mgmt.dpi.ait.ac.th`** | A / CNAME | Management Ingress | `dpi-mgmt` | Administrative management & GitOps endpoints |

---

## 🔒 2. DNS Governance Standard (The 3-Tier Policy)

To protect institutional reputation, eliminate subdomain takeovers, and prevent email outages, DNS creation follows a strict 3-tier boundary:

### Tier 1: Apex & Core Management (Strict GitOps Only)
* **Scope**: `dpi.ait.ac.th` apex, `MX`, `TXT`, `netbird`, `signal`, `rancher`.
* **Policy**: Zero direct editing via the GCP Console. Any change requires a **Pull Request** in this repository reviewed by Operating Administrators (`akraradet@ait.asia` or `nuttasit@ait.asia`).

### Tier 2: Dynamic Demonstrators & APIs (Kubernetes Ingress Automation)
* **Scope**: `*.demo.dpi.ait.ac.th`, `*.api.dpi.ait.ac.th`.
* **Policy**: Automated via Kubernetes **`external-dns`**. Developers deploy standard Ingress manifests; the controller creates and garbage-collects DNS records dynamically with zero manual intervention.

### Tier 3: Developer Sandboxes (Subdomain Delegation)
* **Scope**: `*.sandbox-a.dpi.ait.ac.th`, `*.dev.dpi.ait.ac.th`.
* **Policy**: Independent subzones delegated via NS records. Research teams hold full admin rights inside their isolated sandboxes with zero blast radius to the root apex domain.

---

## 🔍 3. Validation Commands

Run these commands from any terminal to verify live DNS propagation and delegation:

```bash
# Check Authoritative Nameservers for dpi.ait.ac.th
dig NS dpi.ait.ac.th +short

# Check Parent Delegation trace from root servers
dig dpi.ait.ac.th +trace

# Check Mail Exchange (MX) records
dig MX dpi.ait.ac.th +short

# Check TXT records (SPF policy)
dig TXT dpi.ait.ac.th +short

# Check Subdomain Delegations
dig NS obs.dpi.ait.ac.th +short
dig NS sandbox-a.dpi.ait.ac.th +short
```
