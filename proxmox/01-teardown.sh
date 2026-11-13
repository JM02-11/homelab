#!/usr/bin/env bash
# Phase 1: wipe the old setup on the Proxmox host.
#   - saves the old VM configs and MAC addresses
#   - destroys VMs 100 and 101 and their disks
#   - removes the old `das` pool (including a SUSPENDED pool whose DAS is gone)
#   - removes the old directory mappings (photos, media, documents)
# Run as root on the Proxmox host:  ./01-teardown.sh
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env

echo "This PERMANENTLY deletes VM ${APPS_VMID} (${APPS_NAME}), VM ${MC_VMID} (${MC_NAME}),"
echo "the ZFS pool '${POOL}', and the photos/media/documents directory mappings."
read -r -p "Type WIPE to continue: " answer
[[ "$answer" == "WIPE" ]] || { echo "Aborted."; exit 1; }

saved="/root/homelab-teardown-$(date +%F-%H%M)"
mkdir -p "$saved"
cp /etc/pve/storage.cfg "$saved/"
[[ -f /etc/pve/mapping/directory.cfg ]] && cp /etc/pve/mapping/directory.cfg "$saved/"

for vmid in "$APPS_VMID" "$MC_VMID"; do
  if qm status "$vmid" &>/dev/null; then
    qm config "$vmid" > "$saved/$vmid.conf"
    mac=$(qm config "$vmid" | sed -n 's/^net0: [a-z0-9]*=\([0-9A-Fa-f:]*\),.*/\1/p')
    echo "VM $vmid MAC: ${mac:-unknown}  (put this in homelab.env so the router reservation keeps working)"
    qm stop "$vmid" --skiplock 1 &>/dev/null || true
    qm destroy "$vmid" --purge 1 --destroy-unreferenced-disks 1
    echo "VM $vmid destroyed."
  else
    echo "VM $vmid does not exist, skipping."
  fi
done

# Warn about any directory storage that lives on the pool (e.g. 'backups')
awk -v pool="/${POOL}" '
  /^[a-z]+: / {type=$1; name=$2}
  /^[[:space:]]+path / && ($2 == pool || index($2, pool "/") == 1) {print name}
' /etc/pve/storage.cfg | while read -r st; do
  echo "Storage '$st' points into /${POOL}; removing it from the storage config."
  pvesm remove "$st"
done

# (read storage.cfg directly: 'pvesm status' can hang while a storage sits on a SUSPENDED pool)
if grep -qE "^[a-z]+: ${POOL}\$" /etc/pve/storage.cfg; then
  pvesm remove "$POOL"
  echo "Removed Proxmox storage entry '$POOL'."
fi

if zpool list "$POOL" &>/dev/null; then
  echo "Destroying pool '$POOL'. If this hangs for more than a minute, press Ctrl+C,"
  echo "unplug the old DAS (if still attached), reboot the host, and re-run this script."
  zpool destroy -f "$POOL"
fi
systemctl disable "zfs-import@${POOL}.service" &>/dev/null || true
if [[ -d "/${POOL}" ]] && ! mountpoint -q "/${POOL}"; then
  rm -rf "/${POOL:?}"
fi

for id in photos media documents; do
  if pvesh get "/cluster/mapping/dir/$id" &>/dev/null; then
    pvesh delete "/cluster/mapping/dir/$id"
    echo "Removed directory mapping '$id'."
  fi
done

echo
echo "Teardown done. Old configs saved in $saved"
echo "Check: 'zpool list' should not show '$POOL', and 'qm list' should not show VMs ${APPS_VMID}/${MC_VMID}."
