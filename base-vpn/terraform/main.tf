# ==========================================================
# 📡 DPI Center — Network Fabric Tier (NetBird Mesh VPN)
# ==========================================================
# This module manages the permanent cloud infrastructure for
# the 24/7 WireGuard Mesh VPN tier in project base-vpn:
# - Regional Static External IP (base-vpn-static-ip)
# - Zero-trust firewall rules (Web, WireGuard, NetBird, IAP SSH)
# - Compute Engine VM host (e2-micro on Ubuntu 24.04 LTS)
# - Decoupled Cloud DNS record (netbird.base.dpi.ait.ac.th)
# ==========================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "gcs" {
    bucket = "base-dpi-ait-ac-th-tfstate"
    prefix = "base-vpn"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
