# Jellyfin

Self-hosted media server for movies and TV shows: a private alternative to Plex or streaming services.

## Overview

| | |
|---|---|
| **Runs on** | Apps VM (192.168.1.61) |
| **Deployment** | Docker Compose |
| **Version** | 12.2 |
| **Port** | 8096 |
| **Access** | LAN, and Tailscale from my phone (iOS app) |
| **Status** | Installed; no libraries configured yet |

## Storage

| Data | Location | Protection |
|---|---|---|
| Media library | `/mnt/media` → DAS via virtiofs | RAID-Z1 |
| Settings & metadata | `./config` on the VM disk | None |
| Cache | `./cache` on the VM disk | Not needed; rebuilt automatically |

## Configuration Notes

- **Runs as a non-root user (`1000:1000`):** if Jellyfin were compromised, an attacker would have my regular user's permissions, not root's.
- **Host networking (`network_mode: host`):** the container shares the VM's network instead of mapping ports, so Jellyfin listens on port 8096 directly. Jellyfin recommends this so features like automatic discovery on the LAN work. The tradeoff is less network isolation for the container.
- **Firewall note:** because host-mode containers don't publish ports through Docker, a host firewall like ufw *does* apply to Jellyfin, unlike containers with mapped ports, which bypass it.
- **Restart policy `unless-stopped`:** restarts automatically after crashes or reboots, but not if I stopped it on purpose.

## Next Steps

- [ ] Add a first movie or show, and confirm `/mnt/media` grows on the DAS and that user 1000 can read the files through virtiofs
- [ ] Set up Movies and TV Shows libraries
- [ ] Pin the image to a specific version instead of `latest`, to match how Immich is pinned
- [ ] Mount media read-only (`/mnt/media:/media:ro`), since Jellyfin only needs to read it
- [ ] Back up `./config`, which holds settings, users, and watch history
- [ ] Hardware transcoding with Intel Quick Sync (requires GPU passthrough to the VM)