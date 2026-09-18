# ==========================================================
# ⏰ Instance Schedule (Control Plane Schedulability)
# ==========================================================
# Starts the Rancher host at 08:30 and stops it at 18:30, Monday to
# Friday, Asia/Bangkok (AGENTS.md security rule 7). Downstream K3s
# clusters keep running while Rancher is off; proven on dpi-kube-ops
# on 2026-09-14 (17 hours off, the cluster agent reconnected by itself).
#
# Policy fields are immutable. To change a cron, detach first:
#   gcloud compute instances remove-resource-policies base-kube-ops-vm \
#     --zone asia-southeast1-b --project base-kube-ops \
#     --resource-policies base-kube-ops-schedule
# then terraform apply. Attaching and detaching is an in-place update
# in provider 5.45.2 (checked in its source; its docs say otherwise).
#
# A scheduled start does not retry. When the zone has no capacity
# (ZONE_RESOURCE_POOL_EXHAUSTED) the VM simply stays off; see
# base-kube-ops/README.md for the recovery steps.
# ==========================================================

data "google_project" "this" {
  project_id = var.project_id
}

# The schedule starts and stops the VM as the Compute Engine service agent,
# which needs instanceAdmin on the project for that.
resource "google_project_iam_member" "compute_service_agent_instance_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:service-${data.google_project.this.number}@compute-system.iam.gserviceaccount.com"
}

resource "google_compute_resource_policy" "schedule" {
  name        = "base-kube-ops-schedule"
  project     = var.project_id
  region      = var.region
  description = "Start 08:30 and stop 18:30 Mon-Fri Asia/Bangkok for the on-demand Rancher host"

  instance_schedule_policy {
    vm_start_schedule {
      schedule = var.schedule_start_cron
    }
    vm_stop_schedule {
      schedule = var.schedule_stop_cron
    }
    time_zone = var.schedule_time_zone
  }
}
