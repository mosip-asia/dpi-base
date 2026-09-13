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

# Secret 3: Google Cloud Billing Account ID (for automated workspace sync)
resource "google_secret_manager_secret" "billing_account_id" {
  secret_id = "billing-account-id"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.secretmanager_api]
}

# --- Dynamic Billing Resolution: Direct from Secret Manager for Team & CI/CD ---
# Child projects (prj-*.tf) read billing_account_id directly from Secret Manager,
# so team members and CI/CD never need to know or store the billing account ID on disk.
data "google_secret_manager_secret_version" "billing_account" {
  project = var.project_id
  secret  = google_secret_manager_secret.billing_account_id.secret_id
  version = "latest"
}

locals {
  billing_account_id = data.google_secret_manager_secret_version.billing_account.secret_data
}




