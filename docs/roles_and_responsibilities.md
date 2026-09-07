# Roles & Governance Matrix — DPI Center

This document defines the roles, access boundaries, and operational responsibilities across DPI Center infrastructure.

---

## 🏛️ Governance Matrix

| Role | Target Identity | Scope & Authority | Primary Responsibilities |
| :--- | :--- | :--- | :--- |
| **Super Administrator** | `admin@dpi.ait.ac.th` | Google Admin Console (`admin.google.com`) | Break-glass recovery, root organization settings, Cloud Identity governance. |
| **Operating Administrator** | `akraradet@ait.asia` | GCP Org Admin, Project Creator, Billing Admin | Daily infrastructure operations, Cloud DNS, NetBird mesh VPN, IAM management. |
| **Operating Administrator** | `nuttasit@ait.asia` | GCP Org Admin, Project Creator, Billing Admin | Daily infrastructure operations, Kubernetes control plane (Rancher), Observability stack. |
| **Workload / Project Contributor** | Individual Contributor Accounts | Specific Workload Projects (`dpi-workload-*`) | Application deployment, demo configuration, API integration. Zero access to root DNS or management secrets. |

---

## 🔒 Separation of Duties
1. **Management Plane vs. Workload Plane**:
   - Management Plane (`dpi-mgmt`) access is strictly limited to Operating Admins.
   - Workload developers are granted scoped IAM roles on individual project environments without access to root DNS or organization policies.
2. **Zero Permanent Plaintext Credentials**:
   - Service accounts and applications authenticate using GCP Workload Identity or read secrets dynamically from GCP Secret Manager.
