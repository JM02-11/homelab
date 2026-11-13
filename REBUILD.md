# Rebuild Runbook

How to rebuild the homelab from a working Proxmox host. This is the procedure used in November 2026, when I:

- replaced the ORICO Big5 SSD DAS with an **ORICO 9958RU3** holding 3.5" HDDs and created a new ZFS pool
- wiped both VMs and recreated them from the Ubuntu 26.04 cloud image
- replaced Immich + Jellyfin with **Nextcloud, Vaultwarden and AdGuard Home**
- started a fresh Minecraft world
- added SSH keys, the Proxmox firewall, automatic updates and backups

Everything is scripted. Settings live in one file, `proxmox/homelab.env`. Destructive scripts ask you to type a confirmation word.

| Phase | Where | What |
|---|---|---|
| 0 | My PC + Tailscale admin | SSH key, Tailscale prep, repo on the host |
| 1 | Proxmox host | `01-teardown.sh`: delete old VMs, pool, mappings |
| 2 | DAS + host | Enclosure in Normal mode, `02-create-pool.sh` |
| 3 | Proxmox host | `03-storage-mappings-backups.sh` |
| 4 | Proxmox host | `04-create-vms.sh` |
| 5 | Proxmox host | `05-firewall.sh` |
| 6 | Both VMs | `vm/bootstrap.sh` |
| 7 | Apps VM | Tailscale, AdGuard Home, Vaultwarden, Nextcloud |
| 8 | Minecraft VM | playit.gg, Minecraft |
| 9 | Proxmox host | Host SSH keys + two-factor login |
| 10 | Everywhere | Verify, test backups, reboot test |

---

## Phase 0: Prep

**On my PC (Windows PowerShell):**

```powershell
mkdir -Force $env:USERPROFILE\.ssh
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\homelab_ed25519" -C "homelab"
scp "$env:USERPROFILE\.ssh\homelab_ed25519.pub" root@192.168.1.81:/root/homelab_ed25519.pub
```

