# Changelog

## 2026-11-13: Full rebuild

**Storage**
- Replaced the ORICO MixData Vault Big5 (5 × 960 GB SSD, RAID-Z1) with an ORICO 9958RU3 5-bay enclosure in Normal (non-RAID) mode, holding 3 of the old SSDs and 2 × 1 TB WD Blue HDDs.
- Destroyed the old `das` pool (SUSPENDED after the old DAS was removed). Created two pools: `das` (3 SSDs, RAID-Z1) for Nextcloud data, and `bkp` (2 HDDs, mirror) for app backups and VM backups.
- Old directory mappings `photos`, `media`, `documents` removed; new mappings `nextcloud`, `backups`.

**DAS sleep fix**
- The ORICO's Smart Sleep dropped the whole enclosure off USB after ~10 idle minutes, which suspended both pools. Added `proxmox/03b-das-keepalive.sh`: keepalive reads every 2 minutes, USB autosuspend off, boot waits for the drives before importing the pools, and VMs start after the pools.

**VMs**
- Destroyed and recreated both VMs from the Ubuntu 26.04 cloud image with cloud-init (SSH key login, static IPs, same MAC addresses).

**Services**
- Removed Immich and Jellyfin.
- Added Nextcloud, Vaultwarden and AdGuard Home on the Apps VM.
- Minecraft: fresh world, whitelist enforced, automatic daily world backups (`itzg/mc-backup`).

**Security & operations (roadmap items)**
- SSH keys only, no passwords, on the VMs and the host.
- Proxmox firewall turned on: default deny inbound on the host and both VMs.
- Automatic security updates (unattended-upgrades) on both VMs.
- Two-factor (TOTP) on the Proxmox web UI.
- Ad blocking with AdGuard Home for the LAN and tailnet.
- Backups: nightly app backups, daily ZFS snapshots, nightly VM backups to the DAS (no longer on the boot NVMe).

**Repo**
- Added [REBUILD.md](REBUILD.md), `proxmox/` host scripts and firewall rules, `vm/` setup scripts, and Compose files for every service.
