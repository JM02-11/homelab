# Nextcloud

Self-hosted file sync and sharing: a private alternative to Google Drive or Dropbox, with calendar and contacts.

## Overview

| | |
|---|---|
| **Runs on** | Apps VM (192.168.1.61) |
| **Deployment** | Docker Compose (`nextcloud:<major>-apache`, Postgres 17, Valkey) |
| **Version** | Pinned to a major version (`NEXTCLOUD_VERSION` in `.env`) |
| **URL** | `https://apps.<tailnet>.ts.net` (Tailscale only) |
| **Clients** | iOS app, desktop sync client (both need Tailscale running) |

## Containers

| Container | Role |
|---|---|
| `nextcloud` | Web app + WebDAV API (Apache) on `127.0.0.1:8081` |
| `nextcloud-cron` | Runs background jobs every 5 minutes |
| `nextcloud-db` | PostgreSQL 17 database |
| `nextcloud-redis` | Cache and file locking (Valkey, an open-source Redis fork) |

## Storage

| Data | Location | Protection |
|---|---|---|
| User files | `/mnt/nextcloud` → DAS (`das/vault/nextcloud`) via virtiofs | ZFS redundancy + daily snapshots (14 days) |
| Database | `./db` on the VM disk | Nightly `pg_dump` → `/mnt/backups/nextcloud`, nightly VM backup |
| App code + config | `./html` on the VM disk | Nightly config tarball, nightly VM backup |

The database stays on the VM's local disk because databases should not run on a shared filesystem like virtiofs. The user files are owned by UID 33 (`www-data` inside the container) on the host, and Nextcloud requires that folder to be mode `0770`. `02-create-pool.sh` sets both.

## How it's reached

The container only listens on `127.0.0.1`. **Tailscale Serve** puts HTTPS in front of it with a real certificate for the VM's tailnet name:

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:8081
```

This keeps Nextcloud off the LAN and off the internet entirely. Any device that should sync files needs Tailscale installed.

## First start

```bash
cd ~/homelab/services/Nextcloud
cp .env.example .env && nano .env      # set TS_FQDN and passwords
docker compose up -d
docker compose logs -f app             # wait for "apache2 -D FOREGROUND"
```

Then open `https://apps.<tailnet>.ts.net` and log in with the admin account from `.env`. Afterwards, clear `NEXTCLOUD_ADMIN_PASSWORD` from `.env` (it's only used once).

Useful `occ` commands:

```bash
docker exec -u www-data nextcloud php occ status
docker exec -u www-data nextcloud php occ background:cron     # use the cron container
docker exec -u www-data nextcloud php occ db:add-missing-indices
```

## Updating

1. Read the release notes.
2. Confirm last night's dump exists in `/mnt/backups/nextcloud`.
3. Patch releases: `docker compose pull && docker compose up -d`.
4. New major: raise `NEXTCLOUD_VERSION` by **one** major at a time (Nextcloud can't skip majors), then pull and start.

## Restore

```bash
docker compose stop app cron
gunzip -c /mnt/backups/nextcloud/db-YYYY-MM-DD.sql.gz | docker exec -i nextcloud-db psql -U nextcloud -d nextcloud
docker compose start app cron
docker exec -u www-data nextcloud php occ files:scan --all
```
