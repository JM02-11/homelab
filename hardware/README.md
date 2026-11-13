# Hardware

## Host

| Component | Details |
|---|---|
| **Model** | HP ProDesk 600 G4 DM (Desktop Mini) |
| **CPU** | Intel Core i5-8500T, 6 cores / 6 threads, 35 W TDP |
| **RAM** | 32 GB DDR4 SO-DIMM (2 × 16 GB) |
| **Hypervisor** | Proxmox VE 9.2 |

I chose a mini PC because it runs 24/7 with low power draw, heat, and noise. The i5-8500T is a low-power "T" model, which suits an always-on server.

## Internal Storage

| Drive | Proxmox storage | Holds |
|---|---|---|
| 256 GB NVMe | `local`, `local-lvm` | Proxmox OS, ISO images, container templates, backups |
| 2 TB SATA SSD | `vmdata` (LVM-Thin) | All VM disks |

The operating system, VM disks, and bulk data each live on separate storage. If I need to reinstall Proxmox, my VMs and files are not on that drive. VM disks are thin-provisioned, so each one only uses the space it has actually filled.

## External Storage (DAS)

| Component | Details |
|---|---|
| **Enclosure** | ORICO 5-Bay RAID enclosure (model 9958RU3), set to **Normal/Clear** mode (hardware RAID off) |
| **Connection** | USB-A, USB 3.0 (5 Gbps) |
| **Drives** | TODO: number × model, size (3.5" HDD) |
| **Layout** | ZFS TODO: RAID-Z2 / RAID-Z1 / mirror, managed by Proxmox (`das`) |
| **Capacity** | TODO: raw TB, usable TiB (from `zfs list das`) |

The enclosure supports hardware RAID, but it's set to Normal mode so that each drive shows up separately and ZFS handles the redundancy. ZFS checksums every block, so it can detect and repair silent corruption, which the enclosure's hardware RAID can't. Its "JBOD" or "Span" mode would merge every drive into one disk, so it isn't used.

How the pool was rebuilt is in [das-rebuild.md](das-rebuild.md).

### Previous DAS (retired November 2026)

ORICO MixData Vault Big5 (8858RC3) with 3 × Samsung PM883 and 2 × Toshiba 960 GB SSDs in RAID-Z1 (3.37 TiB usable). Replaced to get more capacity from 3.5" hard drives. The pool was wiped, not migrated.

### Directory Mappings

Folders on the pool are shared into VMs with virtiofs, using Proxmox directory mappings:

| Mapping | Host path |
|---|---|
| `documents` | `/das/vault/documents` |
| `media` | `/das/vault/media` |
| `photos` | `/das/vault/photos` |

## Virtual Machines

| VM | vCPUs | RAM | Disk | OS | Purpose |
|---|---|---|---|---|---|
| **Apps** | 4 | 16 GB | 120 GB | Ubuntu Server 26.04.1 LTS | Immich, Jellyfin (Docker) |
| **Minecraft** | 2 | 6 GB | 40 GB | Ubuntu Server 26.04.1 LTS | Paper Minecraft server (Docker, 4 GB allocated to the server) |

All 6 cores are assigned. Proxmox lets VMs share CPU time, and they rarely run at full load at once. About 10 GB of RAM is left unassigned for Proxmox itself and the ZFS cache (ARC).

## Storage Flow

```mermaid
graph LR
    DAS["ORICO 9958RU3 DAS<br/>3.5 in. HDDs"] --> ZFS["ZFS pool das<br/>(Proxmox host)"]
    ZFS -- "virtiofs<br/>(directory mappings)" --> VM["Apps VM"]
    VM -- bind mounts --> Immich["Immich<br/>(photos)"]
    VM -- bind mounts --> Jellyfin["Jellyfin<br/>(media)"]
```

## Known Limitations

- **ZFS over USB:** USB-to-SATA adapters can briefly disconnect drives, which ZFS may treat as failures, and can hide drive health data (SMART needs `smartctl -d sat`). All drives also share a single 5 Gbps link. Some ORICO multi-bay enclosures report duplicate disk IDs, so check `zpool status` after every host reboot. A future upgrade would be a SATA or SAS controller (HBA) in a machine with drive bays.
- **Drive sleep:** the 9958RU3 spins its drives down after about 10 minutes idle, so the first access after a pause is slow.
- **Backups on the boot drive:** Proxmox backups go to `local` on the same NVMe as the OS. If that drive fails, the OS and its backups are lost together.
- **RAID is not a backup:** RAID-Z protects against a drive failure, but not against accidental deletion, corruption from software, or ransomware. My photos need a separate backup copy.
- **All CPU cores assigned:** fine at current load, but heavy use on both VMs at once could slow them down.