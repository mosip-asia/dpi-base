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

resource "google_secret_manager_secret_version" "oauth_client_id_version" {
  count       = var.google_oauth_client_id != "" ? 1 : 0
  secret      = google_secret_manager_secret.oauth_client_id.id
  secret_data = var.google_oauth_client_id
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

resource "google_secret_manager_secret_version" "oauth_client_secret_version" {
  count       = var.google_oauth_client_secret != "" ? 1 : 0
  secret      = google_secret_manager_secret.oauth_client_secret.id
  secret_data = var.google_oauth_client_secret
}
