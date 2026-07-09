> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# WD MyCloud (Gen1) → Debian on the vendor kernel — findings & lessons

**Status: WORKING.** A single-bay 1st-gen WD MyCloud booting a custom Debian 9
(Stretch) userland on WD's **own vendor kernel**, reachable over the network
(ping / SSH / Samba), with **no serial console used** during the whole bring-up.

This file is the *raw material* for a future write-up — what the box actually is,
the exact set of fixes that make it work, the dead-ends we ruled out (so you don't
repeat them), and the no-serial debugging method that got us there. It is
deliberately not a polished tutorial.

---

## 1. What the hardware actually is (correct the internet first)

- **Model:** WD MyCloud, **single-bay, 1st gen** ("Clio" in our notes).
- **SoC: Mindspeed/Freescale Comcerto 2000** — dual Cortex-A9, ~256 MB RAM, **armhf**.
  It is **NOT** an Armada 370, despite what a lot of forum posts claim. Tooling and
  kernels for Armada will not apply.
- **Ethernet = PFE (Packet Forwarding Engine):** a proprietary hardware datapath
  with **no mainline Linux driver**. This is the single fact that shapes everything:
  you **must keep the vendor kernel** (3.2.26) and its `pfe.ko` + firmware. You can
  only replace userland.
- **The vendor kernel uses 64 KB pages.** (Deduced from ELF segment alignment — see §3.6.)
  This is unusual for armv7 and has big consequences for which userland will run.
- **Boot chain (critical):** U-Boot bootargs live in small GPT partitions and read:
  `console=ttyS0,115200n8 init=/sbin/init root=/dev/md1 raid=autodetect rootfstype=ext3 rw noinitrd ... panic=3`
  → **No initramfs.** The kernel does **in-kernel RAID autodetect** and names the
  root array purely from the 0.90 superblock's *preferred-minor* field, then mounts
  `root=/dev/md1` and execs `/sbin/init`. `panic=3` = reboot 3 s after any panic
  (so every early failure is a *silent* reboot).
- **Disk layout (GPT, WD30EFRX in our unit):**
  | part | size | role |
  |---|---|---|
  | p1 + p2 | ~1.9 G each | **root RAID1 (`md1`, metadata 0.90, ext3)** — the only thing we rewrite |
  | p3 | ~0.5 G | swap |
  | p4 | rest (2.7 T) | **data, ext4** (mounted `/srv/nas`; `/dev/sda4` on the NAS) |
  | p5 / p6 | ~95 M | vendor kernel A / B |
  | p7 / p8 | 1–2 M | U-Boot env / config A / B |
  On the NAS the disk is `/dev/sda`. In WSL it shows up as `/dev/sdX` and the node
  **drifts** between attaches — always re-detect.

---

## 2. The final working recipe (in boot order)

Base: **Debian 9 "Stretch", armhf, sysvinit (NOT systemd), glibc 2.24**, built with
`debootstrap` from `archive.debian.org`. (Why Stretch and not newer/older: §3.6.)

1. **RAID preferred-minor must be 1.** The flash assembles the root array as
   `/dev/md1` with `mdadm --assemble --update=super-minor`, and **must not rw-mount
   it afterward** (any write while the array runs under the wrong md number
   re-stamps the minor). Verify with `mdadm --examine /dev/sdX1 | grep 'Preferred Minor'` → `1`.
2. **Filesystem is a non-issue.** `mkfs.ext3` from modern e2fsprogs (1.47) produces a
   superblock whose feature flags/revision/inode-size/mount-options are **identical**
   to stock's 2013 ext3 (only `extra_isize` 28→32, benign). Verified by `dumpe2fs`
   diff vs the stock root image.
3. **Disable modern udev.** udev 232 (systemd-era) **hangs `rcS` at `S02udev`** on the
   3.2.26 kernel → silent reboot/hang, nothing past it runs. Fix: replace
   `/etc/init.d/udev` with a **no-op stub** that still `Provides: udev` (so the
   dependency graph stays satisfied and nothing waits on it). udevd never starts.
