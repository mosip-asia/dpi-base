output "rancher_static_ip" {
  description = "Permanent regional static external IP address of the Rancher host"
  value       = google_compute_address.rancher_ip.address
}

output "rancher_base_fqdn" {
  description = "A record owned by this root in zone dpi-base"
  value       = local.rancher_fqdn
}

output "rancher_url" {
  description = "Rancher server URL (canonical name, a CNAME to rancher_base_fqdn)"
  value       = "https://${var.canonical_fqdn}"
}

output "cname_request" {
  description = "The record to create by hand in parent zone dpi-center (ait-brainlab-mgmt)"
  value       = "${var.canonical_fqdn}. 300 IN CNAME ${local.rancher_fqdn}."
}

output "instance_name" {
  description = "Compute Engine instance name"
  value       = google_compute_instance.rancher_vm.name
}

output "zone" {
  description = "Zone of the Rancher host"
  value       = google_compute_instance.rancher_vm.zone
}

output "service_account_email" {
  description = "Service account attached to the Rancher VM"
  value       = google_service_account.rancher_sa.email
}

output "schedule_policy" {
  description = "Instance schedule attached to the Rancher VM"
  value       = google_compute_resource_policy.schedule.name
}
