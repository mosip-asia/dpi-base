variable "project_id" {
  type        = string
  description = "GCP Project ID for DPI Base Management Plane"
  default     = "base-mgmt"
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

# --- Domain & Hierarchy Variables (from bootstrap_domain.sh) ---

variable "organization_id" {
  type        = string
  description = "Google Cloud Organization ID"
  default     = "350922776586"
}

variable "folder_id" {
  type        = string
  description = "Parent GCP Folder ID (e.g. folders/123456 or numeric ID)"
  default     = ""
}

variable "billing_account_id" {
  type        = string
  description = "Billing Account ID linked to this domain"
  default     = ""
}

variable "state_bucket" {
  type        = string
  description = "Remote state storage bucket name"
  default     = "base-dpi-ait-ac-th-tfstate"
}

variable "folder_admins" {
  type        = list(string)
  description = "List of administrator emails granted access"
  default     = []
}

variable "folder_members" {
  type        = list(string)
  description = "List of viewer emails granted access"
  default     = []
}
