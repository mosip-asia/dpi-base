output "domain_name" {
  description = "Subzone domain name for DPI Center Base Infrastructure"
  value       = google_dns_managed_zone.dpi_base_zone.dns_name
}

output "name_servers" {
  description = "Authoritative Cloud DNS nameservers assigned to base.dpi.ait.ac.th (delegate these in ait-brainlab-mgmt)"
  value       = google_dns_managed_zone.dpi_base_zone.name_servers
}

output "terraform_service_account_email" {
  description = "Email of the dedicated Terraform CI/CD automation service account"
  value       = google_service_account.mgmt_terraform_sa.email
}
