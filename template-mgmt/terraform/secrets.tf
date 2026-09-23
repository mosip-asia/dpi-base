# ==========================================================
# 🔐 GCP Secret Manager Keys
# ==========================================================

# Required GCP APIs for Secret Manager
resource "google_project_service" "secretmanager_api" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Secret 1: Google OAuth Web Client ID (Optional SSO)
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

# Secret 2: Google OAuth Web Client Secret (Optional SSO)
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

# ==========================================================
# 👥 Operating Admins: Read Access to the Billing Account ID
# ==========================================================
data "google_project" "mgmt" {
  project_id = var.project_id
}

resource "google_project_iam_member" "folder_admins_billing_account_reader" {
  for_each = toset(local.formatted_folder_admins)

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = each.value

  condition {
    title       = "billing-account-id only"
    description = "Read the billing account ID secret for prj-*.tf envelopes"
    expression  = "resource.name == \"projects/${data.google_project.mgmt.number}/secrets/billing-account-id\" || resource.name.startsWith(\"projects/${data.google_project.mgmt.number}/secrets/billing-account-id/\")"
  }
}

resource "google_project_iam_member" "folder_admins_oauth_client_reader" {
  for_each = toset(local.formatted_folder_admins)

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = each.value

  condition {
    title       = "google-oauth-client only"
    description = "Read the Google OAuth client ID and secret for SSO setup"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.mgmt.number}/secrets/${google_secret_manager_secret.oauth_client_id.secret_id}\") || resource.name.startsWith(\"projects/${data.google_project.mgmt.number}/secrets/${google_secret_manager_secret.oauth_client_secret.secret_id}\")"
  }
}
