# ==========================================================
# 🌐 Permanent Regional Static External IP
# ==========================================================
resource "google_compute_address" "rancher_ip" {
  name        = "base-kube-ops-static-ip"
  project     = var.project_id
  region      = var.region
  description = "Permanent static external IP for the DPI Base Rancher host"

  # AGENTS.md security rule 2: permanent static IPs carry prevent_destroy.
  # The name and description cannot change without replacing the address.
  lifecycle {
    prevent_destroy = true
  }
}

# ==========================================================
# 🛡️ Firewall Rules (Zero-Trust)
# ==========================================================
# The project's default VPC ships default-allow-ssh and default-allow-rdp
# (priority 1000, no target tags), which open 22 and 3389 to the internet.
# For the Rancher host the IAP allow (800) is evaluated first and the deny
# (900) closes everything else. Found on dpi-kube-ops on 2026-09-10.
# No 6443: downstream cluster agents dial out to 443 only.

# 1. HTTP 80 for the Let's Encrypt HTTP-01 challenge, HTTPS 443 for the UI, API and downstream agents
resource "google_compute_firewall" "allow_web" {
  name        = "base-kube-ops-allow-web"
  project     = var.project_id
  network     = "default"
  description = "Allow HTTP (ACME HTTP-01) and HTTPS (Rancher UI, API, cluster agents)"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["base-kube-ops-node"]
}

# 2. Allow SSH strictly via Google Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "base-kube-ops-allow-iap-ssh"
  project     = var.project_id
  network     = "default"
  priority    = 800
  description = "Allow SSH strictly through Google Cloud Identity-Aware Proxy (IAP)"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.iap_ssh_source_range]
  target_tags   = ["base-kube-ops-node"]
}

# 3. Deny SSH and RDP from anywhere else, out-ranking the default VPC rules
resource "google_compute_firewall" "deny_public_ssh_rdp" {
  name        = "base-kube-ops-deny-public-ssh-rdp"
  project     = var.project_id
  network     = "default"
  priority    = 900
  description = "Out-ranks the default VPC's default-allow-ssh and default-allow-rdp for the Rancher host"

  deny {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["base-kube-ops-node"]
}