4. **Populate `/dev` without udev.** This kernel has **no `CONFIG_DEVTMPFS`** (a
   `mount -t devtmpfs` attempt leaves `/dev` unchanged), so — exactly like stock,
   which ships ~144 static nodes — we **bake static `/dev` nodes** (console, null,
   tty, ttyS0, sda+sda1..8, md1, sdb+sdb1, …). A best-effort devtmpfs mount runs as
   an early inittab `sysinit` action; if it ever works it shadows the static nodes harmlessly.
5. **64 KB-page fix — stub `libsystemd`.** On a 64 KB-page kernel every userspace ELF
   must be ≥64 KB-aligned. Debian armhf builds everything 64 KB-aligned **except the
   systemd/udev family** (`libsystemd.so.0`, `libudev.so.1`, `udevadm`, `systemd-hwdb`)
   which are 4 KB-aligned and therefore **unloadable** → that breaks `sshd`, Samba
   (`libsamba-util`→`libsystemd`), `ps`, `dbus`, `logger`. Fix: drop in a **64 KB-aligned,
   versioned, no-op stub `libsystemd.so.0`** (we only need the symbols to *resolve*;
   sysvinit needs no real systemd). `libudev` needs no stub — nothing we run loads it.
6. **Firmware loading without udev.** A **pre-3.7 kernel has no direct-from-filesystem
   firmware loading** — it needs a *userspace helper*, which used to be udev. We
   provide `/sbin/fw-helper` and point the kernel at it via
   `echo /sbin/fw-helper > /proc/sys/kernel/hotplug`, **before** the PFE driver calls
   `request_firmware()`. So `pfe` is removed from `/etc/modules` and `modprobe`d from
   the `eth0` `pre-up` *after* the helper is set.
7. **THE final blocker — PFE module params.** Stock loads:
   `pfe lro_mode=1 tx_qos=1 alloc_on_init=1 disable_wifi_offload=1`.
   We were loading bare `pfe`. **Without `disable_wifi_offload=1`, the PFE brings up
   its VWD / "wifi-offload" datapath** (`pfe_vwd_init: created vwd device` in dmesg)
   **which hijacks host-bound RX** — outbound works, inbound *unicast* works (NTP synced!),
   but inbound *broadcast* (ARP "who-has .16") never reaches the Linux stack, so the
   box answers nobody and is unreachable. Loading with `disable_wifi_offload=1` (we set
   it both in `/etc/modprobe.d/pfe.conf` and on the `modprobe` line) fixed it instantly.
8. **The rest:** static IP `192.168.0.16/24`, Samba (workgroup `OLYMPUS`, host `CLIO`,
   guest `public` + auth `alpha` shares), `sshd`, `chrony` (fixes the dead RTC stuck at 2012),
   serial getty on ttyS0 (insurance), and the diagnostics in §4.

---

## 3. Lessons worth sharing (ranked by how much pain they saved/cost)

**3.1 Keep the vendor kernel; the PFE has no mainline driver.** Everything else
follows from this. You are doing a *userland swap on a frozen 2012 kernel*, not a
normal install.

**3.2 The PFE `disable_wifi_offload=1` param is the difference between "on the network"
and "invisible."** This was the hardest to find and the most opaque: the box looked
100% healthy from inside (eth0 up, link 1000/Full, reached the internet, Samba running)
yet was unreachable. Found by **diffing stock's `/etc/modules`**. If your rebuilt
MyCloud pings out but nothing can ping it, this is almost certainly why.

**3.3 Modern udev does not work on this kernel.** It hangs `rcS` early. Don't fight it —
go udev-less with a static `/dev` (the kernel has no devtmpfs anyway). This was the
breakthrough that turned "boots nothing visible" into "boots fully."

**3.4 Firmware on a pre-3.7 kernel needs a userspace helper.** Once you remove udev you
also remove the thing that loaded firmware. Symptom: `request_firmware ... failed` /
`pfe: probe failed -110 (ETIMEDOUT)` ~60 s in, no eth0. Fix is the tiny
`/proc/sys/kernel/hotplug` helper.

**3.5 64 KB pages → check ELF alignment.** `readelf -lW <so> | grep LOAD` — segments
must be `0x10000`-aligned. If a library is `0x1000`-aligned it won't load and every
binary linking it dies with *"ELF load command alignment not page-aligned."* On this
box only the systemd/udev family is 4 KB-aligned.

