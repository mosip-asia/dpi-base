variable "project_id" {
  type        = string
  description = "GCP Project ID for DPI Base VPN tier"
  default     = "base-vpn"
}

variable "mgmt_project_id" {
  type        = string
  description = "GCP Project ID for DPI Base Management plane (anchors Cloud DNS and Secret Manager)"
  default     = "base-mgmt"
}

variable "mgmt_dns_zone" {
  type        = string
  description = "Name of the authoritative Cloud DNS managed zone in base-mgmt"
  default     = "dpi-base"
}

variable "region" {
  type        = string
  description = "GCP Region for regional static IP and compute resources"
  default     = "asia-southeast1"
}

variable "zone" {
  type        = string
  description = "GCP Zone for Compute Engine instance"
  default     = "asia-southeast1-a"
}

variable "domain_name" {
  type        = string
  description = "Subzone domain name for DPI Base Infrastructure (must end with dot)"
  default     = "base.dpi.ait.ac.th."
}

variable "netbird_subdomain" {
  type        = string
  description = "Subdomain for NetBird Mesh VPN control plane"
  default     = "netbird"
}

variable "machine_type" {
  type        = string
  description = "Machine type for NetBird VPN host VM"
  default     = "e2-small"
}

variable "acme_email" {
  type        = string
  description = "Email address for automated Let's Encrypt SSL certificate registration"
  default     = "admin@dpi.ait.ac.th"
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket name for state and SQLite database backups"
  default     = "base-dpi-ait-ac-th-tfstate"
}

variable "traefik_version" {
  type        = string
  description = "Version tag for Traefik edge proxy"
  default     = "v3.7"
}

variable "netbird_version" {
  type        = string
  description = "Version tag for NetBird Management, Signal, and Relay"
  default     = "0.78.1"
}

variable "single_account_mode_domain" {
  type        = string
  description = "Primary organizational domain for NetBird Single Account Mode"
  default     = "dpi.ait.ac.th"
}

variable "google_oauth_client_id" {
  type        = string
  description = "Google OAuth 2.0 Web Client ID for NetBird SSO"
  default     = "PLACEHOLDER_CLIENT_ID.apps.googleusercontent.com"
}

variable "google_oauth_client_secret" {
  type        = string
  description = "Google OAuth 2.0 Web Client Secret for NetBird SSO"
  default     = "PLACEHOLDER_CLIENT_SECRET"
  sensitive   = true
}
