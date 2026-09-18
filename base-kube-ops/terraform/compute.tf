# ==========================================================
# 🤖 Dedicated Service Account for the Rancher VM
# ==========================================================
resource "google_service_account" "rancher_sa" {
  project      = var.project_id
  account_id   = "base-kube-ops-sa"
  display_name = "DPI Base Kube Ops Rancher Host Service Account"
}

# Standard logging and monitoring roles
resource "google_project_iam_member" "rancher_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.rancher_sa.email}"
}

resource "google_project_iam_member" "rancher_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.rancher_sa.email}"
}

# ==========================================================
# 👥 Operator Project-Level IAM (OS Login & IAP Tunneling)
# ==========================================================
# Operators whose accounts live outside the dpi.ait.ac.th organization
# (@ait.asia) also need roles/compute.osLoginExternalUser on the
# organization. It exists only at organization level and was granted by
# hand to both admins on 2026-09-13.
resource "google_project_iam_member" "operator_os_admin" {
  for_each = toset(var.admin_users)

  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = startswith(each.value, "user:") ? each.value : "user:${each.value}"
}

resource "google_project_iam_member" "operator_iap_tunnel" {
  for_each = toset(var.admin_users)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = startswith(each.value, "user:") ? each.value : "user:${each.value}"
}

# ==========================================================
# 📄 Template Rendering (OS Level Only)
# ==========================================================
locals {
  rancher_fqdn = "${var.rancher_subdomain}.${trimsuffix(var.domain_name, ".")}"

  cloud_init_rendered = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    service_dir = var.service_dir
  })
}

# ==========================================================
# 🖥️ Rancher Compute Instance (Ubuntu 24.04 LTS on e2-standard-4)
# ==========================================================
resource "google_compute_instance" "rancher_vm" {
  name                      = "base-kube-ops-vm"
  project                   = var.project_id
  machine_type              = var.machine_type
  zone                      = var.zone
  description               = "DPI Base on-demand Rancher management host (single-node K3s); stopped by schedule outside office hours"
  allow_stopping_for_update = true

  tags = ["base-kube-ops-node"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.rancher_ip.address
    }
  }

  service_account {
    email  = google_service_account.rancher_sa.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    user-data              = local.cloud_init_rendered
  }

  resource_policies = [google_compute_resource_policy.schedule.self_link]

  lifecycle {
    # cloud-init runs on first boot only; application changes go through
    # ../remote-deploy.sh, never a VM rebuild. A newer image must not force one either.
    ignore_changes = [
      metadata["user-data"],
      boot_disk[0].initialize_params[0].image,
    ]
  }

  depends_on = [
    google_compute_firewall.allow_web,
    google_compute_firewall.allow_iap_ssh,
    google_compute_firewall.deny_public_ssh_rdp,
    google_project_iam_member.compute_service_agent_instance_admin,
  ]
}