**3.6 Newer Debian/Devuan is WORSE here, not better.** Debian armhf's default link
alignment **flipped from 64 KB → 4 KB between Stretch (2017) and Trixie (2025)** — so
on Trixie *most* of userland (incl. `grep`, `find`, `zlib`, `readline`) is 4 KB-aligned
and won't run on this 64 KB-page kernel, while Stretch is broadly 64 KB-aligned (only
systemd-family is the exception). **Stretch is the sweet spot precisely because it's
old enough.** (Buster/Bullseye were not tested; they *might* still be 64 KB-default.)

**3.7 RAID 0.90 preferred-minor is a footgun.** With in-kernel autodetect and no
initramfs, the array name comes from the superblock's preferred-minor. Assemble/write
it as `md0`/`md127` and the kernel makes the wrong node, `root=/dev/md1` is missing, and
you get a silent `panic=3` reboot loop. Re-stamp `--update=super-minor` as the **last**
array op and don't rw-mount after.

**3.8 `debugfs` reads a RAID member without assembling it.**
`debugfs -R "cat /var/log/syslog" /dev/sdX1` (or `stat`, `ls`) reads the ext3 on a 0.90
RAID member **directly** — no `mdadm`, no mount, no minor disturbance. This was the
backbone of all the post-mortem forensics.

---

## 4. No-serial debugging method (the part that's reusable anywhere)

The UART is a 1.27 mm board-edge pad; we judged it too fiddly and **never connected
serial**. With `panic=3`, every early failure is invisible. We bought back visibility with:

- **A static IP** (`192.168.0.16`) so a successful boot has a known address to ping —
  no DHCP-lease hunting.
- **A boot "breadcrumb ladder"**, each rung writing to a always-available place, so a
  post-mortem (pull drive → read) pinpoints *how far* boot got:
  1. **mount-count** on the root superblock (we `tune2fs -C 0` at flash time, so
     count ≥ 1 ⟺ the kernel mounted root) — *did the kernel mount root?*
  2. **`/INIT-RAN.txt`** written by the **first** inittab `sysinit` action (before
     `rcS`) — *did `/sbin/init` + glibc exec at all?*
  3. **`/CANARY-RAN.txt`** + a marker on the data partition from an early `rcS.d`
     script — *did rcS start?*
  4. **`first-boot-diag`** at the end of multiuser (`ip addr`, `lsmod`, `dmesg|grep pfe`,
     services, mounts) — *did it fully boot, and what's the network/firmware state?*
  5. **`net-diag`**: a **`setsid`-detached** delayed script (backgrounding from an init
     script gets killed on script exit — use `setsid`) logging `ip -s link` RX/TX
     counters, `ip neigh`, listening ports, and active pings — *is the box even
     receiving inbound frames?*
- **Reading it all back** by attaching the drive to WSL2 (`wsl --mount \\.\PHYSICALDRIVEn --bare`)
  and using `debugfs` (root fs, §3.8) + a plain read-only mount of the data partition.

Verdict logic: the highest rung present = where it died, which collapses the search
space far faster than guessing.

---

## 5. Dead-ends & rejected approaches (so you can skip them)

- **Devuan Excalibur (Trixie, glibc 2.41):** failed identically to early Stretch. We
  *first* blamed "glibc too new / `getrandom`" — **wrong**; the real cause was udev/eudev
  (proven later once Stretch failed the same way, then once the instrumented boot showed
  init *did* run). And the 64 KB-page finding (§3.6) means Trixie is non-viable on this
  kernel regardless.
- **"mke2fs 1.47 makes an unmountable fs":** disproven by a `dumpe2fs` superblock diff
  vs stock — feature-identical. Don't waste a drive cycle on this.
- **"Userland too new for the 3.2 kernel":** disproven — both Stretch (2.24) and Trixie
  (2.41) glibc declare min-kernel `3.2.0`, and the instrumented boot proved init runs.
- **Going to a *newer* distro to dodge the libsystemd stub:** rejected — newer = *more*
  4 KB-aligned landmines (§3.6).
- **dropbear instead of openssh to dodge `libsystemd`:** insufficient — Samba also pulls
  `libsystemd` (via `libsamba-util`), so you need the stub anyway.
