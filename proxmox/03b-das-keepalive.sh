#!/usr/bin/env bash
# Phase 3b: keep the ORICO 9958RU3 awake and make boot wait for it.
#
# Why: the enclosure's "Smart Sleep" hibernates after ~10 minutes without disk activity,
# and when it does, the whole enclosure drops off USB. ZFS then suspends both pools,
# and after a reboot the pools can't be imported because the drives aren't there yet.
#
# This installs:
#   1. a udev rule that turns off USB power-saving for the enclosure
#   2. a timer that reads a small random block from every pool drive every 2 minutes
#      (direct I/O, so it really reaches the disks), so the enclosure never sees 10 idle minutes
#   3. a boot step that waits (up to 3 min) for all pool drives before ZFS imports the pools,
#      and makes the VMs start only after the pools are imported
# Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./homelab.env
BKP_POOL=${BKP_POOL:-bkp}
BKP_DISKS=${BKP_DISKS:-}
disks="$POOL_DISKS $BKP_DISKS"

# 1. No USB autosuspend for the JMicron bridge (152d:0567)
cat > /etc/udev/rules.d/50-orico-no-autosuspend.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="152d", ATTR{idProduct}=="0567", TEST=="power/control", ATTR{power/control}="on"
EOF
udevadm control --reload
for d in /sys/bus/usb/devices/*; do
  [[ "$(cat "$d/idVendor" 2>/dev/null)" == 152d ]] && echo on > "$d/power/control"
done

# 2. Keepalive reads
cat > /usr/local/sbin/homelab-das-keepalive <<EOF
#!/usr/bin/env bash
# Read one random 4 KiB block from each DAS drive, bypassing the cache.
for d in $disks; do
  [[ -e "\$d" ]] || continue
  dd if="\$d" of=/dev/null bs=4096 count=1 skip=\$(( (RANDOM << 15 | RANDOM) % 200000000 )) iflag=direct status=none || true
done
EOF
chmod 0755 /usr/local/sbin/homelab-das-keepalive

cat > /etc/systemd/system/homelab-das-keepalive.service <<'EOF'
[Unit]
Description=Keep the ORICO DAS from going to sleep

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/homelab-das-keepalive
EOF
cat > /etc/systemd/system/homelab-das-keepalive.timer <<'EOF'
[Unit]
Description=Keep the ORICO DAS awake (every 2 minutes)

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

# 3. Wait for the drives at boot, then import; start VMs only after the pools exist
cat > /usr/local/sbin/homelab-wait-das <<EOF
#!/usr/bin/env bash
# Wait up to 180 s for every DAS drive to appear (the enclosure can be slow to wake up).
for _ in \$(seq 90); do
  missing=0
  for d in $disks; do [[ -e "\$d" ]] || missing=1; done
  [[ \$missing -eq 0 ]] && exit 0
  sleep 2
done
echo "DAS drives still missing after 180 s" >&2
exit 0   # let the import try anyway, so the error is visible in zpool/journal
EOF
chmod 0755 /usr/local/sbin/homelab-wait-das

for p in "$POOL" "$BKP_POOL"; do
  mkdir -p "/etc/systemd/system/zfs-import@${p}.service.d"
  cat > "/etc/systemd/system/zfs-import@${p}.service.d/wait-for-das.conf" <<'EOF'
[Service]
ExecStartPre=/usr/local/sbin/homelab-wait-das
TimeoutStartSec=240
EOF
  systemctl enable "zfs-import@${p}.service" >/dev/null 2>&1 || true
done

mkdir -p /etc/systemd/system/pve-guests.service.d
cat > /etc/systemd/system/pve-guests.service.d/after-das.conf <<EOF
[Unit]
Wants=zfs-import@${POOL}.service zfs-import@${BKP_POOL}.service
After=zfs-import@${POOL}.service zfs-import@${BKP_POOL}.service zfs-mount.service
EOF

systemctl daemon-reload
systemctl enable --now homelab-das-keepalive.timer
/usr/local/sbin/homelab-das-keepalive
systemctl list-timers homelab-das-keepalive.timer --no-pager
echo "DAS keepalive and boot wait installed."
