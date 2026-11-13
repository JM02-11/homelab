#!/usr/bin/env bash
# Phase 4: create the Apps and Minecraft VMs from the Ubuntu 26.04 cloud image with cloud-init
# (SSH key login, static IP, virtiofs shares, firewall on the NIC).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env

[[ -f "$SSH_PUBKEY_FILE" ]] || { echo "Copy your PC's public key to $SSH_PUBKEY_FILE first (REBUILD.md, phase 0)."; exit 1; }

img_dir=/root/images
img="$img_dir/$(basename "$CLOUD_IMG_URL")"
mkdir -p "$img_dir"
if [[ ! -f "$img" ]]; then
  wget -O "$img" "$CLOUD_IMG_URL"
  sums_url="$(dirname "$CLOUD_IMG_URL")/SHA256SUMS"
  expected=$(wget -qO- "$sums_url" | awk -v f="*$(basename "$img")" '$2==f || $2==substr(f,2) {print $1}')
  actual=$(sha256sum "$img" | awk '{print $1}')
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    rm -f "$img"; echo "Checksum mismatch for the cloud image; aborting."; exit 1
  fi
  echo "Cloud image downloaded and verified."
fi

prefix=${LAN_CIDR#*/}

create_vm() {
  local vmid=$1 name=$2 cores=$3 mem=$4 disk=$5 ip=$6 mac=$7
  shift 7
  if qm status "$vmid" &>/dev/null; then echo "VM $vmid already exists, skipping."; return; fi

  local nic="virtio,bridge=vmbr0,firewall=1"
  [[ -n "$mac" ]] && nic="virtio=${mac},bridge=vmbr0,firewall=1"

  qm create "$vmid" --name "$name" --ostype l26 --machine q35 \
    --cpu host --cores "$cores" --memory "$mem" --balloon 0 \
    --scsihw virtio-scsi-single --net0 "$nic" \
    --agent enabled=1 --serial0 socket --vga serial0 --onboot 1
  qm set "$vmid" --scsi0 "${VM_STORAGE}:0,import-from=${img},discard=on,iothread=1,ssd=1"
  qm disk resize "$vmid" scsi0 "$disk"
  qm set "$vmid" --boot order=scsi0 --ide2 "${VM_STORAGE}:cloudinit"
  qm set "$vmid" --ciuser "$VM_USER" --sshkeys "$SSH_PUBKEY_FILE" --ciupgrade 1 \
    --ipconfig0 "ip=${ip}/${prefix},gw=${GATEWAY}" --nameserver "$VM_DNS"
  # Any extra arguments are passed straight to qm set (virtiofs shares)
  [[ $# -gt 0 ]] && qm set "$vmid" "$@"
  echo "Created VM $vmid ($name) at $ip."
}

create_vm "$APPS_VMID" "$APPS_NAME" "$APPS_CORES" "$APPS_MEM" "$APPS_DISK" "$APPS_IP" "$APPS_MAC" \
  --virtiofs0 dirid=nextcloud --virtiofs1 dirid=backups

create_vm "$MC_VMID" "$MC_NAME" "$MC_CORES" "$MC_MEM" "$MC_DISK" "$MC_IP" "$MC_MAC" \
  --virtiofs0 dirid=backups

echo
echo "VMs created (not started). Next: ./05-firewall.sh, then start them with:"
echo "  qm start ${APPS_VMID} && qm start ${MC_VMID}"
