# Management Plane (`dpi-mgmt/`) — DPI Center

This directory contains the central Infrastructure-as-Code (IaC), identity configurations, and operational governance tools for the **DPI Center**.

---

## 🏛️ Architecture Overview

The DPI Center management plane is designed to be:
* **100% Stateless & GitOps Managed**: All infrastructure state is defined declaratively in Terraform and version-controlled.
* **Cost-Efficient**: Operates at ~$0.20/month base cost (covering only authoritative Cloud DNS records and GCS state storage).
* **High Availability**: Backed by Google Cloud Platform's globally distributed Cloud DNS and Identity infrastructure (100% SLA).

```text
dpi-mgmt/
├── README.md                      # Management plane architecture & operations (this file)
├── oauth_setup.md                 # Google OAuth2 / OIDC console setup SOP
└── terraform/                     # Project baseline, Cloud DNS, IAM, Secrets (flattened layout)
```

---

## 🔑 Core Governance Principles

1. **Root Organization (`dpi.ait.ac.th`)**:
   Managed under Google Cloud Identity Free (Org ID: `350922776586`). Provides sovereign organizational control, centralized IAM policies, and resource hierarchy without recurring subscription fees.

2. **Decoupled Workloads & Compute**:
   The management plane (`dpi-mgmt`) is strictly reserved for authoritative Cloud DNS, GCS remote state (`gs://dpi-mgmt-tfstate`), root IAM, and shared secrets. Compute workloads run in dedicated tier projects (`dpi-vpn`, `dpi-kube-ops`, `dpi-workload-*`).

3. **Operations Access**:
   Daily administration authenticates using individual university accounts (`akraradet@ait.asia` and `nuttasit@ait.asia`) and dedicated Terraform service accounts (`dpi-mgmt-terraform`). Root super admin (`admin@dpi.ait.ac.th`) is strictly break-glass.