- **Promiscuous/allmulticast mode for the inbound problem:** no effect — the PFE ignores
  Linux interface flags; the real fix was the `disable_wifi_offload` module param (§2.7).
- **Serial console:** dropped as too fiddly; replaced by §4.

---

## 6. Chronology (brief — what each phase *proved*)

1. Devuan builds (×4): silent reboot, zero rootfs writes. Found+fixed the RAID
   preferred-minor footgun. Still dead → (mis)concluded "userland too new."
2. Rebuilt on Stretch (glibc 2.24): **also** dead → broke the userland-age theory.
3. Stock-restore sanity test booted fine → proved disk + kernel + boot-chain + our
   RAID handling are all OK; **the problem was exclusively our rootfs.**
4. Offline superblock diff + ELF ABI check **disproved** both leading theories (fs &
   glibc-age). Pivoted to instrumenting the boot instead of guessing.
5. Instrumented boot: mount-count + `/INIT-RAN.txt` present, canary absent → **init runs;
   the wall is early rcS = udev.** Stubbed udev + static `/dev` → **booted to multiuser.**
6. Diag then showed two remaining bugs: PFE firmware didn't load (no udev helper) and
   `libsystemd` wouldn't load (64 KB pages). Fixed both (fw-helper; 64 KB stub).
7. Booted, networked *outbound* (NTP synced), Samba + sshd up — but **unreachable
   inbound.** Ruled out WiFi isolation (router itself couldn't reach it). Diffed stock
   `/etc/modules` → **`disable_wifi_offload=1`** → reachable. **Done.**

---

## 7. Files in this tree (artifacts)

- `build-stretch-stage{1,2,3,4}*.sh` — debootstrap + configure + bake fixes + package the rootfs tarball.
- `rootfs-stretch/` , `rootfs-stretch.tar.gz` — the built userland (the tarball is what gets flashed).
- `flash/01-backup-drive.sh` , `flash/02-flash-devuan.sh` — backup, and flash-to-md1
  (assembles md1+stamps minor, mkfs.ext3, extracts tarball, verifies all the fixes landed,
  resets mount-count baseline). *(Script name says "devuan" for historical reasons; it flashes the Stretch tarball.)*
- `harvest/` — vendor `pfe.ko` + firmware (`*_c2000.elf`), and the **libsystemd stub**
  source/map/binary (`libsystemd-stub.c`, `libsystemd.map`, `libsystemd.so.0.stub`).
- `backup-20260630/` — full stock rootfs image (`p1.img`) + kernels/configs/GPT + checksums (rollback path).
- `original_v04.01.02-417.tar.gz`, `img/`, DeBrick notes — original WD firmware references.
- `HANDOFF.md`, `RUNBOOK.md` — earlier living docs (historical; superseded by this file).

Rollback is always possible: `dd backup-20260630/p1.img -> /dev/md1` (assembled at minor 1)
restores genuine stock. Kernel partitions and the 2.7 TB data partition were never touched.

---

## 8. Open items / caveats (honest state)

- **`devtmpfs` absent** → USB-A hotplug won't auto-create nodes. We baked `sdb`/`sdb1`
  static nodes; full USB support would want more static nodes or `mdev` + an automount.
- **Passwords are still the build defaults** — `root: REDACTED`, `alpha: REDACTED`. Change them.
- On the WSL build host, remove the temporary `/etc/sudoers.d/99-claude-temp` when done.
- Samba logs harmless `SO_REUSEPORT ... Protocol not available` (old kernel; it falls back).
- **Reproducibility gap:** the Attempt-7→10 fixes (udev stub, static nodes, fw-helper,
  libsystemd stub swap, pfe params, breadcrumbs) currently live in `rootfs-stretch/` +
  `harvest/`; they are **not yet all folded back into the `build-stretch-stage*` scripts**.
  Fold them in before treating the build as from-scratch reproducible.
- IP is assigned ~5 s **before** carrier comes up (`pfe_eth_open` ~26 s, link ~31 s); the
  initial gratuitous ARP is lost. `arp_notify=1` re-announces on carrier-up; not fully
  stress-tested.
- Only this one unit tested. Partition sizes / disk model will vary across MyClouds.
