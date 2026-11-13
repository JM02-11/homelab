#!/usr/bin/env bash
# Nightly app-level backups from the Apps VM to /mnt/backups (the DAS).
# Installed by apps-setup.sh as /usr/local/sbin/homelab-backup-apps (cron 01:30).
# Keeps 14 days. Restores are covered in each service's README.
set -euo pipefail
REPO=${REPO:-/home/homelab/homelab}
dest=/mnt/backups
day=$(date +%F)
keep_days=14

mountpoint -q "$dest" || { echo "$(date) $dest is not mounted; skipping."; exit 1; }

# --- Nextcloud: database dump + config (user files already live on the DAS) ---
nc="$REPO/services/Nextcloud"
if docker ps --format '{{.Names}}' | grep -qx nextcloud-db; then
  # shellcheck source=/dev/null
  source "$nc/.env"
  docker exec nextcloud-db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$dest/nextcloud/db-$day.sql.gz"
  tar -C "$nc/html" -czf "$dest/nextcloud/config-$day.tar.gz" config
fi

# --- Vaultwarden: consistent SQLite copy + keys/attachments ---
vw="$REPO/services/Vaultwarden/data"
if [[ -f "$vw/db.sqlite3" ]]; then
  sqlite3 "$vw/db.sqlite3" ".backup '$dest/vaultwarden/db-$day.sqlite3'"
  tar -C "$vw" --exclude='db.sqlite3*' --exclude=icon_cache -czf "$dest/vaultwarden/files-$day.tar.gz" .
fi

# --- AdGuard Home: configuration only (query logs are not worth keeping) ---
ag="$REPO/services/AdGuardHome/conf"
[[ -d "$ag" ]] && tar -C "$ag" -czf "$dest/adguardhome/conf-$day.tar.gz" .

find "$dest/nextcloud" "$dest/vaultwarden" "$dest/adguardhome" -type f -mtime +"$keep_days" -delete
echo "$(date) app backups OK"
