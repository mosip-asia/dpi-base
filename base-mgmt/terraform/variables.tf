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

# --- Domain & Hierarchy Variables (from bootstrap_domain.sh) ---

variable "folder_id" {
  type        = string
  description = "Parent GCP Folder ID (e.g. folders/123456 or numeric ID)"
  default     = "740224775327"
}

variable "folder_admins" {
  type        = list(string)
  description = "List of administrator emails granted access"
  default     = [
    "akraradet@ait.asia",
    "nuttasit@ait.asia",
  ]
}

variable "folder_members" {
  type        = list(string)
  description = "List of viewer emails granted access"
  default     = []
}

