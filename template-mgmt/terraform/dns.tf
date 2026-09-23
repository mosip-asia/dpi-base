# ==========================================================
# 🌐 Authoritative Cloud DNS Subzone: <domain>.dpi.ait.ac.th
# ==========================================================
# This managed zone is 100% owned inside project <domain>-mgmt under
# Organization 350922776586. It is delegated from ait-brainlab-mgmt
# via a single NS record, providing full local DNS sovereignty.
# ==========================================================

# Required GCP APIs for Cloud DNS
resource "google_project_service" "dns_api" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# Subzone: <domain>.dpi.ait.ac.th
resource "google_dns_managed_zone" "domain_zone" {
  name        = "dpi-${var.domain_slug != "" ? var.domain_slug : "mgmt"}"
  dns_name    = var.domain_name
  description = "DPI Center Managed Zone (${var.domain_name})"
  visibility  = "public"

  dnssec_config {
    state = "off"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.dns_api]
}
