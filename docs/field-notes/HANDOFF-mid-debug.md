> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# WD MyCloud → custom-Linux reflash — HANDOFF / STATE

> **STATUS: SOLVED (2026-06-30).** The box now boots, networks, and serves SSH + Samba.
> This file is the *historical* mid-debug state; for the final solution + lessons read
> **[FINDINGS.md](FINDINGS.md)** (and [README.md](README.md)). The last wall was the PFE
> module param **`disable_wifi_offload=1`** — see FINDINGS §2.7 / §3.2.

**Last updated:** 2026-06-30, mid-debug. Written for a fresh agent to continue without re-deriving.
**Working dir for everything:** `/home/alpha/nas_old/Cloud3TB/` (WSL2, Debian host, user `alpha`, passwordless sudo via `/etc/sudoers.d/99-claude-temp`).

---

## 1. The goal
Replace the WD MyCloud's stock OS with a custom Linux (Samba NAS, no cloud), **keeping the vendor kernel** (its ethernet has no mainline driver). The box is a single-bay **WD MyCloud, Mindspeed/Freescale Comcerto 2000 SoC** (dual Cortex-A9, ~256 MB RAM, armhf). NOT Armada 370.

## 2. Hardware / boot facts (verified, trust these)
- **Disk:** WDC WD30EFRX, 2.7 TB, **GPT**. In WSL it appears as `/dev/sdX` (node drifts: has been sde, sdf — always re-check with `lsblk -dno NAME,SIZE,MODEL | grep EFRX`). On the NAS itself the disk is `/dev/sda`.
- **Partition layout (untouched by us except p1/p2):**
  | part | size | role |
  |---|---|---|
  | sdX1+sdX2 | 1.9 G each | **root RAID1 (`md1`, metadata 0.90, ext3)** — the ONLY thing we rewrite |
  | sdX3 | 489 M | swap |
  | sdX4 | 2.7 T | **data, ext4** (mounted `/srv/nas`; on NAS = `/dev/sda4`) |
  | sdX5 / sdX6 | 95/96 M | vendor kernel A / B |
  | sdX7 / sdX8 | 1/2 M | U-Boot env / config A / B |
- **Boot chain (CRITICAL):** U-Boot bootargs live in `sdX7`/`sdX8`, read via:
  `console=ttyS0,115200n8 init=/sbin/init root=/dev/md1 raid=autodetect rootfstype=ext3 rw noinitrd ... panic=3`
  → **No initramfs.** The kernel does **in-kernel RAID autodetect** and names the array purely from the **0.90 superblock "preferred minor"** field. It then mounts `root=/dev/md1` and execs `/sbin/init`. `panic=3` = reboots 3 s after any panic (→ silent reboot loops).
- **No serial console attached.** UART is a 1.27 mm board-edge pad (1+key+3); user judged it too fiddly to connect. THIS IS THE CENTRAL HANDICAP — every failure so far has been invisible. A receive-only TX+GND tap (no connector to fabricate) would end the guesswork.

## 3. The two footguns we learned (don't repeat)
1. **RAID preferred-minor reverts to 127.** When WSL auto-assembles the array it becomes `md127`; if you then **write** to it (e.g. an `rw` mount, or `mdadm --assemble /dev/md0`), the 0.90 superblock re-stamps preferred-minor to that running number. The vendor kernel then creates `/dev/md0` or `/dev/md127`, `root=/dev/md1` is missing → panic loop. **RULE:** the *very last* array op before the user boots must be `mdadm --assemble /dev/md1 /dev/sdX1 /dev/sdX2 --update=super-minor` then `--stop`, and **do not rw-mount afterward**. Verify with `mdadm --examine /dev/sdX1 | grep 'Preferred Minor'` → must read **1**.
   - To inspect the rootfs WITHOUT disturbing the minor, use `debugfs -R "stat /path" /dev/sdX1` or `-R "cat /path"` (reads the ext3 on a raid member directly, no assembly, no write). Or mount **read-only**.
2. **`flash/02-flash-devuan.sh` originally assembled as `/dev/md0`** — that caused failure #1 below. It's now PATCHED to assemble as `md1 --update=super-minor`. Keep it that way.

