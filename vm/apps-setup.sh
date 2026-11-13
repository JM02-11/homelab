#!/usr/bin/env bash
# Run once on the Apps VM after bootstrap.sh:  sudo ./apps-setup.sh
# - mounts the DAS shares (virtiofs): /mnt/nextcloud and /mnt/backups
# - frees port 53 for AdGuard Home
# - installs Tailscale
# - installs the nightly app backup job
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
repo=$(cd "$(dirname "$0")/.." && pwd)
user=${SUDO_USER:-homelab}

# --- virtiofs mounts (the tag is the Proxmox directory mapping ID) ---
for share in nextcloud backups; do
  mkdir -p "/mnt/$share"
  grep -q "^$share " /etc/fstab || echo "$share /mnt/$share virtiofs defaults,nofail 0 0" >> /etc/fstab
done
systemctl daemon-reload
mount -a
findmnt -t virtiofs

# --- Free port 53: stop systemd-resolved's local stub listener, keep it as the VM's resolver ---
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/adguard.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

# --- Tailscale ---
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# --- Nightly app backups to the DAS (01:30) ---
install -m 0755 "$repo/vm/backup-apps.sh" /usr/local/sbin/homelab-backup-apps
cat > /etc/cron.d/homelab-backup-apps <<EOF
30 1 * * * root REPO=$repo /usr/local/sbin/homelab-backup-apps >> /var/log/homelab-backup.log 2>&1
EOF

mkdir -p /mnt/backups/{nextcloud,vaultwarden,adguardhome}
chown -R "$user:$user" /mnt/backups/{nextcloud,vaultwarden,adguardhome}

echo
echo "Apps VM ready. Next:"
echo "  sudo tailscale up            (log in, then disable key expiry for this machine in the admin console)"
echo "  then follow REBUILD.md phase 7 to start AdGuard Home, Vaultwarden and Nextcloud."
