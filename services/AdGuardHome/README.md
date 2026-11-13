# AdGuard Home

Network-wide ad and tracker blocking. Every device on the network uses it as its DNS server, so ads are blocked without installing anything on each device.

## Overview

| | |
|---|---|
| **Runs on** | Apps VM (192.168.1.61) |
| **Deployment** | Docker Compose, pinned version (`ADGUARD_VERSION`, default in the compose file) |
| **DNS** | Port 53 (TCP/UDP), LAN + Tailscale |
| **Admin page** | `http://192.168.1.61:3000` (LAN only) |

## How devices use it

- **At home:** the router (Nighthawk RS90) hands out `192.168.1.61` as the DNS server through DHCP.
- **Away from home:** in the Tailscale admin console under *DNS → Nameservers → Add → Custom*, add the Apps VM's Tailscale IP (`100.x.y.z`) and turn on **Override local DNS**. My phone then gets ad blocking over Tailscale.
- **The VMs and the Proxmox host** use public DNS (1.1.1.1, 9.9.9.9), so a broken AdGuard can't break the servers themselves.

**Tradeoff:** if the Apps VM is down, devices at home lose DNS (web pages won't load). Fix by restarting the VM, or temporarily setting the router's DNS back to automatic. Adding a public secondary DNS on the router avoids this, but devices would then sometimes skip AdGuard and see ads.

## Port 53

Ubuntu's `systemd-resolved` normally listens on port 53. `vm/apps-setup.sh` turns that listener off (`DNSStubListener=no`) so AdGuard can bind it.

## First start

```bash
cd ~/homelab/services/AdGuardHome
docker compose up -d
```
Open `http://192.168.1.61:3000` and go through the wizard:
- Admin web interface: **All interfaces, port 3000.** Port 3000 is the only web port mapped and allowed by the firewall.
- DNS server: All interfaces, port 53.
- Create a strong admin password.

Suggested settings: upstream DNS `https://dns.quad9.net/dns-query` and `https://cloudflare-dns.com/dns-query` (encrypted DNS over HTTPS, so the ISP can't read the queries), with *Parallel requests* on. Keep the default AdGuard DNS filter, and add a couple of filter lists from the built-in list.

## Backups

`./conf` (settings, filters, clients) is archived nightly to `/mnt/backups/adguardhome`. Query logs and stats in `./work` are not backed up.
