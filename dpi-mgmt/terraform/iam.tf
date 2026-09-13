# ==========================================================
# 👥 IAM Governance & Automation Service Account
# ==========================================================

# Required GCP APIs for IAM
resource "google_project_service" "iam_apis" {
  for_each = toset([
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

locals {
  authorized_editors = [
    "user:akraradet@ait.asia",
    "user:nuttasit@ait.asia",
  ]
}

# Project Editors (Daily Technical Administrators)
resource "google_project_iam_member" "editors" {
  for_each = toset(local.authorized_editors)

  project    = var.project_id
  role       = "roles/editor"
  member     = each.key
  depends_on = [google_project_service.iam_apis]
}

# Dedicated Service Account for Terraform CI/CD & Automation
resource "google_service_account" "mgmt_terraform_sa" {
  account_id   = "dpi-mgmt-terraform"
  display_name = "DPI Management Terraform Service Account"
  description  = "Service account used by Terraform and automation pipelines to manage infrastructure"
  depends_on   = [google_project_service.iam_apis]
}

# Grant DNS Admin to Terraform Service Account
resource "google_project_iam_member" "sa_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.mgmt_terraform_sa.email}"
}

# Grant Secret Manager Admin to Terraform Service Account
resource "google_project_iam_member" "sa_secrets_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.mgmt_terraform_sa.email}"
}

# Grant Storage Object Admin for State & Backups
resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.mgmt_terraform_sa.email}"
}
