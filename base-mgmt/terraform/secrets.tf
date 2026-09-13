# ==========================================================
# 🔐 GCP Secret Manager Keys
# ==========================================================

# Required GCP APIs for Secret Manager
resource "google_project_service" "secretmanager_api" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Secret 1: Google OAuth Web Client ID
resource "google_secret_manager_secret" "oauth_client_id" {
  secret_id = "google-oauth-client-id"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.secretmanager_api]
}

# Secret 2: Google OAuth Web Client Secret
resource "google_secret_manager_secret" "oauth_client_secret" {
  secret_id = "google-oauth-client-secret"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.secretmanager_api]
}

# ==========================================================
# 🔑 Platform Prerequisite: Authoritative Billing Account ID
# ==========================================================
# Seeded on Day 0 by scripts/bootstrap_domain.sh directly into Secret Manager.
# Child project envelopes (prj-*.tf) read it dynamically here so team members
# and CI/CD never need to know, store, or manage the billing ID on local disk.
data "google_secret_manager_secret_version" "billing_account" {
  project = var.project_id
  secret  = "billing-account-id"
  version = "latest"
}

locals {
  billing_account_id = data.google_secret_manager_secret_version.billing_account.secret_data
}





