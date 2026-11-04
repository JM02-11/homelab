# Immich

Self-hosted photo and video backup: a private replacement for Google Photos.

## Overview

| | |
|---|---|
| **Runs on** | Apps VM (192.168.1.61) |
| **Deployment** | Docker Compose (official compose file, unmodified) |
| **Version** | Pinned to major version v3 |
| **Port** | 2283 |
| **Access** | LAN, and Tailscale from my phone (iOS app) |
| **Users** | Just me |

## Containers

| Container | Role |
|---|---|
| `immich_server` | Web app and API that the iOS app connects to |
| `immich_machine_learning` | Face recognition and smart search |
| `immich_redis` | Job queue (Valkey, an open-source fork of Redis) |
| `immich_postgres` | PostgreSQL 14 database with vector extensions, storing albums, users, metadata, and faces |

## Storage

| Data | Location | Protection |
|---|---|---|
| Photos & videos | `/mnt/photos` → DAS via virtiofs | RAID-Z1 |
| Nightly database backups | `/mnt/photos/backups` (last 14 kept) | RAID-Z1 |
| Live database | `./postgres` on the VM disk | None (backed up nightly to the DAS) |
| ML model cache | Docker volume `model-cache` | Not needed; re-downloads automatically |

The live database stays on the VM's local disk on purpose: Immich doesn't support running its database on a network or shared filesystem, and doing so risks corruption. Immich dumps the database to the DAS every night at 2:00 AM.

## Configuration Notes

- **Version pinned to `v3`:** updates bring bug fixes and minor releases, but never an automatic jump to a new major version that could include breaking changes.
- **Image digests:** the database and Redis images are pinned by `sha256` digest, so Docker always pulls the exact same build.
- **Data checksums** are enabled in Postgres to detect database corruption.
- **Secrets:** the real `.env` is not committed. See [`.env.example`](.env.example).

## Updating

Not yet updated since installation. Planned procedure:

1. Read the release notes for breaking changes.
2. Confirm a recent database backup exists in `/mnt/photos/backups`.
3. `docker compose pull`
4. `docker compose up -d`
5. Confirm all four containers report healthy with `docker ps`.

## Current Status & Next Steps

- [ ] Turn on automatic backup in the iOS app (currently off)
- [ ] Test restoring from a database backup
- [ ] Keep a second copy of photos off the DAS (RAID is not a backup)
- [ ] Hardware transcoding with Intel Quick Sync (requires GPU passthrough to the VM)