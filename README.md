# Homelab

My homelab runs a file and calendar server (Nextcloud), a password manager (Vaultwarden), network-wide ad blocking (AdGuard Home), and a Minecraft server I play occasionally with friends. Every service runs in a Docker container on one of two virtual machines. The host is an HP ProDesk 600 G4 DM running Proxmox as the hypervisor. Bulk storage is an ORICO 9958RU3 DAS (Direct Attached Storage) with two ZFS pools: three SSDs in RAID-Z1 for data, and two hard drives mirrored for backups. Each pool survives a drive failure, and the backups never share a drive with the data.

The whole setup can be rebuilt from this repo: see **[REBUILD.md](REBUILD.md)**.

| Folder | Contents |
|---|---|
| [hardware/](hardware/README.md) | Host, DAS, VM specs |
| [network/](network/README.md) | IP plan, Tailscale, DNS, firewall |
| [proxmox/](proxmox/) | Host scripts: teardown, ZFS pool, mappings, VMs, firewall rules, backups |
| [vm/](vm/) | VM setup scripts: Docker, auto-updates, SSH hardening, mounts, app backups |
| [services/](services/) | Docker Compose files + docs for each service |

## Services

| Service | VM | What it replaces | Reached via |
|---|---|---|---|
| [Nextcloud](services/Nextcloud/README.md) | Apps | Google Drive / Dropbox | Tailscale (HTTPS) |
| [Vaultwarden](services/Vaultwarden/README.md) | Apps | Bitwarden / 1Password cloud | Tailscale (HTTPS) |
| [AdGuard Home](services/AdGuardHome/README.md) | Apps | Ads and trackers on every device | LAN DNS + Tailscale DNS |
| [Minecraft](services/Minecraft/README.md) | Minecraft | Paid server hosting | LAN + playit.gg tunnel |

## Why I Built This

I built this homelab to develop hands-on skills in networking, security, and self-hosting.

### Networking
- **Remote access with Tailscale:** my phone and PC reach Nextcloud and Vaultwarden over Tailscale, a private VPN. **Tailscale Serve** gives them real HTTPS certificates without exposing anything to the internet.
- **DNS:** AdGuard Home is the DNS server for the LAN (handed out by the router) and for my tailnet, so ads are blocked at home and away.
- **Game server tunneling with playit.gg:** friends on other networks connect through a playit.gg tunnel instead of ports opened to the public.
- **Static IPs:** the host and VMs have fixed addresses (cloud-init static IPs, matching DHCP reservations on the router).

### Security
- **No open ports on my router.** All outside access goes through Tailscale or the outbound playit.gg tunnel.
- **Proxmox firewall:** inbound traffic to the host and both VMs is denied by default. Only the needed ports are allowed, and only from the LAN (rules in [proxmox/firewall/](proxmox/firewall/)).
- **SSH keys only:** password login is disabled on the VMs and the host, and root can't log in to the VMs.
- **Two-factor** on the Proxmox web UI and the Vaultwarden account.
- **Automatic security updates** on both VMs (unattended-upgrades), with a 04:30 reboot window when one is needed.
- **Least exposure:** Nextcloud and Vaultwarden listen only on `127.0.0.1` inside the VM, so they aren't reachable from the LAN at all. The Minecraft server enforces a whitelist.
- **Unique, strong passwords** for each VM user, service, and the Proxmox hypervisor.

### Self-Hosting
- **Docker:** each service runs in its own isolated container, with versions pinned so updates are deliberate.
- **Two VMs:** apps and the game server are kept separate because they need different resources.
- **Storage:** data on an SSD pool and backups on a separate HDD pool. ZFS datasets are shared into the VMs with virtiofs. Databases stay on the VMs' local SSD, because they shouldn't run on shared filesystems.

### Backups

| Layer | What | When | Kept |
|---|---|---|---|
| App backups | Nextcloud DB dump + config, Vaultwarden DB + keys, AdGuard config, Minecraft world | 01:30 nightly (Minecraft daily) | 14 days |
| ZFS snapshots | `das/vault` (Nextcloud files) | 02:30 daily | 14 days |
| VM backups | Both VMs (vzdump to `bkp-vzdump`) | 03:00 nightly | 7 daily, 4 weekly, 3 monthly |

### Game Server
- **4 GB of RAM** for the Paper server out of the VM's 6 GB.
- **Whitelist enforced**, because the playit.gg tunnel makes it reachable from anywhere.
- **Automatic world backups** with `itzg/mc-backup`.

## Roadmap
- [x] **SSH:** key-only access from my main computer
- [x] **Two-factor:** Proxmox web UI (TOTP) and Vaultwarden
- [x] **Firewall:** Proxmox firewall, default deny, only service ports open
- [x] **Auto updates:** unattended-upgrades on both VMs
- [x] **Ad blocking:** AdGuard Home for the LAN and tailnet
- [x] **Backups:** app backups, ZFS snapshots, and VM backups on the DAS
- [ ] **Off-site backup:** everything is still in one house. Next: an encrypted copy off-site (USB drive kept elsewhere, or restic to cloud storage)
- [ ] **Intrusion detection:** alerts if something unexpected logs in or scans the network
- [ ] **Vulnerability scanning:** scan the VMs and container images regularly
- [ ] **VLAN:** separate servers from personal devices. The RS90 can't do internal VLANs, so this needs a managed switch
