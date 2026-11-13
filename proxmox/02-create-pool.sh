#!/usr/bin/env bash
# Phase 2: create the ZFS pool on the ORICO 9958RU3 (Normal/Clear mode) and its datasets.
# Run as root on the Proxmox host after filling in POOL_DISKS in homelab.env.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env

[[ -n "${POOL_DISKS// }" ]] || { echo "Set POOL_DISKS in homelab.env first (see REBUILD.md, phase 2)."; exit 1; }
zpool list "$POOL" &>/dev/null && { echo "Pool '$POOL' already exists. Run 01-teardown.sh first."; exit 1; }

read -r -a disks <<< "$POOL_DISKS"
declare -A seen=()
for d in "${disks[@]}"; do
  [[ "$d" == /dev/disk/by-id/* ]] || { echo "$d is not a /dev/disk/by-id/ path."; exit 1; }
  [[ -e "$d" ]] || { echo "$d does not exist."; exit 1; }
  real=$(readlink -f "$d")
  [[ -z "${seen[$real]:-}" ]] || { echo "$d and ${seen[$real]} are the SAME disk ($real). The enclosure is reporting duplicate IDs; stop and see REBUILD.md."; exit 1; }
  seen[$real]=$d
done

echo "Creating pool '$POOL' as ${POOL_LAYOUT} from ${#disks[@]} drives:"
for d in "${disks[@]}"; do
  echo "  $d -> $(readlink -f "$d") $(lsblk -dno SIZE,MODEL "$(readlink -f "$d")")"
done
echo "ALL DATA ON THESE DRIVES WILL BE ERASED."
read -r -p "Type CREATE to continue: " answer
[[ "$answer" == "CREATE" ]] || { echo "Aborted."; exit 1; }

for d in "${disks[@]}"; do wipefs -a "$d"; done

zpool create -o ashift=12 \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -m "/${POOL}" "$POOL" "$POOL_LAYOUT" "${disks[@]}"

# Import the pool at boot, the same way Proxmox does for pools created in the GUI
systemctl enable "zfs-import@${POOL}.service"

zfs create -p "${POOL}/vault/nextcloud"        # Nextcloud user files
zfs create    "${POOL}/vault/backups"          # nightly app backups (DB dumps, configs, Minecraft world)
zfs create -o recordsize=1M "${POOL}/vzdump"   # Proxmox VM backups (not part of the daily snapshots)

# Nextcloud's container runs as www-data (UID/GID 33) and requires its data folder to be 0770
chown 33:33 "/${POOL}/vault/nextcloud"
chmod 0770  "/${POOL}/vault/nextcloud"
# The VM user (UID 1000) writes the app backups
chown 1000:1000 "/${POOL}/vault/backups"

zpool status "$POOL"
zfs list -r "$POOL"
echo "Pool ready. Next: ./03-storage-mappings-backups.sh"
