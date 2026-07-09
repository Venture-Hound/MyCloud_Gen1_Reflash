> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# WD MyCloud → Devuan NAS — Morning Runbook

Built overnight while you slept. **Nothing was done to the physical NAS** — it's still running stock,
reachable at `192.168.0.16`. Everything below is the host-side work + the hardware steps for you to do.

## TL;DR of what the box actually is
- **SoC: Mindspeed/Freescale Comcerto 2000** (NOT Armada 370, despite what the internet says). Dual Cortex-A9, ~256 MB RAM.
- Ethernet runs through a proprietary **PFE** engine → no mainline kernel support → **we keep the vendor 3.2.26 kernel** and only replace the userland.
- Target OS: **Devuan Excalibur (= Debian 13 Trixie, no systemd)**, armhf. Confirmed its glibc 2.41 runs on a 3.2 kernel (min-kernel 3.2.0).

## What's prepared on the host (`/home/alpha/nas_old/Cloud3TB/`)
| File | Purpose |
|---|---|
| `rootfs-excalibur/` | The built Devuan rootfs (chroot tree) |
| `rootfs-excalibur.tar.gz` | Flashable tarball of the above (what gets written to the drive) |
| `harvest/vendor-kernel-bits.tgz` | Vendor `/lib/modules/3.2.26` (incl `pfe.ko`) + firmware — baked into the rootfs |
| `build-rootfs-stage{1,2,3,4}*.sh` | The build scripts (already run; kept for reproducibility) |
| `flash/01-backup-drive.sh` | Safety-net backup of the current drive |
| `flash/02-flash-devuan.sh` | Writes Devuan onto the root RAID (md1) |
| `img/` | Original WD firmware images (extra fallback) |

## Credentials baked in (CHANGE THESE after first boot)
- root password: `REDACTED`
- user `alpha` (sudo + samba): `REDACTED`
- Samba: workgroup `OLYMPUS`, host `CLIO`, shares `public` (guest) and `alpha` (auth)

---

## Hardware steps (in order)

### Prereqs
- USB-to-SATA adapter (you have it).
- The drive, removed from the MyCloud enclosure.
- ~~USB-to-TTL serial adapter~~ — **DROPPED.** The UART is a 1.27mm board-edge
  pad (1 + key + 3), too fiddly to source a connector for. We flash WITHOUT
  serial. Reachability is bought back two ways baked into the image:
  a **static IP (192.168.0.16)** and an **every-boot diagnostic logger** that
  writes to the data partition (sda4) — see Steps E–H.

### Step A — Attach the drive to WSL2
1. Plug the drive into the USB-SATA adapter → into the PC.
2. **PowerShell as Administrator** — find the disk number:
   ```powershell
   wmic diskdrive list brief        # or: Get-Disk
   ```
   Identify the ~3 TB WDC WD30EFRX.
3. Mount it raw into WSL:
   ```powershell
   wsl --mount \\.\PHYSICALDRIVEn --bare
   ```
   (replace `n`). In WSL it appears as `/dev/sdX` (likely `/dev/sdd`). Confirm:
   ```bash
   lsblk -o NAME,SIZE,MODEL
   ```

### Step B — Back it up (do not skip)
```bash
sudo bash /home/alpha/nas_old/Cloud3TB/flash/01-backup-drive.sh /dev/sdX
```
Writes partition table + kernel/config partitions + a rootfs mirror to `backup-YYYYMMDD/`.
This is your rollback path.

### Step C — Flash Devuan
```bash
sudo bash /home/alpha/nas_old/Cloud3TB/flash/02-flash-devuan.sh /dev/sdX
```
It assembles the root RAID, `mkfs.ext3` on it (wipes only the stock rootfs), extracts the Devuan
tarball, and verifies `pfe.ko` / firmware / serial getty / pfe-autoload landed. **Kernel, config and
the 2.7 TB data partition are untouched.**

### Step D — Detach + reassemble
```powershell
wsl --unmount \\.\PHYSICALDRIVEn
```
Put the drive back in the MyCloud.

### Step E — (router) reserve the IP — optional but recommended
While the box is **still alive at 192.168.0.16**, note its MAC from your router's
client list (entry at .16, may show as CLIO / MyCloud) and add a DHCP
**reservation** (MAC → 192.168.0.16) so nothing else ever leases .16 while the
NAS is off. The image is statically set to .16 regardless, so this only prevents
a future address clash — not required for first boot.

