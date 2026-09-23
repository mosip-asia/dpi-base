variable "project_id" {
  type        = string
  description = "GCP Project ID for Domain Management Plane (<domain>-mgmt)"
}

variable "region" {
  type        = string
  description = "GCP Region for Domain Management Plane resources"
  default     = "asia-southeast1"
}

variable "domain_name" {
  type        = string
  description = "Subzone domain name for Domain Infrastructure (must end with dot, e.g. <domain>.dpi.ait.ac.th.)"
}

variable "domain_slug" {
  type        = string
  description = "Domain slug identifier (e.g. ait-vc, mosip-asia)"
  default     = ""
}

# --- Domain & Hierarchy Variables (from bootstrap_domain.sh) ---

variable "folder_id" {
  type        = string
  description = "Parent GCP Folder ID (e.g. folders/123456 or numeric ID)"
}

variable "folder_admins" {
  type        = list(string)
  description = "List of administrator emails granted access"
  default = [
    "akraradet@ait.asia",
    "nuttasit@ait.asia",
  ]
}

variable "folder_members" {
  type        = list(string)
  description = "List of viewer emails granted access"
  default     = []
}

variable "billing_account_id" {
  type        = string
  description = "Authoritative Google Cloud Billing Account ID"
  default     = ""
}
