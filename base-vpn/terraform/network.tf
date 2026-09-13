# ==========================================================
# 🌐 Permanent Regional Static External IP
# ==========================================================
resource "google_compute_address" "vpn_ip" {
  name        = "base-vpn-static-ip"
  project     = var.project_id
  region      = var.region
  description = "Permanent static external IP for DPI Base NetBird Mesh VPN"
}

# ==========================================================
# 🛡️ Firewall Rules (Zero-Trust)
# ==========================================================

# 1. Allow Web Traffic (HTTP 80 for ACME SSL challenge & HTTPS 443 for Traefik)
resource "google_compute_firewall" "allow_web" {
  name        = "base-vpn-allow-web"
  project     = var.project_id
  network     = "default"
  description = "Allow HTTP and HTTPS traffic for Traefik edge proxy"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["base-vpn-node"]
}

# 2. Allow WireGuard Peer-to-Peer Tunnels (UDP 51820)
resource "google_compute_firewall" "allow_wireguard" {
  name        = "base-vpn-allow-wireguard"
  project     = var.project_id
  network     = "default"
  description = "Allow WireGuard direct peer-to-peer tunnels"

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["base-vpn-node"]
}

# 3. Allow NetBird Signal & STUN Traffic
resource "google_compute_firewall" "allow_netbird" {
  name        = "base-vpn-allow-netbird"
  project     = var.project_id
  network     = "default"
  description = "Allow NetBird WireGuard signal and relay broker traffic"

  allow {
    protocol = "tcp"
    ports    = ["33073"]
  }

  allow {
    protocol = "udp"
    ports    = ["33073"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["base-vpn-node"]
}

# 4. Allow SSH Strictly via Google Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "base-vpn-allow-iap-ssh"
  project     = var.project_id
  network     = "default"
  description = "Allow SSH strictly through Google Cloud Identity-Aware Proxy (IAP)"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["base-vpn-node"]
}
