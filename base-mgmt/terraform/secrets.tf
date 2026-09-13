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

resource "google_secret_manager_secret_version" "billing_account_id_val" {
  count       = var.billing_account_id != "" ? 1 : 0
  secret      = google_secret_manager_secret.billing_account_id.id
  secret_data = var.billing_account_id
}


