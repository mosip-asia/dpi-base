output "domain_name" {
  description = "Apex domain name for DPI Center"
  value       = google_dns_managed_zone.dpi_th_zone.dns_name
}

output "name_servers" {
  description = "Authoritative Cloud DNS nameservers assigned to dpi.ait.ac.th"
  value       = google_dns_managed_zone.dpi_th_zone.name_servers
}

output "terraform_service_account_email" {
  description = "Email of the dedicated Terraform CI/CD automation service account"
  value       = google_service_account.mgmt_terraform_sa.email
}
