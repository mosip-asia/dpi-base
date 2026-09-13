# ==============================================================================
# 🌐 Child Project Envelope: base-vpn (Tier 1 Network Fabric / NetBird VPN)
# ==============================================================================
# This template provisions the GCP project container, attaches billing, enables
# required APIs, and locks deletion via a project lien.
#
# Internal resources (VMs, IPs, firewall, NetBird stack) are declared inside
# the workload project repository: base-vpn/terraform/
# ==============================================================================

# 1. Project Container & Billing Association
resource "google_project" "base_vpn" {
  name            = "DPI Base VPN - NetBird"
  project_id      = "base-vpn"
  folder_id       = var.folder_id
  billing_account = var.billing_account_id
}

# 2. Enabled APIs for this Tier
resource "google_project_service" "base_vpn_services" {
  for_each = toset([
    "compute.googleapis.com",
  ])
  project            = google_project.base_vpn.project_id
  service            = each.key
  disable_on_destroy = false
}

# 3. Project Deletion Protection Lien
resource "google_resource_manager_lien" "base_vpn_lien" {
  parent       = "projects/${google_project.base_vpn.project_id}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "terraform"
  reason       = "Permanent anchor for DPI Center Network Fabric (NetBird VPN)"
}
