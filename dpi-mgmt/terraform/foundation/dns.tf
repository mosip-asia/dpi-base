# ==========================================================
# 🌐 Authoritative Cloud DNS: dpi.ait.ac.th
# ==========================================================

# Required GCP APIs for Cloud DNS
resource "google_project_service" "dns_api" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# Authoritative Zone: dpi.ait.ac.th
resource "google_dns_managed_zone" "dpi_th_zone" {
  name        = "dpi-th"
  dns_name    = var.domain_name
  description = "DPI Center Public Authoritative Domain (dpi.ait.ac.th)"
  visibility  = "public"

  dnssec_config {
    state = "off"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.dns_api]
}

# Inbound Mail Routing (MX Records for Email Forwarding)
resource "google_dns_record_set" "dpi_mx" {
  name         = var.domain_name
  managed_zone = google_dns_managed_zone.dpi_th_zone.name
  type         = "MX"
  ttl          = 3600
  rrdatas = [
    "10 mx1.improvmx.com.",
    "20 mx2.improvmx.com."
  ]
}

# TXT Records: SPF and Domain Ownership Verification
locals {
  txt_records = compact([
    "\"v=spf1 include:spf.improvmx.com ~all\"",
    var.google_site_verification != "" ? "\"${var.google_site_verification}\"" : ""
  ])
}

resource "google_dns_record_set" "dpi_txt" {
  name         = var.domain_name
  managed_zone = google_dns_managed_zone.dpi_th_zone.name
  type         = "TXT"
  ttl          = 300
  rrdatas      = local.txt_records
}
