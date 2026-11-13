#!/usr/bin/env bash
# Phase 3: Proxmox directory mappings for virtiofs, the VM backup storage and job,
# and daily ZFS snapshots. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env

# --- Directory mappings (shared into VMs with virtiofs; the ID is also the mount tag) ---
add_mapping() {
  local id=$1 path=$2
  if pvesh get "/cluster/mapping/dir/$id" &>/dev/null; then
    echo "Mapping '$id' already exists."
  else
    pvesh create /cluster/mapping/dir --id "$id" --map "node=${NODE},path=${path}"
    echo "Added mapping '$id' -> $path"
  fi
}
add_mapping nextcloud "/${POOL}/vault/nextcloud"
add_mapping backups   "/${POOL}/vault/backups"

# --- Storage for Proxmox VM backups, on the pool instead of the boot NVMe ---
if ! grep -q "^dir: das-vzdump$" /etc/pve/storage.cfg; then
  pvesm add dir das-vzdump --path "/${POOL}/vzdump" --content backup --is_mountpoint yes \
    --prune-backups keep-daily=7,keep-weekly=4,keep-monthly=3
  echo "Added storage 'das-vzdump'."
fi

# --- Nightly backup job for both VMs at 03:00 ---
if pvesh get /cluster/backup --output-format json | grep -q '"storage":"das-vzdump"'; then
  echo "Backup job to das-vzdump already exists."
else
  pvesh create /cluster/backup --schedule "03:00" --storage das-vzdump \
    --vmid "${APPS_VMID},${MC_VMID}" --mode snapshot --compress zstd --enabled 1 \
    --notes-template "{{guestname}} nightly"
  echo "Added nightly backup job (03:00)."
fi

# --- Daily ZFS snapshots of the vault datasets (protects against deletion/ransomware, not drive loss) ---
install -m 0755 ./zfs-snapshot.sh /usr/local/sbin/homelab-zfs-snapshot
cat > /etc/cron.d/homelab-zfs-snapshot <<EOF
# Daily snapshot of ${POOL}/vault (after the 01:30 app backups, before the 03:00 VM backups)
30 2 * * * root /usr/local/sbin/homelab-zfs-snapshot ${POOL}/vault 14
EOF
echo "Installed daily ZFS snapshots (keep 14)."
echo "Next: ./04-create-vms.sh"
