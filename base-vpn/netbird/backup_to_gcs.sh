#!/usr/bin/env bash
# ==============================================================================
# 💾 DPI Center — NetBird VPN State & Certificate Backup to GCS
# ==============================================================================
# Takes a hot online snapshot of the NetBird SQLite database, backs up Traefik
# TLS certificates, and securely synchronizes them to GCS.
#
# Executed via:
#   - 6-hourly cron: 0 */6 * * * /opt/netbird/scripts/backup_to_gcs.sh
#   - VM graceful shutdown: ExecStopPost in /etc/systemd/system/dpi-vpn.service
#   - Manual execution: sudo /opt/netbird/scripts/backup_to_gcs.sh
# ==============================================================================
set -euo pipefail

NETBIRD_DIR="/opt/netbird"
STATE_BUCKET="base-dpi-ait-ac-th-tfstate"
BACKUP_PREFIX="gs://${STATE_BUCKET}/backups/netbird"

echo "==> 💾 Starting NetBird backup to ${BACKUP_PREFIX}..."

# 1. Hot snapshot of SQLite database using online backup API
if [ -f "$NETBIRD_DIR/data/store.db" ]; then
  echo "  -> Backing up NetBird store.db..."
  sqlite3 "$NETBIRD_DIR/data/store.db" ".backup /tmp/netbird_store.db"
  gcloud storage cp /tmp/netbird_store.db "${BACKUP_PREFIX}/store.db" --quiet
  rm -f /tmp/netbird_store.db
  echo "  ✔ store.db snapshot uploaded to GCS."
else
  echo "  ℹ store.db not found yet, skipping database backup."
fi

# 2. Backup Traefik Let's Encrypt certificates if present and non-empty
if [ -f "$NETBIRD_DIR/traefik/acme.json" ] && [ -s "$NETBIRD_DIR/traefik/acme.json" ]; then
  echo "  -> Backing up Traefik acme.json certificates..."
  gcloud storage cp "$NETBIRD_DIR/traefik/acme.json" "${BACKUP_PREFIX}/acme.json" --quiet
  echo "  ✔ acme.json uploaded to GCS."
fi

echo "==> 🎉 Backup to GCS completed successfully."
