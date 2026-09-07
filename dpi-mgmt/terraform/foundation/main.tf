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

  # Once the GCS bucket gs://dpi-mgmt-tfstate is created, uncomment the backend block below.
  # backend "gcs" {
  #   bucket = "dpi-mgmt-tfstate"
  #   prefix = "foundation"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