## 4. The build pipeline (all scripts in the working dir)
- **Devuan (FAILED, abandoned):** `build-rootfs-stage{1,2,3,4}*.sh` → tree `rootfs-excalibur/` → `rootfs-excalibur.tar.gz`.
- **Stretch (FAILED, current custom attempt):** `build-stretch-stage{1,2,3,4}*.sh` → tree `rootfs-stretch/` → `rootfs-stretch.tar.gz`.
  - Stage1: `debootstrap --foreign --arch=armhf --variant=minbase --no-merged-usr stretch` from `http://archive.debian.org/debian` (keyring fetched + verified OK).
  - Stage2: 2nd stage; apt with `Acquire::Check-Valid-Until "false"`; installs `sysvinit-core insserv udev kmod ifupdown isc-dhcp-client iproute2 iputils-ping openssh-server ...` (sysvinit is PID1, NOT systemd; uses `udev` — `eudev` is Devuan-only). Bakes vendor pfe modules+firmware from `harvest/vendor-kernel-bits.tgz`, **static IP 192.168.0.16/24 gw .1 dns .1+1.1.1.1**, `/etc/resolv.conf`, fstab, hostname `clio`, serial getty @115200, and two diagnostics (see §6).
  - Stage3: samba/sudo/rsyslog/cron/chrony/avahi (wsdd absent in stretch — ok), user `alpha`, smb.conf (workgroup OLYMPUS, host CLIO, shares `public` guest + `alpha`), `depmod 3.2.26`.
  - Stage4: tar `--numeric-owner --xattrs -czf rootfs-stretch.tar.gz`.
- **Flash:** `flash/01-backup-drive.sh /dev/sdX` (backup) and `flash/02-flash-devuan.sh /dev/sdX` (assembles md1+stamps minor, `mkfs.ext3 -L rootfs`, extracts the **TARBALL** — currently points at `rootfs-stretch.tar.gz`, verifies pfe/fw/getty). Both have interactive `YES`/sanity prompts; feed with `printf 'YES\n' |`.
- Build runs under qemu-arm-static binfmt (registered, flag F). `mke2fs` here is **1.47.0 (2023)** — see the open hypothesis.

## 5. Credentials baked in (CHANGE after first successful boot)
- root: `REDACTED` ; user `alpha` (sudo+samba): `REDACTED` ; ssh PermitRootLogin yes (LAN only).

## 6. Diagnostics baked into our images (our "serial substitute")
- **Early canary** `/etc/init.d/canary` → `rcS.d/S03canary` (after udev, before checkroot). Mounts `/dev/sda4` and appends `STAGE=rcS-reached ...` to `<data>/boot-canary.txt`. **Proves init/rcS ran at all.**
- **Full diag** `/etc/init.d/firstboot-diag` (rc2) → dumps `ip addr/link, lsmod, dmesg|pfe, services, mount` to data partition `/srv/nas/first-boot-diag/` AND `/var/log/first-boot-diag/`, symlink `latest.txt`.
- To read after a boot: attach drive to WSL, `mount -o ro /dev/sdX4 /mnt`, look for `/mnt/.canary/boot-canary.txt` and `/mnt/first-boot-diag/latest.txt`.

