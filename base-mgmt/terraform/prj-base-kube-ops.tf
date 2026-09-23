# ==============================================================================
# 🐮 Child Project Envelope: base-kube-ops (Tier 2 Control Plane / Rancher)
# ==============================================================================
# This template provisions the GCP project container, attaches billing, enables
# required APIs, and locks deletion via a project lien.
#
# Internal resources (VM, static IP, firewall, instance schedule, DNS record) are
# declared inside the workload project repository: base-kube-ops/terraform/
#
# Applied from the Phase 3 PR branch (feat/issue-5-kube-ops) before that PR merges.
# Until it merges, apply base-mgmt/terraform only from that branch: a plan from
# main would remove this lien and then delete the project.
# ==============================================================================

# 1. Project Container & Billing Association
resource "google_project" "base_kube_ops" {
  name            = "DPI Base Kube Ops - Rancher"
  project_id      = "base-kube-ops"
  folder_id       = var.folder_id
  billing_account = local.billing_account_id
}

# 2. Enabled APIs for this Tier
resource "google_project_service" "base_kube_ops_services" {
  for_each = toset([
    "compute.googleapis.com",
  ])
  project            = google_project.base_kube_ops.project_id
  service            = each.key
  disable_on_destroy = false
}

# 3. Project Deletion Protection Lien
resource "google_resource_manager_lien" "base_kube_ops_lien" {
  parent       = "projects/${google_project.base_kube_ops.project_id}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "terraform"
  reason       = "Permanent anchor for DPI Center Control Plane (Rancher)"
}