### Step F — Reassemble + power on, give it ~2 minutes
No serial console. Put the drive back in the MyCloud, power on, wait ~1–2 min for
a full boot (DHCP isn't used, so no lease delay). Then reach it at the **fixed**
address — no need to hunt for a lease:
- `ssh alpha@192.168.0.16`   (password `REDACTED`)  — or `ssh root@192.168.0.16` / `REDACTED`
- fallbacks: `ssh alpha@clio.local` (avahi/mDNS), or `\\192.168.0.16\public` in Explorer
- a successful `ping 192.168.0.16` from your PC is the quickest "it's alive" signal.

### Step G — Verify networking + shares
Once SSH'd in:
```bash
ip addr show eth0          # should show 192.168.0.16/24 (static)
lsmod | grep pfe           # pfe loaded
dmesg | grep -i pfe        # firmware loaded OK
```
From Windows Explorer: `\\192.168.0.16\public` and `\\192.168.0.16\alpha` (or `\\CLIO\...`).

### Step H — If you CAN'T reach it (the serial substitute)
The image writes a full boot diagnostic every boot to the data partition. To read it:
1. Power off, pull the drive, attach via USB-SATA, `wsl --mount \\.\PHYSICALDRIVEn --bare`.
2. Plain-mount **sda4** (no RAID needed): `sudo mount /dev/sdX4 /mnt && cat /mnt/first-boot-diag/latest.txt`
3. It shows `ip addr` / `ip link` (real iface name + whether eth0 got .16), `lsmod`,
   `dmesg | grep pfe` (firmware load), and which services started — i.e. exactly why
   it's unreachable. Fix in the image, re-run stage4 + flash, retry.

---

## If first boot fails (rollback)
Re-attach the drive via `wsl --mount`, then restore the stock rootfs from the backup:
```bash
sudo mdadm --assemble --run /dev/md0 /dev/sdX1 /dev/sdX2   # or --scan
sudo dd if=backup-YYYYMMDD/p1.img of=/dev/md0 bs=4M status=progress   # restores stock rootfs onto the array
```
(Or rebuild from `img/` per the fox-exe notes.) The box is then back to stock — no harm done.

### Likely first-boot gotchas (debug via the sda4 diagnostic logger — Step H)
- **No eth0 / unreachable**: check `dmesg | grep pfe` for firmware load; confirm `pfe.ko` loaded
  (`lsmod`); `S08kmod` loads it before `S12networking`, so order is fine. If `ip link` shows the
  interface under a name other than `eth0`, edit `/etc/network/interfaces` to match and re-flash.
- **Reachable by ping but not SSH**: services may still be starting — give it another minute; else
  check the diag dump's service list for sshd/smbd.
- **Root won't mount**: kernel cmdline expects `root=/dev/md1 ... rootfstype=ext3` with RAID
  metadata 0.90 — the flash script preserves the array and uses ext3, so this should be fine.
  (This failure mode boots nothing, so the sda4 logger won't run — that's the one case the dropped
  serial console would've helped; recovery is the rollback above.)
- **⚠ RAID preferred-minor (caused the first real first-boot failure 2026-06-30)**: bootargs are
  `root=/dev/md1 raid=autodetect noinitrd panic=3` — NO initramfs, so the kernel autodetects the
  array and names it from the **0.90 superblock preferred-minor**. If the array was ever assembled/
  written as md0 (preferred-minor 0), the kernel makes /dev/md0, root=/dev/md1 is missing, and it
  panic-reboot-loops silently (no ping, link-LED flicker, no rootfs writes). FIX:
  `sudo mdadm --assemble /dev/md1 /dev/sdX1 /dev/sdX2 --update=super-minor` then `--examine` shows
  `Preferred Minor : 1`. The flash script now always assembles as md1 with `--update=super-minor`.

---

## Post-success cleanup (once it's working)
1. Change `root` and `alpha` passwords (`passwd`).
2. Set up the data partition for storage (it's empty). Either reuse it as-is or reformat:
   ```bash
   sudo mkfs.ext4 -L data /dev/sda4   # WIPES the 2.7TB partition (it's empty anyway)
   ```
   `fstab` already mounts `/dev/sda4` at `/srv/nas` (with `nofail`).
3. Confirm `chrony` is syncing time (fixes the old stuck-clock problem): `chronyc tracking`.
4. **On the WSL2 host, remove the temporary passwordless sudo** I used:
   ```bash
   sudo rm /etc/sudoers.d/99-claude-temp
   ```
5. Keep it **LAN-only** (no port-forwarding) regardless — good hygiene.
