# Minecraft

Paper Minecraft server for me and my friends.

## Overview

| | |
|---|---|
| **Runs on** | Minecraft VM (192.168.1.59) |
| **Deployment** | Docker Compose (`itzg/minecraft-server`, `TYPE=PAPER`) |
| **Memory** | 4 GB for the server (VM has 6 GB) |
| **Port** | 25565 (LAN), friends connect through the playit.gg tunnel |
| **Access control** | Whitelist enforced. Only usernames in `WHITELIST` can join |

## Containers

| Container | Role |
|---|---|
| `minecraft` | The Paper server. World and config in `./data` |
| `minecraft-backups` | `itzg/mc-backup`: once a day pauses saving through RCON, archives the world to `/mnt/backups/minecraft` on the DAS, keeps 14 days |

## Why the whitelist

The playit.gg tunnel makes the server reachable from the whole internet, and bots scan for open Minecraft servers. With `ENFORCE_WHITELIST`, anyone not on the list is kicked straight away.

## playit.gg

The playit agent is a systemd service on the VM (installed by `vm/minecraft-setup.sh` from the official package repo). It keeps an **outbound** connection to playit.gg, so no router ports are opened. Claim it once with `sudo playit setup` and point the tunnel at `127.0.0.1:25565`.

## First start

```bash
cd ~/homelab/services/Minecraft
cp .env.example .env && nano .env      # whitelist, ops, RCON password
docker compose up -d
docker compose logs -f mc              # wait for "Done (...)! For help, type "help""
```

Server console: `docker attach minecraft` (detach with Ctrl+P, Ctrl+Q), or `docker exec minecraft rcon-cli`.

## Restore a world backup

```bash
docker compose stop mc
sudo mv data/world data/world.broken      # likewise world_nether / world_the_end
sudo tar -C data -xzf /mnt/backups/minecraft/world-YYYYMMDD-HHMMSS.tgz
docker compose start mc
```
