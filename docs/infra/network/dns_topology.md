# Domain & DNS Architecture — DPI Center

## Overview
DPI Center operates under the public authoritative apex domain **`dpi.ait.ac.th`** routed through Google Cloud DNS in project **`dpi-mgmt`**.

---

## 1. Managed DNS Records (`dpi.ait.ac.th`)

| Record / Hostname | Type | Target / Value | Purpose |
| :--- | :---: | :--- | :--- |
| **`dpi.ait.ac.th`** | NS | `ns-cloud-*.googledomains.com.` | Authoritative nameserver delegation |
| **`dpi.ait.ac.th`** | MX | `10 mx1.improvmx.com.`, `20 mx2.improvmx.com.` | Email forwarding to operational administrators |
| **`dpi.ait.ac.th`** | TXT | `v=spf1 include:spf.improvmx.com ~all` | SPF email security policy |
| **`dpi.ait.ac.th`** | TXT | `google-site-verification=...` | Cloud Identity Free domain ownership proof |
| **`netbird.dpi.ait.ac.th`** | A | `dpi-vpn` Static External IP | NetBird Management API & Dashboard UI |
| **`signal.dpi.ait.ac.th`** | A | `dpi-vpn` Static External IP | NetBird Signal service (WebRTC) |
| **`rancher.dpi.ait.ac.th`** | A | `dpi-kube-ops` Static / Overlay IP | Rancher Multi-Cluster Kubernetes Manager |
| **`grafana.dpi.ait.ac.th`** | A | `dpi-kube-ops` Static / Overlay IP | Observability & Telemetry Dashboards |
| **`demo.dpi.ait.ac.th`** | A / CNAME | Workload Ingress | Demonstrator Ingress (MOSIP, DLMS) |
| **`mgmt.dpi.ait.ac.th`** | A / CNAME | Management Plane Ingress | Administrative management & GitOps endpoints |

---

## 2. Validation Commands

Run these commands from any terminal to verify global DNS propagation and delegation:

```bash
# Check Authoritative Nameservers for dpi.ait.ac.th
dig NS dpi.ait.ac.th +short

# Check Parent Delegation trace from root
dig dpi.ait.ac.th +trace

# Check Mail Exchange (MX) records
dig MX dpi.ait.ac.th +short

# Check TXT records (SPF and Google verification)
dig TXT dpi.ait.ac.th +short
```
