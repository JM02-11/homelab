# Homelab

This is my homelab where  I have a photo server (Immich), a media server (Jellyfin) for movies and TV shows, and a Minecraft server that I play occasionally with my friends. All of the services are running inside Docker containers on two virtual machines. The homelab is based on an HP Prodesk 600 G4 DM and is running Proxmox as the hypervisor. I also have an ORICO DAS (Direct Attached Storage) that has five 960GB drives in it and is configured into RAID-Z which protects against drive failure by spreading the data and parity across all drives making only 3.37 TB usable.

See [hardware/](hardware/README.md) for full specs

## Why I Built This

I built this homelab to develop hands-on skills in networking, security, and self-hosting.

### Networking
- **Remote access with Tailscale:** Immich and Jellyfin are reachable from my phone through their iOS apps over Tailscale, a private VPN, so I can use them away from home.
- **Game server tunneling with playit.gg:** friends on other networks connect to my Minecraft server through a playit.gg tunnel instead of through ports opened to the public.
- **Static IPs:** the Proxmox host and all VMs have static IP addresses, so I can always remote into them without the addresses changing. DHCP reservations through my routers address reservation.
- **Ports:** Immich runs on its default port (2283) and Jellyfin on its default (8096). The official Docker Compose files already map these, so no extra port configuration was needed.

### Security
- **No open ports on my router.** All outside access goes through Tailscale or the playit.gg tunnel, which keeps my network from being directly exposed to attacks from the internet.
- **Why it matters:** a VM exposed to the open internet could be hit by a DDoS attack, or someone could gain unauthorized remote access to it.
- **Unique, strong passwords** for each VM and for the Proxmox hypervisor.

### Self-Hosting
- **Immich and Jellyfin over Google Photos and Plex:** they're free and open source, private to me, and I can allocate as much storage to each as I want.
- **Docker:** each service runs in its own isolated container, even on the same VM, so they don't depend on each other's updates or versions.
- **Two VMs:** apps and game servers are kept separate because they need different resources.
- **Storage:** the ZFS pool on the DAS is shared into the Apps VM with virtiofs, and Docker bind-mounts those folders into the Immich and Jellyfin containers.

### Game Server
- **4 GB of RAM** for the Minecraft server. It runs without mods, and from experience a server needs at least 4 GB. The VM has 6 GB, and 4 GB of that goes to the server, with the rest for the OS.
- **Stability:** no lag or crashes since it went live on October 19, 2026.
- **Next step:** add backup plugin for automatic world backups.

## Roadmap
- [ ] **SSH:** to provide ease of access from my main computer while hardening access by replacing passwords.
- [ ] **Two-factor:** Second layer of security. A stolen password is not enough for access.
- [ ] **Firewall:** allow only the ports to the services I am running, deny all others.
- [ ] **Auto updates:** Keeping everything current which is important in case of security vulnerabilities in previous versions.
- [ ] **Intrusion detection:** Alerts and monitoring in case of intrusion or access from outside my network.
- [ ] **Ad blocking:** Ads annoy me and I don't want to keep getting targeted ads for things I am uninterested in. Also lets me learn more about DNS.
- [ ] **Vulnerability scanning:** Security practice and a way to detect issues with any other step I have set up.
- [ ] **VLAN:** Would like to add to keep my server and main network separate but my router can't do internal VLANs (Nighthawk RS90).
- [ ] **Backups:** Need to add backups for (apps {Immich, Jellyfin})
