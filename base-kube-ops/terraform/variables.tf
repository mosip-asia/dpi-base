variable "project_id" {
  type        = string
  description = "GCP Project ID for the DPI Base control plane tier (created by base-mgmt/terraform/prj-base-kube-ops.tf)"
  default     = "base-kube-ops"
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
  description = "GCP Region for the regional static IP, the instance schedule and compute resources"
  default     = "asia-southeast1"
}

variable "zone" {
  type        = string
  description = "GCP Zone for the Compute Engine instance. Zone b, like base-vpn: zone a ran out of e2 capacity for about 17 hours on 2026-09-13/14. The boot disk is zonal, so changing this later rebuilds the VM."
  default     = "asia-southeast1-b"
}

variable "domain_name" {
  type        = string
  description = "Subzone domain name for DPI Base Infrastructure (must end with dot)"
  default     = "base.dpi.ait.ac.th."

  validation {
    condition     = endswith(var.domain_name, ".")
    error_message = "domain_name must end with a dot, e.g. base.dpi.ait.ac.th."
  }
}

variable "rancher_subdomain" {
  type        = string
  description = "Subdomain of the A record this root owns in the dpi-base zone"
  default     = "rancher"
}

variable "canonical_fqdn" {
  type        = string
  description = "Rancher server URL host. A CNAME to <rancher_subdomain>.<domain_name> in the parent zone dpi-center (ait-brainlab-mgmt), created by hand like netbird.dpi.ait.ac.th. Must match RANCHER_FQDN in ../rancher/.env.template."
  default     = "rancher.dpi.ait.ac.th"
}

variable "machine_type" {
  type        = string
  description = "Machine type for the Rancher host (issue #5: 4 vCPU / 16 GB)"
  default     = "e2-standard-4"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB; K3s, images and Rancher's datastore live here"
  default     = 50
}

variable "boot_disk_type" {
  type        = string
  description = "Boot disk type"
  default     = "pd-balanced"
}

variable "image" {
  type        = string
  description = "Boot image; cloud-init and deploy.sh assume Ubuntu"
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "service_dir" {
  type        = string
  description = "Directory on the VM that holds the Rancher deployer (flat, owned by ubuntu). Must match RANCHER_DIR in ../rancher/.env.template."
  default     = "/opt/rancher"
}

variable "iap_ssh_source_range" {
  type        = string
  description = "Google Identity-Aware Proxy TCP forwarding range; the only source allowed on port 22"
  default     = "35.235.240.0/20"
}

variable "admin_users" {
  type        = list(string)
  description = "Administrator user emails granted OS Admin Login and IAP Tunneling on base-kube-ops"
  default = [
    "akraradet@ait.asia",
    "nuttasit@ait.asia",
  ]
}

variable "schedule_start_cron" {
  type        = string
  description = "Instance schedule start, cron in schedule_time_zone. Policy fields are immutable: see schedule.tf before changing."
  default     = "30 8 * * 1-5"
}

variable "schedule_stop_cron" {
  type        = string
  description = "Instance schedule stop, cron in schedule_time_zone"
  default     = "30 18 * * 1-5"
}

variable "schedule_time_zone" {
  type        = string
  description = "IANA time zone of the instance schedule (AGENTS.md security rule 6)"
  default     = "Asia/Bangkok"
}
