# ==========================================================
# 🌐 Decoupled Authoritative DNS Record for Rancher
# ==========================================================
# Points rancher.base.dpi.ait.ac.th to the static IP of this project.
# Managed zone "dpi-base" is anchored in project base-mgmt
# (docs/sop-workload.md Step 6).
#
# The Rancher server URL, rancher.dpi.ait.ac.th, is a CNAME to this
# record in the parent zone dpi-center (ait-brainlab-mgmt), created by
# hand like netbird.dpi.ait.ac.th. See output "cname_request".
# ==========================================================

resource "google_dns_record_set" "rancher" {
  project      = var.mgmt_project_id
  managed_zone = var.mgmt_dns_zone
  name         = "${var.rancher_subdomain}.${var.domain_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.rancher_ip.address]
}
