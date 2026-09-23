output "domain_name" {
  description = "Subzone domain name for this domain"
  value       = google_dns_managed_zone.domain_zone.dns_name
}

output "name_servers" {
  description = "Authoritative Cloud DNS nameservers assigned to this domain subzone (delegate these in ait-brainlab-mgmt)"
  value       = google_dns_managed_zone.domain_zone.name_servers
}
