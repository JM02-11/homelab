#!/usr/bin/env bash
# Run once on EACH new VM:  sudo ./bootstrap.sh
# - installs Docker (Ubuntu packages, so security updates arrive through unattended-upgrades)
# - turns on automatic security updates with a nightly reboot window if needed
# - hardens SSH: key-only, no root login
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
user=${SUDO_USER:-homelab}

# Refuse to lock SSH down unless this user actually has a key installed
if [[ ! -s "/home/$user/.ssh/authorized_keys" ]]; then
  echo "No SSH key in /home/$user/.ssh/authorized_keys; refusing to disable password login."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y full-upgrade
apt-get -y install qemu-guest-agent unattended-upgrades apt-listchanges \
  docker.io docker-compose-v2 git curl ca-certificates sqlite3
systemctl enable --now qemu-guest-agent docker
usermod -aG docker "$user"

# --- Automatic updates ---
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/52homelab-unattended <<'EOF'
// Security updates from the Ubuntu archive (includes docker.io) are installed daily.
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF
systemctl enable --now unattended-upgrades

# --- SSH hardening ---
cat > /etc/ssh/sshd_config.d/10-homelab-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
EOF
sshd -t
systemctl reload ssh

echo "Bootstrap done. Log out and back in so the docker group applies."
