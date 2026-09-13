# ==========================================================
# 🛡️ DPI Center - Consolidated Cloud Foundation Module
# ==========================================================
# This module manages 100% of the permanent, static GCP cloud
# assets for dpi-mgmt:
# - Cloud DNS Zone (dpi.ait.ac.th) & Core Records
# - Project IAM Governance & CI/CD Service Account
# - GCP Secret Manager Keys
#
# INVARIANT: This module is applied ONCE and never destroyed.
# All sensitive and critical resources use prevent_destroy = true.
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
    bucket = "dpi-mgmt-tfstate"
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
# Enforces an absolute deletion lock on the foundation project.
# Prevents accidental deletion via GCP Console or CLI.
# ==========================================================
resource "google_resource_manager_lien" "mgmt_project_lien" {
  parent       = "projects/${var.project_id}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "terraform"
  reason       = "Permanent anchor for DPI Center foundation infrastructure (state, secrets, DNS)"
}

