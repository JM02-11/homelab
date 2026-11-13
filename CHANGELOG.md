# Changelog

## 2026-11-13: New DAS and ZFS pool rebuild

- Replaced the ORICO MixData Vault Big5 (5 × 960 GB SSD, RAID-Z1) with an ORICO 9958RU3 5-bay enclosure holding 3.5" HDDs, running in Normal (non-RAID) mode.
- Destroyed and recreated the `das` ZFS pool with the same dataset paths (`/das/vault/{photos,media,documents}`), so the Proxmox directory mappings, virtiofs devices and VM mounts are unchanged.
- Reset Immich to a fresh install (new database), since the old photo library was not migrated.
- Jellyfin was reconnected without changes (no libraries had been configured).
- Added the runbook [hardware/das-rebuild.md](hardware/das-rebuild.md).
