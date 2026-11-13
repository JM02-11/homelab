# Vaultwarden

Self-hosted password manager. It's a lightweight server that works with the official Bitwarden apps and browser extensions.

## Overview

| | |
|---|---|
| **Runs on** | Apps VM (192.168.1.61) |
| **Deployment** | Docker Compose, pinned to an exact version |
| **URL** | `https://apps.<tailnet>.ts.net:8443` (Tailscale only) |
| **Clients** | Bitwarden iOS app, browser extension. Set the server URL to the address above |

## Security choices

- **Not exposed to the LAN or internet.** The container listens on `127.0.0.1:8082` only. Tailscale Serve provides HTTPS, which the Bitwarden clients require:
  ```bash
  sudo tailscale serve --bg --https=8443 http://127.0.0.1:8082
  ```
- **Signups closed** after creating my account (`SIGNUPS_ALLOWED=false`).
- **Admin page disabled** (no `ADMIN_TOKEN`).
- **Turn on two-factor** (authenticator app) for the account in the web vault.
- The vault is end-to-end encrypted with my master password. The server only stores encrypted data.

## Storage & backups

| Data | Location | Protection |
|---|---|---|
| SQLite DB, keys, attachments | `./data` on the VM disk | Nightly `sqlite3 .backup` + tarball → `/mnt/backups/vaultwarden` (14 days), nightly VM backup |

> The Bitwarden apps keep an offline copy of the vault, so a dead server doesn't lock me out. Still, export an encrypted vault backup occasionally (web vault → Tools → Export, *encrypted JSON*) and store it off the homelab.

## First start

```bash
cd ~/homelab/services/Vaultwarden
cp .env.example .env && nano .env         # set TS_FQDN
docker compose up -d
```
Create your account at `https://apps.<tailnet>.ts.net:8443`. Then set `SIGNUPS_ALLOWED=false` and run `docker compose up -d` again.

## Restore

```bash
docker compose down
cp /mnt/backups/vaultwarden/db-YYYY-MM-DD.sqlite3 data/db.sqlite3
tar -C data -xzf /mnt/backups/vaultwarden/files-YYYY-MM-DD.tar.gz
docker compose up -d
```
