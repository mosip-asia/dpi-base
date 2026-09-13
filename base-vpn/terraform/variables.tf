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
  default     = "asia-southeast1-b"
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

variable "state_bucket" {
  type        = string
  description = "GCS bucket name for state and SQLite database backups"
  default     = "base-dpi-ait-ac-th-tfstate"
}

