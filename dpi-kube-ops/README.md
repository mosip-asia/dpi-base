# `dpi-kube-ops` — K8s Cluster Management & Observability Hub

**GCP Project**: `dpi-kube-ops`  
**Purpose**: Centralized multi-cluster Kubernetes orchestration (Rancher Community) and ultra-low overhead telemetry (VictoriaMetrics, Grafana Loki, Grafana OSS).

---

## 🏗 Architecture
* **Kubernetes Manager**: Rancher Community Server (Apache 2.0 open source, $0 license fee) for MOSIP platform compatibility.
* **Metrics TSDB**: VictoriaMetrics Single (1/5th to 1/7th RAM of Prometheus, native remote-write).
* **Logs**: Grafana Loki (compressed chunked logs on disk/GCS).
* **Visualization**: Grafana OSS.
* **Compute Host**: `e2-standard-4` (4 vCPU, 16 GB RAM).
* **Operating Mode**: **On-Demand / Scheduled** via GCP Instance Schedules (e.g. Mon–Fri 08:30–18:30, saving ~65–75% compute costs).
* **DNS FQDN**: `rancher.dpi.ait.ac.th` and `grafana.dpi.ait.ac.th`.

---

## 📁 Directory Structure
```text
dpi-kube-ops/
├── README.md              # This documentation
├── terraform/             # VPC, e2-standard-4 VM, persistent disk, GCP Instance Schedule
└── helm/                  # Values files for Rancher, VictoriaMetrics, and Grafana
```

---

## 🔑 Authentication & Single Sign-On (SSO)

Rancher and Grafana do **not** maintain isolated user directories. They connect to the central **Google OAuth2 / OIDC** credentials provisioned in `dpi-mgmt`:

* **Shared Credentials**: Uses `google-oauth-client-id` and `google-oauth-client-secret` stored in `dpi-mgmt` Secret Manager.
* **Redirect URIs**:
  * Rancher: `https://rancher.dpi.ait.ac.th/verify-auth`
  * Grafana: `https://grafana.dpi.ait.ac.th/login/generic_oauth`
* **Accepted Domains**: `@dpi.ait.ac.th`, `@ait.asia`, `@ait.ac.th`, and `@gmail.com` (enabled by the **External** OAuth Consent Screen).
* **Kubernetes RBAC Access Mode**: Rancher's auth provider is set to **"Restricted"** access mode. Anyone with an accepted Google account can authenticate their identity, but **they are granted zero permissions until an administrator explicitly binds their account to specific clusters or projects**.

See [`dpi-mgmt/oauth_setup.md`](../dpi-mgmt/oauth_setup.md) for full configuration steps.