(PowerShell doesn't expand `~` for `ssh-keygen`, so use `$env:USERPROFILE`. On Linux or macOS, use `~/.ssh/...` instead.)

Create the SSH config file (`notepad $env:USERPROFILE\.ssh\config`) so `ssh apps` / `ssh minecraft` / `ssh pve` just work. Inside this file `~` is fine, because ssh expands it itself:

```
Host pve
  HostName 192.168.1.81
  User root
  IdentityFile ~/.ssh/homelab_ed25519
Host apps
  HostName 192.168.1.61
  User homelab
  IdentityFile ~/.ssh/homelab_ed25519
Host minecraft
  HostName 192.168.1.59
  User homelab
  IdentityFile ~/.ssh/homelab_ed25519
```

**In the Tailscale admin console** (login.tailscale.com):
- *Machines:* remove the old `apps` machine, so the new VM can take the name `apps`.
- *DNS:* make sure **MagicDNS** is on, and turn on **HTTPS Certificates**. Tailscale Serve needs both.
- Install Tailscale on my PC too. Nextcloud and Vaultwarden are only reachable over Tailscale.

**On the Proxmox host** (web UI → *pve → Shell*):

```bash
apt update && apt install -y git
git clone https://github.com/JM02-11/homelab /root/homelab
cd /root/homelab/proxmox
cp homelab.env.example homelab.env
nano homelab.env          # check every value; POOL_DISKS and the MACs come later
```

## Phase 1: Tear down the old setup

```bash
cd /root/homelab/proxmox && chmod +x *.sh
./01-teardown.sh
```

This saves the old VM configs to `/root/homelab-teardown-<date>/`, prints each VM's **MAC address**, destroys VMs 100 and 101, removes the old (SUSPENDED) `das` pool and any storage on it (such as `backups`), and deletes the `photos`/`media`/`documents` mappings.

- **Copy the two MAC addresses** into `APPS_MAC` / `MC_MAC` in `homelab.env`. The new VMs then keep the same MACs, so the router's DHCP reservations still match. The VMs also get static IPs from cloud-init, so this is a backup.
- **If the script prints nothing or a VM won't stop:** a backup job that was writing to the old DAS is probably frozen and holding the VM's lock (look for a *Backup Job* that never finishes in the task log). Reboot the host. If it won't shut down within ~5 minutes, hold the power button. Then run `qm unlock 100; qm unlock 101` and run the script again.
- **If `zpool destroy` hangs** (the old DAS is gone and the pool is SUSPENDED): press Ctrl+C. If it won't stop, reboot the host; with the old drives gone, the pool won't import again. Then run `./01-teardown.sh` again. It skips anything already done.

Check: `qm list` shows no VMs, `zpool list` shows no `das`, and `cat /etc/pve/storage.cfg` has nothing pointing at `/das`.

## Phase 2: The new DAS and ZFS pool

### 2a. Put the ORICO 9958RU3 in Normal mode

The 9958RU3 is a hardware RAID enclosure. ZFS needs to see each drive individually, so use **Normal/Clear** mode, **not** RAID 5, and **not** "JBOD"/"Span (Big)" (those merge all drives into one).

1. Enclosure **off**. Install the 3.5" drives. Note which serial number is in which bay.
2. Rear DIP switches for **Normal/Clear: 1 = ON, 2 = OFF, 3 = ON, 4 = OFF**.
3. Hold **SET** while turning the power on, until it beeps or the LEDs confirm.
4. Connect to the ProDesk's USB 3.0 port.

Notes: the enclosure spins drives down after ~10 minutes idle (the first access after that is slow). In Normal mode, inserting or removing a drive can briefly disconnect the **other** drives, so only change drives with the enclosure powered off.

### 2b. Identify and check the drives

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN         # new drives show TRAN=usb
ls -l /dev/disk/by-id/ | grep -v part
for d in /dev/sdX /dev/sdY; do smartctl -d sat -H -A "$d" | grep -E 'overall|Reallocated|Pending|Uncorrect'; done
```

Each drive needs **its own unique** `/dev/disk/by-id/` name. Some ORICO multi-bay USB enclosures report duplicate or missing IDs, which makes ZFS show a disk as FAULTED after a reboot. `02-create-pool.sh` refuses to continue if two IDs point at the same disk. If a drive has no by-id name at all, stop and check `ls -l /dev/disk/by-path/` before going on.

Put the by-id paths into `POOL_DISKS` in `homelab.env`, and pick `POOL_LAYOUT`:

| Drives | Layout | Survives | Usable (N drives of size S) |
|---|---|---|---|
| 2 | `mirror` | 1 failure | S |
| 3–4 | `raidz1` | 1 failure | (N−1) × S |
| 5 | `raidz2` **(recommended)** | 2 failures | 3 × S |

Rebuilding a large HDD takes many hours, and a USB hiccup during that window could take out a second drive, so RAID-Z2 is worth the space with 5 drives.

### 2c. Create the pool

```bash
./02-create-pool.sh
```

This creates pool `das` (`ashift=12`, `lz4`, `atime=off`) with three datasets:

| Dataset | Mounted at | Used for |
|---|---|---|
| `das/vault/nextcloud` | `/das/vault/nextcloud` | Nextcloud user files (owner UID 33, mode 0770) |
| `das/vault/backups` | `/das/vault/backups` | Nightly app backups + Minecraft world backups (owner UID 1000) |
| `das/vzdump` | `/das/vzdump` | Proxmox VM backups |

## Phase 3: Mappings, backup storage, snapshots

```bash
./03-storage-mappings-backups.sh
```

- Directory mappings `nextcloud` and `backups` (shared into VMs with virtiofs)
- Storage `das-vzdump` plus a nightly **03:00** backup job for both VMs (keeps 7 daily, 4 weekly, 3 monthly)
- Daily **02:30** recursive snapshots of `das/vault` (keeps 14)

## Phase 4: Create the VMs

```bash
./04-create-vms.sh
```

This downloads and checksum-verifies the Ubuntu 26.04 cloud image, then creates:

| VM | vCPU | RAM | Disk | IP | Shares |
|---|---|---|---|---|---|
| 100 `apps` | 4 | 16 GB | 120 GB | 192.168.1.61 | `nextcloud`, `backups` |
| 101 `minecraft` | 2 | 6 GB | 40 GB | 192.168.1.59 | `backups` |

Cloud-init creates user `homelab` (UID 1000) with only my SSH key; there is no password. The firewall is turned on for each VM's network card.

## Phase 5: Firewall

```bash
./05-firewall.sh
qm start 100 && qm start 101
```

Rules are in `proxmox/firewall/`. Inbound is denied by default. Allowed:

| Target | Allowed in (from LAN unless noted) |
|---|---|
| Proxmox host | 8006 (web UI), 22, ping |
| Apps VM | 22, ping, 53 (DNS), 3000 (AdGuard admin), UDP 41641 from anywhere (Tailscale) |
| Minecraft VM | 22, ping, 25565 |

Open the web UI in a **new** tab to confirm you still have access. If you're locked out: at the host's physical console, run `pve-firewall stop`.

## Phase 6: Bootstrap both VMs

From the PC, for each VM (`ssh apps`, then `ssh minecraft`):

```bash
cloud-init status --wait                     # first boot runs updates; wait for "done"
git clone https://github.com/JM02-11/homelab ~/homelab
sudo ~/homelab/vm/bootstrap.sh
exit                                         # log back in so the docker group applies
```

`bootstrap.sh` installs Docker, qemu-guest-agent and unattended-upgrades (daily security updates, reboot at 04:30 if one is needed). It also locks SSH to keys only, with no root login.

## Phase 7: Apps VM

```bash
ssh apps
sudo ~/homelab/vm/apps-setup.sh              # virtiofs mounts, frees port 53, Tailscale, backup cron
sudo tailscale up                            # log in; then in the admin console: disable key expiry for 'apps'
tailscale status                             # note the name, e.g. apps.tail1234.ts.net, and the 100.x IP
```

**AdGuard Home** (see `services/AdGuardHome/README.md`):

```bash
cd ~/homelab/services/AdGuardHome && docker compose up -d
```
Run the wizard at `http://192.168.1.61:3000` (admin interface on port **3000**). Then:
- **Router (Nighthawk RS90):** *Internet* settings → DNS address → *Use these DNS servers* → primary `192.168.1.61`. Netgear routers usually relay DNS, so AdGuard may see every query as coming from the router rather than from each device. Blocking still works.
- **Tailscale admin → DNS:** add a custom nameserver with the Apps VM's `100.x` IP, and turn on *Override local DNS*.

**Vaultwarden:**

```bash
cd ~/homelab/services/Vaultwarden && cp .env.example .env && nano .env
docker compose up -d
sudo tailscale serve --bg --https=8443 http://127.0.0.1:8082
```
Create your account at `https://apps.<tailnet>.ts.net:8443`, turn on two-factor, then set `SIGNUPS_ALLOWED=false` and run `docker compose up -d`.

**Nextcloud:**

```bash
cd ~/homelab/services/Nextcloud && cp .env.example .env && nano .env
docker compose up -d && docker compose logs -f app
sudo tailscale serve --bg --https=443 http://127.0.0.1:8081
```
Log in at `https://apps.<tailnet>.ts.net`.

`tailscale serve status` should list both. These Serve settings survive reboots.

## Phase 8: Minecraft VM

```bash
ssh minecraft
sudo ~/homelab/vm/minecraft-setup.sh         # backups mount + playit agent
sudo playit setup                            # claim it; tunnel → 127.0.0.1:25565
cd ~/homelab/services/Minecraft && cp .env.example .env && nano .env
docker compose up -d && docker compose logs -f mc
```

Re-check the tunnel at playit.gg. If the old tunnel still points at the old agent, delete it and create a new one, then send friends the new address if it changed.

## Phase 9: Harden the Proxmox host

```bash
# On the host. The key was copied in phase 0.
mkdir -p /root/.ssh && cat /root/homelab_ed25519.pub >> /root/.ssh/authorized_keys
```
From the PC, check that `ssh pve` logs in **without a password**. Only then:
```bash
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/10-homelab.conf
sshd -t && systemctl reload ssh
```
**Two-factor for the web UI:** *Datacenter → Permissions → Two Factor → Add → TOTP*, and scan the code with an authenticator app. Keep the recovery keys somewhere safe, not on the homelab.

Proxmox host updates stay manual (*pve → Updates → Refresh → Upgrade*), done monthly. Automatic hypervisor upgrades are riskier than VM upgrades.

## Phase 10: Verify

- [ ] `zpool status das`: all disks ONLINE, listed by by-id name, 0 errors
- [ ] **Reboot the Proxmox host.** The pool imports by itself, both VMs start, all containers come up, and `zpool status` still shows by-id names with nothing FAULTED
- [ ] A website on the PC loads and shows up in AdGuard's query log. Ads are blocked on the phone away from home (over Tailscale)
- [ ] Phone, Wi-Fi off, Tailscale on: Nextcloud app uploads a file, and the file appears under `/das/vault/nextcloud` on the host
- [ ] Bitwarden app logs in to `https://apps.<tailnet>.ts.net:8443`
- [ ] A friend joins Minecraft through playit.gg. A player who isn't whitelisted is kicked
- [ ] **Backups actually work:**
  - `sudo /usr/local/sbin/homelab-backup-apps` on Apps → files appear in `/mnt/backups/*`
  - *Datacenter → Backup →* select the job → **Run now** → both VMs show up in `das-vzdump`
  - `zfs list -t snapshot -r das/vault` the next day shows `@auto-` snapshots
  - Once: restore VM 101's backup to a new VMID, boot it, then delete it
- [ ] Update `hardware/README.md` with the drive models and capacity (`zfs list das`)

## Still not covered

Everything above lives on one DAS in one house. A failed enclosure, fire, or theft would take the live data **and** the backups. The remaining step is an **off-site copy** of `das/vault` and `das/vzdump`: a USB drive kept elsewhere, or an encrypted cloud backup (e.g. restic to Backblaze B2).
