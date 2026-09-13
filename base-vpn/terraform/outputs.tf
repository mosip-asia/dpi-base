output "vpn_static_ip" {
  description = "Permanent regional static external IP address for NetBird VPN"
  value       = google_compute_address.vpn_ip.address
}

output "netbird_fqdn" {
  description = "Fully-qualified domain name for NetBird VPN Control Plane"
  value       = local.netbird_fqdn
}

output "netbird_url" {
  description = "Dashboard & API URL for NetBird Mesh VPN"
  value       = "https://${local.netbird_fqdn}"
}

output "instance_name" {
  description = "Compute Engine instance name"
  value       = google_compute_instance.vpn_vm.name
}

output "service_account_email" {
  description = "Service account attached to the VPN VM"
  value       = google_service_account.vpn_sa.email
}
