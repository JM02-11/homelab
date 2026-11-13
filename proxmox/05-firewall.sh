#!/usr/bin/env bash
# Phase 5: turn on the Proxmox firewall (datacenter, host, and both VMs).
# The rules live in ./firewall/ so they're version-controlled.
#
# If you ever lock yourself out of the web UI, log in at the host's physical console and run:
#   pve-firewall stop
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env

echo "Make sure you are on the LAN (${LAN_CIDR}) before enabling the firewall."
read -r -p "Type FIREWALL to continue: " answer
[[ "$answer" == "FIREWALL" ]] || { echo "Aborted."; exit 1; }

render() { sed -e "s#__LAN__#${LAN_CIDR}#g" "$1"; }

render firewall/host.fw    > "/etc/pve/nodes/${NODE}/host.fw"
render firewall/apps.fw    > "/etc/pve/firewall/${APPS_VMID}.fw"
render firewall/minecraft.fw > "/etc/pve/firewall/${MC_VMID}.fw"
# The datacenter file is written last, because it is the one that switches the firewall on
render firewall/cluster.fw > /etc/pve/firewall/cluster.fw

pve-firewall compile >/dev/null
pve-firewall status
echo "Firewall enabled. Check that https://<host>:8006 still loads in a NEW browser tab."
