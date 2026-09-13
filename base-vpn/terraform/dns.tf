# ==========================================================
# 🌐 Decoupled Authoritative DNS Record for NetBird VPN
# ==========================================================
# Points netbird.base.dpi.ait.ac.th to the static IP in base-vpn.
# Managed zone "dpi-base" is anchored in project base-mgmt.
# ==========================================================

resource "google_dns_record_set" "netbird" {
  project      = var.mgmt_project_id
  managed_zone = var.mgmt_dns_zone
  name         = "${var.netbird_subdomain}.${var.domain_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.vpn_ip.address]
}
