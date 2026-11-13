#!/usr/bin/env bash
# Phase 2: create the two ZFS pools on the ORICO 9958RU3 (Normal/Clear mode):
#   das  - the SSDs  (POOL_DISKS, POOL_LAYOUT)   -> Nextcloud data
#   bkp  - the HDDs  (BKP_DISKS,  BKP_LAYOUT)    -> app backups + Proxmox VM backups
# Keeping backups on different drives means a dead data drive can't take the backups with it.
# Run as root on the Proxmox host after filling in the disk lists in homelab.env.
#   ./02-create-pool.sh          create both pools
#   ./02-create-pool.sh das      create only the data pool (e.g. after swapping its drives)
#   ./02-create-pool.sh bkp      create only the backup pool
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env
# Defaults for homelab.env files made before the backup pool existed
BKP_POOL=${BKP_POOL:-bkp}
BKP_LAYOUT=${BKP_LAYOUT:-mirror}
BKP_DISKS=${BKP_DISKS:-}

declare -A seen=()

check_disks() {   # name, "disk list"
  local name=$1 list=$2 d real
  [[ -n "${list// }" ]] || { echo "Set the disk list for '$name' in homelab.env first (see REBUILD.md, phase 2)."; exit 1; }
  zpool list "$name" &>/dev/null && { echo "Pool '$name' already exists. Run 01-teardown.sh first."; exit 1; }
  for d in $list; do
    [[ "$d" == /dev/disk/by-id/* ]] || { echo "$d is not a /dev/disk/by-id/ path."; exit 1; }
    [[ -e "$d" ]] || { echo "$d does not exist."; exit 1; }
    real=$(readlink -f "$d")
    [[ -z "${seen[$real]:-}" ]] || { echo "$d and ${seen[$real]} are the SAME disk ($real). Duplicate IDs; stop and see REBUILD.md."; exit 1; }
    seen[$real]=$d
  done
}

show() {   # name, layout, "disk list"
  local d
  echo "Pool '$1' as $2:"
  for d in $3; do
    echo "  $d -> $(readlink -f "$d") $(lsblk -dno SIZE,MODEL "$(readlink -f "$d")")"
  done
}

wipe() {   # clear old ZFS labels (the reused SSDs still carry the old 'das' pool) and partition tables
  local d p
  for d in "$@"; do
    for p in "$d"-part*; do
      [[ -e "$p" ]] || continue
      zpool labelclear -f "$p" 2>/dev/null || true
      wipefs -a "$p"
    done
    wipefs -a "$d"
    sgdisk --zap-all "$d" >/dev/null
  done
  udevadm settle
}

create_pool() {   # name, layout, extra -o options, "disk list"
  local name=$1 layout=$2 extra=$3 disks
  read -r -a disks <<< "$4"
  wipe "${disks[@]}"
  # -f: the drives differ slightly in size (894 GiB SSDs vs 931 GiB HDDs), which zpool otherwise refuses
  # shellcheck disable=SC2086
  zpool create -f -o ashift=12 $extra \
    -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
    -m "/${name}" "$name" "$layout" "${disks[@]}"
  # Import at boot, the same way Proxmox does for pools created in the GUI
  systemctl enable "zfs-import@${name}.service"
}

want=("$@"); [[ ${#want[@]} -gt 0 ]] || want=("$POOL" "$BKP_POOL")
do_data=0; do_bkp=0
for w in "${want[@]}"; do
  case "$w" in
    "$POOL") do_data=1 ;;
    "$BKP_POOL") do_bkp=1 ;;
    *) echo "Unknown pool '$w' (expected '$POOL' or '$BKP_POOL')."; exit 1 ;;
  esac
done

[[ $do_data -eq 1 ]] && check_disks "$POOL" "$POOL_DISKS"
[[ $do_bkp  -eq 1 ]] && check_disks "$BKP_POOL" "$BKP_DISKS"

[[ $do_data -eq 1 ]] && show "$POOL" "$POOL_LAYOUT" "$POOL_DISKS"
[[ $do_bkp  -eq 1 ]] && show "$BKP_POOL" "$BKP_LAYOUT" "$BKP_DISKS"
echo "ALL DATA ON THESE DRIVES WILL BE ERASED."
read -r -p "Type CREATE to continue: " answer
[[ "$answer" == "CREATE" ]] || { echo "Aborted."; exit 1; }

# No autotrim: the Toshiba THNSF8960PCSE SSDs hang on TRIM, and a hung drive makes the enclosure's
# JMicron bridge reset and drop every drive. This suspended both pools during the first rebuild.
if [[ $do_data -eq 1 ]]; then
  create_pool "$POOL" "$POOL_LAYOUT" "-o autotrim=off" "$POOL_DISKS"
  zfs create -p "${POOL}/vault/nextcloud"           # Nextcloud user files
  # Nextcloud's container runs as www-data (UID/GID 33) and requires its data folder to be 0770
  chown 33:33 "/${POOL}/vault/nextcloud"
  chmod 0770  "/${POOL}/vault/nextcloud"
fi

if [[ $do_bkp -eq 1 ]]; then
  create_pool "$BKP_POOL" "$BKP_LAYOUT" "" "$BKP_DISKS"
  zfs create    "${BKP_POOL}/apps"                  # nightly app backups (DB dumps, configs, Minecraft world)
  zfs create -o recordsize=1M "${BKP_POOL}/vzdump"  # Proxmox VM backups
  chown 1000:1000 "/${BKP_POOL}/apps"               # the VM user (UID 1000) writes the app backups
fi

zpool status
zfs list
echo "Pools ready. Next: ./03-storage-mappings-backups.sh"
