variable "project_id" {
  type        = string
  description = "GCP Project ID for DPI Management Plane"
  default     = "dpi-mgmt"
}

variable "region" {
  type        = string
  description = "GCP Region for DPI Management Plane resources"
  default     = "asia-southeast1"
}

variable "domain_name" {
  type        = string
  description = "Subzone domain name for DPI Base Infrastructure (must end with dot)"
  default     = "base.dpi.ait.ac.th."
}


variable "google_site_verification" {
  type        = string
  description = "Google domain verification TXT string (e.g. google-site-verification=...)"
  default     = ""
}

variable "google_oauth_client_id" {
  type        = string
  description = "Google OAuth 2.0 Web Client ID to seed into Secret Manager"
  default     = ""
}

variable "google_oauth_client_secret" {
  type        = string
  description = "Google OAuth 2.0 Web Client Secret to seed into Secret Manager"
  sensitive   = true
  default     = ""
}
