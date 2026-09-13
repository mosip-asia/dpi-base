# ==========================================================
# 🌐 Authoritative Cloud DNS Subzone: base.dpi.ait.ac.th
# ==========================================================
# This managed zone is 100% owned inside project dpi-mgmt under
# Organization 350922776586. It is delegated from ait-brainlab-mgmt
# via a single NS record, providing full local DNS sovereignty.
# ==========================================================

# Required GCP APIs for Cloud DNS
resource "google_project_service" "dns_api" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# Subzone: base.dpi.ait.ac.th
resource "google_dns_managed_zone" "dpi_base_zone" {
  name        = "dpi-base"
  dns_name    = var.domain_name
  description = "DPI Center Base Infrastructure Managed Zone (base.dpi.ait.ac.th)"
  visibility  = "public"

  dnssec_config {
    state = "off"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.dns_api]
}

