output "domain_name" {
  description = "Subzone domain name for DPI Center Base Infrastructure"
  value       = google_dns_managed_zone.dpi_base_zone.dns_name
}

output "name_servers" {
  description = "Authoritative Cloud DNS nameservers assigned to base.dpi.ait.ac.th (delegate these in ait-brainlab-mgmt)"
  value       = google_dns_managed_zone.dpi_base_zone.name_servers
}
