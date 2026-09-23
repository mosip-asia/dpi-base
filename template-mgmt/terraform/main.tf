# ==========================================================
# 🛡️ DPI Center - Domain Management Plane Module
# ==========================================================
# This module manages the permanent, static GCP cloud assets
# for the domain management plane:
# - Cloud DNS Managed Subzone (<domain>.dpi.ait.ac.th)
# - Folder-Level IAM Governance & Team Collaborator Bindings
# - GCP Secret Manager Keys
#
# INVARIANT: This module is applied ONCE and never destroyed.
# Critical resources use lifecycle { prevent_destroy = true }.
# ==========================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "gcs" {
    bucket = "__STATE_BUCKET__"
    prefix = "foundation"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ==========================================================
# 🛑 Project Protection Lien
# ==========================================================
# Enforces an absolute deletion lock on the management project.
# Prevents accidental deletion via GCP Console or CLI.
# ==========================================================
resource "google_resource_manager_lien" "mgmt_project_lien" {
  parent       = "projects/${var.project_id}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "terraform"
  reason       = "Permanent anchor for ${var.domain_name} foundation infrastructure (state, secrets, DNS)"
}
