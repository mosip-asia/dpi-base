# ==========================================================
# 🤖 Dedicated Service Account for VPN VM
# ==========================================================
resource "google_service_account" "vpn_sa" {
  project      = var.project_id
  account_id   = "base-vpn-sa"
  display_name = "DPI Base NetBird VPN Host Service Account"
}

# Grant least privilege to read/write backups in remote state bucket
resource "google_storage_bucket_iam_member" "backup_access" {
  bucket = var.state_bucket
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.vpn_sa.email}"
}

# Standard logging and monitoring roles
resource "google_project_iam_member" "vpn_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vpn_sa.email}"
}

resource "google_project_iam_member" "vpn_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vpn_sa.email}"
}

# Grant VM service account read access to OAuth secrets in base-mgmt
resource "google_secret_manager_secret_iam_member" "oauth_client_id_accessor" {
  project   = var.mgmt_project_id
  secret_id = "google-oauth-client-id"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vpn_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "oauth_client_secret_accessor" {
  project   = var.mgmt_project_id
  secret_id = "google-oauth-client-secret"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vpn_sa.email}"
}


# ==========================================================
# 📄 Template Rendering (OS Level Only)
# ==========================================================
locals {
  netbird_fqdn = "${var.netbird_subdomain}.${trimsuffix(var.domain_name, ".")}"

  cloud_init_rendered = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    netbird_fqdn = local.netbird_fqdn
    state_bucket = var.state_bucket
  })
}

# ==========================================================
# 🖥️ NetBird Compute Instance (Ubuntu 24.04 LTS on e2-small)
# ==========================================================
resource "google_compute_instance" "vpn_vm" {
  name                      = "base-vpn-vm"
  project                   = var.project_id
  machine_type              = var.machine_type
  zone                      = var.zone
  description               = "DPI Base 24/7 NetBird Mesh Network Tier (Host OS & Docker Engine)"
  allow_stopping_for_update = true

  tags = ["base-vpn-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.vpn_ip.address
    }
  }

  service_account {
    email  = google_service_account.vpn_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data      = local.cloud_init_rendered
  }

  lifecycle {
    ignore_changes = [
      metadata["user-data"],
      boot_disk[0].initialize_params[0].image,
    ]
  }

  depends_on = [
    google_compute_firewall.allow_web,
    google_compute_firewall.allow_wireguard,
    google_compute_firewall.allow_netbird,
    google_compute_firewall.allow_iap_ssh,
    google_storage_bucket_iam_member.backup_access,
  ]
}
