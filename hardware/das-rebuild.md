# Runbook: Replace the DAS and Rebuild the ZFS Pool

Swapping the ORICO MixData Vault Big5 (5 × 960 GB SSD, RAID-Z1) for an **ORICO 9958RU3** with 3.5" hard drives, rebuilding the `das` pool from scratch, and reconnecting Immich and Jellyfin on the Apps VM.

> **This wipes everything on the old pool.** That includes the Immich photos and the nightly Immich database dumps in `/mnt/photos/backups`. Immich is reset to a fresh install as part of this runbook.

**Goal:** keep every name and path the same (pool `das`, datasets under `/das/vault/`, mappings `documents`/`media`/`photos`, and `/mnt/photos` and `/mnt/media` in the VM). That way the Proxmox directory mappings, the VM's virtiofs devices, `/etc/fstab`, and the Docker Compose files don't need to change.

| Placeholder | Meaning | How to find it |
|---|---|---|
| `<VMID>` | Apps VM ID | `qm list` on the Proxmox host |
| `<IMMICH_DIR>` | Folder with Immich's `docker-compose.yml` | On the Apps VM |
| `<JELLYFIN_DIR>` | Folder with Jellyfin's `docker-compose.yml` | On the Apps VM |
| `<DISK_ID_1..N>` | New drives' `/dev/disk/by-id/` names | Step 4 |

---

## 1. Stop the apps (Apps VM, 192.168.1.61)

```bash
cd <IMMICH_DIR>   && docker compose down
cd <JELLYFIN_DIR> && docker compose down

# Note how the shares are mounted. The tags should be photos/media (and documents if used).
grep virtiofs /etc/fstab
findmnt -t virtiofs

sudo shutdown now
```

The VM has to stay **off** until the new pool exists. Its virtiofs devices point at `/das/vault/...`, so it won't start while those folders are missing.

## 2. Destroy the old pool (Proxmox host, 192.168.1.81)

Record the current layout first, for reference:

```bash
qm list                              # note the Apps VM's <VMID>
qm config <VMID> | grep virtiofs     # virtiofs0..N → photos, media, documents
pvesh get /cluster/mapping/dir       # mappings → /das/vault/...
zfs list -r das                      # datasets and mountpoints
```

**Option A, GUI:** *Node → Disks → ZFS →* select `das` *→ More → Destroy*. Tick **Cleanup storage configuration** and **Cleanup disks**.

**Option B, CLI:**

```bash
pvesm remove das          # remove the Proxmox storage entry
zpool destroy das
systemctl disable zfs-import@das.service 2>/dev/null   # old import unit, if one exists
```

> **If the pool shows `SUSPENDED`** (the old DAS was unplugged or powered off first), `zpool destroy` can hang. Plug the old DAS back in, run `zpool clear das` until `zpool status das` shows ONLINE, then destroy it as above. If you can't reconnect it, try `zpool destroy -f das`. If that hangs, reboot the host with the old DAS unplugged, then run `pvesm remove das` and `systemctl disable zfs-import@das.service`.
>
> **Check other storages:** `cat /etc/pve/storage.cfg`. Any `dir` storage (such as `backups`) whose `path` is under `/das` has to be removed first (`pvesm remove <name>`) and added back after step 6.

Check that it's gone: `zpool list` should not show `das`, and `ls /das` should be empty or missing. If `/das` still has leftover empty folders, remove them with `rm -rf /das`. Only do this after you've confirmed the pool is gone.

Power off the old ORICO and unplug it. *(Optional: if you plan to reuse the 960 GB SSDs, which would make a good backup target, clear their old ZFS labels with Disks → Wipe Disk before using them again.)*

## 3. Set up the ORICO 9958RU3 in Normal mode

The 9958RU3 is a **hardware RAID** box. ZFS needs to see each drive individually, so set it to **Normal/Clear** mode, **not** RAID 5 and **not** "JBOD" or "Span (Big)". On this enclosure, JBOD and Span merge every drive into one disk.

1. With the enclosure **powered off**, install the 3.5" drives. Note which drive (serial number) goes in which bay.
2. Set the rear DIP switches for **Normal/Clear: 1 = ON, 2 = OFF, 3 = ON, 4 = OFF**.
3. Hold the **SET** button and press power. Keep holding it for a few seconds, until the enclosure beeps or the LEDs confirm the mode.
4. Connect it to the ProDesk with USB-A (USB 3.0, 5 Gbps), the same port the old DAS used.

Notes for this enclosure:
- **Smart Sleep:** it spins the drives down after about 10 minutes idle. ZFS usually handles this, but the first access after a spin-down will be slow. If ZFS logs I/O errors or timeouts after an idle period, look for ORICO firmware or a tool that turns sleep off.
- **Hot-swap:** in Normal mode, adding or removing a drive can briefly disconnect the **other** drives too. Only add or remove drives with the enclosure powered off.

## 4. Identify and check the new drives (Proxmox host)

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN     # new drives show TRAN=usb
ls -l /dev/disk/by-id/ | grep -v part
```

You should see **one unique by-id name per drive**, usually `usb-<vendor>_<model>_<serial>-0:0` or `ata-...`/`wwn-...`. Copy these names; they're your `<DISK_ID_n>`.

> ⚠️ **Known ORICO issue:** some multi-bay ORICO USB enclosures report the same or incomplete by-id names, so one drive goes missing from `/dev/disk/by-id`. A pool built on `/dev/sdX` names can then show a disk as FAULTED after a reboot. If two drives share an ID, or a drive has no by-id entry, **stop here**. Check `ls -l /dev/disk/by-path/` and `blkid`, and don't build the pool until every drive has a stable, unique name.

Check drive health. USB bridges need `-d sat`:

```bash
for d in /dev/sdX /dev/sdY /dev/sdZ; do      # the new drives only
  smartctl -d sat -H -A $d | grep -E 'overall-health|Reallocated|Pending|Uncorrect|Power_On'