## 7. Chronology — what each attempt PROVED
1. **Attempt 1 (Devuan):** reboot loop, no ping, ZERO rootfs writes. Cause: flash assembled as md0 → **preferred-minor=0** → root=/dev/md1 missing. Fixed minor→1; patched flash script.
2. **Attempt 2 (Devuan, minor=1, genuine):** STILL zero writes, no ping. (Minor confirmed 1 by examine when drive returned.)
3. **Attempt 3 (Devuan canary):** INVALID — planting the canary via rw-mount reverted minor to 127 (footgun #1). Don't count it.
4. **Attempt 4 (Devuan, clean minor=1 + canary):** **canary ABSENT**, zero writes. → init never ran even with correct minor. Concluded "userland too new" (glibc 2.41 needs syscalls >3.2 kernel, e.g. getrandom@3.17).
5. **Rebuild → Attempt 5 (Stretch, glibc 2.24, minor=1, canary baked in):** **ALSO nothing** — no ping, (canary not yet read but prior pattern). This BREAKS the userland-age theory: era-matched glibc 2.24 should have booted.
6. **STOCK RESTORE sanity test (user's idea):** `dd backup-20260630/p1.img → /dev/md1` (minor kept 1), verified on-disk = genuine WD OS (init "for GNU/Linux 2.6.26", WD markers). **User booted it: BLUE LIGHT + shows on PC = stock works.** → disk + vendor kernel + boot chain + our RAID/minor handling are all FINE. **The problem is exclusively our rootfs.**

## 8. CURRENT STATE (as of handoff)
- **Drive is in the NAS, running STOCK, confirmed working** (blue LED, visible on network via DHCP — NOT at .16). Drive is NOT attached to WSL right now.
- `rootfs-stretch.tar.gz` is built and ready; `flash/02-flash-devuan.sh` points at it.
- Local backups intact (see §10).

## 9. THE OPEN QUESTION + the exact next step
**Leading hypothesis:** the filesystem created by **`mke2fs 1.47.0` is not mountable by the vendor 3.2.26 kernel**, even though the named feature flags matched stock (`has_journal ext_attr resize_inode dir_index filetype sparse_super large_file`, inode 256, block 4096). This is the one thing BOTH failed custom builds share and that stock (2013-era ext3) does not. NOTE: the stock-restore test changed BOTH the fs AND the userland, so it proves "disk/kernel OK" but does NOT by itself isolate fs-vs-userland — hence the next two steps.

**Next step A (no drive needed — DO THIS FIRST):** full superblock diff. Was about to run:
```bash
cd <scratch>; truncate -s 1950M test.img; mkfs.ext3 -L rootfs -q test.img
sudo dumpe2fs -h test.img > ours.txt
sudo dumpe2fs -h /home/alpha/nas_old/Cloud3TB/backup-20260630/p1.img > stock.txt
diff stock.txt ours.txt   # look at: revision, inode size, "Default mount options",
                          # "Filesystem flags", Journal features/backup, "*extra isize", First inode
```
Look especially for: `Filesystem revision #`, `Default mount options` (newer mke2fs adds `user_xattr acl`), any journal feature, `Required/Desired extra isize`, `Inode size`, 64-bit/csum bits. If a clear culprit appears, fix by making the flash script create an old-compatible fs, e.g.:
```bash
mke2fs -t ext3 -O ^huge_file,^dir_nlink,^extra_isize,^metadata_csum,^64bit,^resize_inode \
       -I 128 -L rootfs <dev>     # or match stock's exact -O/-I/-r set
```
(Don't blindly drop features — match what `dumpe2fs` shows on STOCK.)

**Next step B (decisive, needs one drive cycle):** the cleanest deterministic fix AND experiment — build our Stretch userland into a **stock-created ext3 structure** so the fs is guaranteed kernel-mountable:
```
assemble md1 (--update super-minor) ; dd p1.img -> /dev/md1 ; mount md1 rw ;
rm -rf everything ; tar -xzf rootfs-stretch.tar.gz -C mnt --numeric-owner --xattrs ;
umount ; re-stamp minor=1 as LAST op ; stop.
```
- If THIS boots → confirms mke2fs-1.47 was the culprit; we have a working NAS.
- If it STILL fails (no canary on sda4) → the problem is the userland/contents after all, and **serial console becomes necessary** — stop guessing.

**Alternative if both stall:** drop to an even older userland (Debian 7 Wheezy = exact WD era) and/or finally tap serial RX.

## 10. Backups / recovery (we can always get back to working stock)
- **Local:** `backup-20260630/` = `p1.img` (stock rootfs, the one we restore), `p5/6/7/8.img` (kernel/config), `gpt-backup.bin`, `partition-table.sfdisk`, checksums. (Stock-restore = `dd p1.img -> /dev/md1` while assembled at minor 1.)
- **External E::** `/mnt/e/MyCloud-Clio-backup-20260629/` = sda1-rootfs + both kernels + both configs + GPT first/last MiB + md5s.
- Data partition (2.7 TB) and kernels/config NEVER touched. "Brick" here only ever meant "boots but invisible," always re-flashable.

## 11. How to operate the drive (no serial)
- Attach to WSL: user runs **elevated PowerShell** `wsl --mount \\.\PHYSICALDRIVE2 --bare`; detach `wsl --unmount \\.\PHYSICALDRIVE2`. (Disk is PHYSICALDRIVE2 = the 2794.5 GB WDC; verify with `Get-Disk`.)
- The agent's bash is non-interactive; the user must run the PS mount/unmount themselves. Node in WSL drifts (sde/sdf) — always re-detect.
- After ANY flash/restore: re-stamp minor=1 as the last op, verify via `mdadm --examine`, leave array stopped, then have user `wsl --unmount` + reassemble + power on (~2 min) + `ping 192.168.0.16` (our static) — then bring drive back to read canary/diag if no ping.

## 12. One-line summary for the next agent
Stock boots fine; both our custom builds (Devuan glibc2.41 AND Debian-Stretch glibc2.24) die before init writes anything, with correct RAID minor=1. **UPDATE (§13): §9's two hypotheses are now DISPROVEN offline — the fs is feature-identical to stock and the userland's min-kernel is 3.2.0 ≤ 3.2.26. We stopped guessing and instrumented the boot instead; do §13, not §9 step B.**

---

## 13. ATTEMPT 6 — instrumented blind flash (staged 2026-06-30; tarball ready, NOT yet flashed)
Offline work this session DISPROVED both §9 hypotheses, so we add observability instead of swapping suspects:
- **FS theory dead:** our `mkfs.ext3` (e2fsprogs 1.47, the flash script's exact opts) superblock is feature-**IDENTICAL** to stock `backup-20260630/p1.img` — same `Filesystem features`, revision 1, block 4096, inode 256, `Default mount options: user_xattr acl`, flags. Only delta is `extra_isize 28→32` (benign; journal_incompat_revoke/sequence diffs are just fresh-vs-used-journal). A kernel that mounts stock mounts ours → **§9 step B would NOT fix boot.**
- **Userland-age theory dead:** in `rootfs-stretch.tar.gz`, `/sbin/init` and `libc.so.6`→libc-2.24.so are both `for GNU/Linux 3.2.0` (NT_GNU_ABI_TAG `OS: Linux, ABI: 3.2.0`), interp `/lib/ld-linux-armhf.so.3` present. 3.2.0 ≤ vendor 3.2.26 AND glibc 2.24's floor is 3.2.0, so it cannot issue a syscall newer than the kernel. Userland runs on this kernel.

**Changes baked into the image/flash (already built; `rootfs-stretch.tar.gz` md5 `REDACTED-MACHINE-ID`):**
- New EARLIEST marker `/etc/init.d/initmarker`, wired as the FIRST inittab `sysinit` action (`ma::sysinit:`) **before** rcS. Writes `/INIT-RAN.txt` to the ROOT fs + `sync`. Proves `/sbin/init` exec'd & parsed inittab — independent of udev/sda4/rcS. (Reproducible: stage2 step [11b].)
- `flash/02-flash-devuan.sh` now (a) verifies the marker landed (aborts if not), (b) `tune2fs -C 0` resets the fs **mount-count baseline to 0** as the last fs op, then re-checks `Preferred Minor : 1`. So after a boot: **Mount count ≥ 1 ⟺ the kernel mounted root.**

**Diagnostic ladder (each rung = how far boot got, narrowing the domain):**
1. **mount-count** (root superblock) → did the KERNEL mount root?  [fs / raid / cmdline]
2. **/INIT-RAN.txt** (root fs) → did `/sbin/init` exec + parse inittab?  [exec / linker / console]
3. **/.canary/boot-canary.txt** (sda4) → did rcS reach S03?  [early rcS]
4. **/first-boot-diag/latest.txt** (sda4) → did it reach rc2 (full multiuser)?  [services / net]

### Physical steps (user)
1. Power off NAS, pull drive, USB-SATA. Elevated PowerShell: `Get-Disk` (find 2794.5 GB WDC) → `wsl --mount \\.\PHYSICALDRIVE2 --bare`.
2. In WSL re-detect node (drifts): `lsblk -dno NAME,SIZE,MODEL | grep EFRX` → that is `sdX`.
3. `printf 'YES\n' | sudo bash /home/alpha/nas_old/Cloud3TB/flash/02-flash-devuan.sh /dev/sdX`
   — confirm it prints `init marker wired OK`, `Mount count: 0`, `Preferred Minor : 1`. **Do NOT rw-mount the array afterward** (bumps the baseline).
4. Elevated PS: `wsl --unmount \\.\PHYSICALDRIVE2`. Reseat drive in NAS, power on, wait ~2 min, `ping 192.168.0.16`.
5. Power off, pull drive, `wsl --mount ... --bare` again, re-detect `sdX`.

### Read-back (ALL read-only — no assemble, no minor change)
```bash
sudo mdadm --stop --scan 2>/dev/null || true          # drop any WSL auto-assembly (no write)
# rung 1 — kernel mounted root?
sudo dumpe2fs -h /dev/sdX1 2>/dev/null | grep -iE 'Mount count|Filesystem state'
# rung 2 — init exec'd?
sudo debugfs -R "cat /INIT-RAN.txt" /dev/sdX1 2>/dev/null
# rungs 3 & 4 — rcS / multiuser (data partition, plain RO mount)
sudo mount -o ro /dev/sdX4 /mnt && { echo '== canary =='; cat /mnt/.canary/boot-canary.txt; \
  echo '== diag =='; cat /mnt/first-boot-diag/latest.txt; } 2>/dev/null; sudo umount /mnt
```
**Verdict — highest rung present is where it died:**
- Mount count still **0** → kernel never mounted root *despite an identical fs* → investigate in-kernel RAID autodetect / bootargs, NOT userland.
- Mount count **≥1** but **no /INIT-RAN.txt** → root mounted, init didn't run → linker/binary or missing `/dev/console`/devtmpfs → **serial RX tap now strongly indicated.**
- **/INIT-RAN.txt** but no canary → init fine; rcS died before S03.
- **canary** but no diag → died between S03 and rc2.
- **diag present** → full boot; only networking/services left (the good outcome).

**If you will BOOT this same flash again after reading** (rather than re-flashing), re-stamp minor as the LAST op: `sudo mdadm --assemble /dev/md1 /dev/sdX1 /dev/sdX2 --update=super-minor` → `--examine` shows `Preferred Minor : 1` → `--stop`, then `wsl --unmount`. Re-flashing instead handles the minor itself.
