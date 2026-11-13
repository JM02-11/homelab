#!/usr/bin/env bash
# Run once on the Minecraft VM after bootstrap.sh:  sudo ./minecraft-setup.sh
# - mounts the DAS backups share at /mnt/backups (world backups go to /mnt/backups/minecraft)
# - installs the playit.gg agent as a systemd service
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
user=${SUDO_USER:-homelab}

mkdir -p /mnt/backups
grep -q "^backups " /etc/fstab || echo "backups /mnt/backups virtiofs defaults,nofail 0 0" >> /etc/fstab
systemctl daemon-reload
mount -a
mkdir -p /mnt/backups/minecraft
chown "$user:$user" /mnt/backups/minecraft

# playit.gg agent from the official package repository (packages.playit.gg)
if ! command -v playit >/dev/null; then
  curl -SsL https://packages.playit.gg/keys/playit.gpg | gpg --dearmor > /usr/share/keyrings/playit.gpg
  chmod 0644 /usr/share/keyrings/playit.gpg
  curl -fsSL -o /etc/apt/sources.list.d/playit.list https://packages.playit.gg/repo-files/playit-debian.list
  apt-get update
  apt-get -y install playit
fi
systemctl enable --now playit

echo
echo "Minecraft VM ready. Next:"
echo "  sudo playit setup      (claim this agent on your playit.gg account; point the tunnel at 127.0.0.1:25565)"
echo "  then follow REBUILD.md phase 8 to start the server."