done
smartctl -d sat -t short /dev/sdX            # optional short self-test, about 2 min
```

New drives should show `PASSED` and 0 reallocated/pending sectors. Then wipe any factory partition tables:

```bash
wipefs -a /dev/disk/by-id/<DISK_ID_1>        # repeat for each new drive
```

## 5. Pick the layout

| Drives | Layout | Survives | Usable space (N drives of size S) |
|---|---|---|---|
| 2 | `mirror` | 1 failure | S |
| 3 | `raidz1` | 1 failure | 2 × S |
| 4 | `raidz1` | 1 failure | 3 × S |
| 4 | 2 × `mirror` | 1 per mirror | 2 × S (faster, easier to expand) |
| 5 | `raidz2` | **2 failures** | 3 × S |

**RAID-Z2 is recommended for 5 large HDDs.** Rebuilding a multi-TB drive (resilvering) takes many hours, and a USB link that drops a second drive during that window would destroy a RAID-Z1 pool. Every vdev is limited by its smallest drive, so use same-size drives.

## 6. Create the pool and datasets (Proxmox host)

```bash
# Example for 5 drives as RAID-Z2. Replace raidz2 with your layout from step 5.
zpool create -o ashift=12 \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -m /das das raidz2 \
  /dev/disk/by-id/<DISK_ID_1> \
  /dev/disk/by-id/<DISK_ID_2> \
  /dev/disk/by-id/<DISK_ID_3> \
  /dev/disk/by-id/<DISK_ID_4> \
  /dev/disk/by-id/<DISK_ID_5>

# Import the pool at boot, as Proxmox does for pools made in the GUI
systemctl enable zfs-import@das.service

# Same paths as before, so the directory mappings still match
zfs create -p das/vault/photos
zfs create    das/vault/media
zfs create    das/vault/documents
zfs set recordsize=1M das/vault/media      # large sequential video files

# Jellyfin runs as 1000:1000; Immich (root) can write either way
chown -R 1000:1000 /das/vault/photos /das/vault/media /das/vault/documents

# Optional: list it in the Proxmox UI again
pvesm add zfspool das --pool das --content images,rootdir
```

What the options do:
- `ashift=12`: 4K sectors, correct for modern HDDs. **It can't be changed later.**
- `lz4`: nearly free on CPU, and it saves space on documents and metadata.
- `atime=off`: avoids a disk write on every file read.
- `xattr=sa`: stores extended attributes more efficiently.

Check the pool:

```bash
zpool status das       # every disk ONLINE, listed by its by-id name
zfs list -r das        # das/vault/{photos,media,documents} under /das/vault/
```

Scrubs: Proxmox's `zfsutils-linux` package already runs a monthly scrub (`/etc/cron.d/zfsutils-linux`), and it covers the new pool automatically.

## 7. Confirm the Proxmox mappings

The paths match the old ones, so nothing should need changing:

```bash
pvesh get /cluster/mapping/dir          # documents/media/photos → /das/vault/...
qm config <VMID> | grep virtiofs        # still attached to the VM
```

If a mapping or virtiofs device was removed, add it back. For a mapping: *Datacenter → Resource Mappings → Directory Mappings → Add* (ID `photos`, path `/das/vault/photos`, node `pve`). For a device: *Apps VM → Hardware → Add → Virtiofs* and pick the mapping.

## 8. Start the Apps VM and check the mounts

```bash
qm start <VMID>
```

On the Apps VM:

```bash
findmnt -t virtiofs                       # /mnt/photos and /mnt/media mounted
sudo mount -a                             # if they're not mounted yet
touch /mnt/media/.write-test /mnt/photos/.write-test && ls -ln /mnt/media /mnt/photos
rm /mnt/media/.write-test /mnt/photos/.write-test
```

The test files should be owned by `1000 1000`. Back on the host, `ls /das/vault/media` briefly showing `.write-test` proves the files land on the new pool.

## 9. Reset Immich to a fresh install

The old database still lists photos that no longer exist. Immich also checks for its `.immich` marker files in the upload folder and won't start when they're missing. Because everything was wiped, start Immich clean:

```bash
cd <IMMICH_DIR>
sudo rm -rf ./postgres        # old database (owned by the container user, so sudo)
docker compose pull           # optional: pick up v3 updates while it's down
docker compose up -d
docker ps                     # all 4 immich_* containers become (healthy)
ls /mnt/photos                # Immich creates library/, upload/, thumbs/, encoded-video/, profile/, backups/
```

Open `http://192.168.1.61:2283`, create the admin account again, log in again in the iOS app, and turn on **Backup** in the app. Upload one photo and confirm it shows up under `/das/vault/photos/upload` on the host.

## 10. Restart Jellyfin

Jellyfin had no libraries yet, so its `./config` can stay:

```bash
cd <JELLYFIN_DIR> && docker compose up -d
docker logs --tail 50 jellyfin   # no permission errors on /media
```

Copy one movie into `/mnt/media`, add a **Movies** library in Jellyfin that points at the container path, and confirm it plays.

## 11. Final checks

- [ ] `zpool status das` shows every disk ONLINE with 0 errors
- [ ] Reboot the **Proxmox host** once. Then confirm the pool imports by itself, the Apps VM starts, and both apps come up. This is where by-id problems show up with USB enclosures.
- [ ] `zpool status das` after the reboot still shows all disks by their by-id names, with nothing FAULTED
- [ ] Immich upload from the phone works over Tailscale
- [ ] Jellyfin plays a file over Tailscale
- [ ] Update `hardware/README.md` with the drive models and the final capacity (`zfs list das`)
