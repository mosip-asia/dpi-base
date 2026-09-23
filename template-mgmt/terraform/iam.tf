# ==========================================================
# 👥 IAM Governance (Folder-Level Inheritance)
# ==========================================================

# Required GCP APIs for Management Plane
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
  formatted_folder_id = var.folder_id != "" ? (
    startswith(var.folder_id, "folders/") ? var.folder_id : "folders/${var.folder_id}"
  ) : ""

  # Ensure user: prefix for emails
  formatted_folder_admins = [
    for member in var.folder_admins :
    startswith(member, "user:") || startswith(member, "group:") || startswith(member, "serviceAccount:") ? member : "user:${member}"
  ]

  formatted_folder_members = [
    for member in var.folder_members :
    startswith(member, "user:") || startswith(member, "group:") || startswith(member, "serviceAccount:") ? member : "user:${member}"
  ]
}

# ------------------------------------------------------------------------------
# Folder Admins: Inherited folder administration & editor access across all child projects
# ------------------------------------------------------------------------------
resource "google_folder_iam_member" "folder_admins_editor" {
  for_each = local.formatted_folder_id != "" ? toset(local.formatted_folder_admins) : []

  folder = local.formatted_folder_id
  role   = "roles/editor"
  member = each.value
}

resource "google_folder_iam_member" "folder_admins_folder_admin" {
  for_each = local.formatted_folder_id != "" ? toset(local.formatted_folder_admins) : []

  folder = local.formatted_folder_id
  role   = "roles/resourcemanager.folderAdmin"
  member = each.value
}

# ------------------------------------------------------------------------------
# Folder Members: Inherited viewer access across all child projects
# ------------------------------------------------------------------------------
resource "google_folder_iam_member" "folder_members_viewer" {
  for_each = local.formatted_folder_id != "" ? toset(local.formatted_folder_members) : []

  folder = local.formatted_folder_id
  role   = "roles/viewer"
  member = each.value
}
