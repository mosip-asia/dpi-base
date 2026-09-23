# ==========================================================
# 🐮 DPI Center — Control Plane Tier (Rancher on K3s)
# ==========================================================
# This module manages the cloud infrastructure for the on-demand
# Rancher management host in project base-kube-ops:
# - Regional Static External IP (base-kube-ops-static-ip)
# - Firewall rules (Web, IAP-only SSH, deny public SSH/RDP)
# - Compute Engine VM host (e2-standard-4 on Ubuntu 24.04 LTS)
# - Instance schedule (08:30-18:30 Mon-Fri, Asia/Bangkok)
# - Decoupled Cloud DNS record (rancher.base.dpi.ait.ac.th)
#
# The project container (billing, APIs, lien) is declared in
# base-mgmt/terraform/prj-base-kube-ops.tf. K3s, cert-manager and
# Rancher are installed by ../rancher/deploy.sh over IAP, never here.
# ==========================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source = "hashicorp/google"
      # Exact pin (AGENTS.md security rule 5; issue #5 spec: ~> 5.45.0).
      version = "5.45.2"
    }
  }

  backend "gcs" {
    bucket = "base-dpi-ait-ac-th-tfstate"
    prefix = "base-kube-ops"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
