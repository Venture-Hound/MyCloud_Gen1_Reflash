> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# CLIO — live NAS OS state (handover)

Handover for a fresh agent taking over the running **clio** NAS via SSH.
Scope: what the box IS and what constrains anything you run on it —
plus the opinionated lessons that will save you a week of dead-ends.
Pre-flash / hardware / boot-chain history is in `FINDINGS.md` and
`HANDOFF.md` — you don't need it for live operations, but it's there
if you want the full story.

**Reach it:** `ssh alpha@clio.local` (mDNS) or `ssh alpha@192.168.0.16`.
Key-based auth for `alpha` (works from the WSL2 host);
sudo pw is currently `REDACTED`. Root: `ssh root@…` with password
`REDACTED` (LAN only; will change).

## What it is

- WD MyCloud Gen 1, **Comcerto 2000** SoC (armhf, dual Cortex-A9),
  **~226 MB usable RAM** (`free -m` total).
- Vendor **kernel 3.2.26** (`uname -a` → `wd-2.4-rel armv7l`). Cannot
  be swapped — PFE ethernet has no mainline driver. Uses **64 KB pages**.
- Debian 9 **Stretch** armhf, glibc 2.24, **sysvinit-core**. No systemd
  as PID 1.
- `apt` sources → `http://archive.debian.org/debian`. Stretch is EOL;
  every apt call needs `-o Acquire::Check-Valid-Until=false`.

## The constraints that shape everything (and why)

### RAM budget: 226 MB total, ~55 MB free, ~162 MB `available`

Every added daemon is a real cost. Idle Samba (smbd + nmbd +
smbd-notifyd) + sshd + wsdd2 + chrony + rsyslog + cron + avahi sits at
~65 MB used. **Any Python-based service (christgau/wsdd, salt, ansible-
pull) will blow this budget.** Pure-C daemons only. If something can
be replaced with a smaller C thing, replace it.

### 64 KB pages — the alignment trap

The vendor kernel uses `PAGE_SIZE=65536`. Every userspace ELF
`LOAD` segment must align to `0x10000`. Debian armhf on Stretch is
broadly 64 KB-aligned; the systemd/udev family (`libsystemd.so.0`,
`libudev.so.1`, `udevadm`, `systemd-hwdb`) is the exception at 4 KB.
A 4 KB-aligned `.so` **won't load at all** — every binary linking it
dies with *"ELF load command alignment not page-aligned."*

**The exception list is NOT just systemd** (learned 2026-07-06).
A full-box scan of every `.so` found three misaligned libs:
`libudev.so.1` (4 KB, unused by design), `libdaemon.so.0` (32 KB —
this is why avahi never ran), `libXau.so.6` (32 KB — blocked
minidlna). Stretch's `libogg0` also shipped 32 KB-aligned; it was
rebuilt with correct alignment in the chroot and the package is
`apt-mark hold`-ed so an upgrade can't clobber it (same treatment for
`libxau6` once replaced). **Rule: readelf-check EVERY lib a new
package pulls in — a clean install + failed load is otherwise silent
until runtime.** Fix recipe for any small lib: fetch the stretch
`.orig.tar.gz` from archive.debian.org, chroot-native
`./configure LDFLAGS='-Wl,-z,max-page-size=0x10000' && make`, install
the built `.so` over the shipped one, `ldconfig`, `apt-mark hold`.
Backups of replaced originals: `/root/*.orig-32k` on clio.

Full-box scan one-liner (from WSL, libs pulled back via tar):
check anything you build or install:

```
readelf -lW <file> | grep LOAD    # alignment must be 0x10000
```

If you're building native, `-Wl,-z,max-page-size=0x10000` in LDFLAGS.

### Newer Debian is WORSE, not better — do not "upgrade"

Debian armhf's default link alignment **flipped from 64 KB → 4 KB
between Stretch (2017) and Trixie (2025)**. On Trixie *most* of
userland — including `grep`, `find`, `zlib`, `readline` — is
4 KB-aligned and won't run on this kernel. Stretch is the sweet spot
precisely because it's old enough that only the systemd family is the
outlier. Buster/Bullseye untested; they *might* still be 64 KB-default
but nobody has verified. **Do not attempt a distro upgrade.**

### No systemd — sysvinit end-to-end

No `systemctl`. No unit files. No `journalctl`. Services are SysV
init scripts in `/etc/init.d/`, enabled via `update-rc.d NAME
defaults`, controlled `service NAME {start,stop,status}`. Logs via
`rsyslog` to `/var/log/*`.

The reason isn't nostalgia — it's the RAM budget plus the fact that
systemd-era udev hangs the boot (next section).

### Samba init scripts are split — `Required-Start: samba` will fail

`/etc/init.d/smbd` and `/etc/init.d/nmbd` are separate; there is no
combined `samba` facility. Anything with `Required-Start: samba` in
its init header will fail `insserv` with *"Service samba has to be
enabled to start service X"*. Use `smbd nmbd` instead. Learned that
the hard way with wsdd2.

## Three invisible workarounds you MUST know about

### 1. `libsystemd.so.0` is a no-op stub — do not replace it

Debian's real `libsystemd.so.0` (4 KB-aligned) can't load on this
kernel. `/lib/arm-linux-gnueabihf/libsystemd.so.0` on the NAS is a
**64 KB-aligned, versioned, no-op stub** — the symbols resolve, calls
return safely. That is why `sshd`, `smbd`, `nmbd`, `dbus`, `ps`,
`logger` all work.

**`apt` still tracks the package** as `libsystemd0:armhf 232-25+deb9u12`.
Package versions can lie about what's on disk. Verify with:

```
readelf -lW /lib/arm-linux-gnueabihf/libsystemd.so.0 | grep LOAD
```

`0x10000` = stub. `0x1000` = whoops, real one, everything will
break next reboot. Stub source is `harvest/libsystemd-stub.c` +
`harvest/libsystemd.map` in this working dir.

**Dropbear instead of openssh does NOT dodge this** — Samba also pulls
`libsystemd` via `libsamba-util`, so you need the stub regardless.

### 2. `udev` is stubbed to no-op; `/dev` is ~144 static nodes

`/etc/init.d/udev` runs nothing but keeps `Provides: udev` so the
dependency graph stays satisfied. `udevd` is never running. Reason:
udev 232 (Stretch's version, systemd-era) hangs `rcS` early on this
kernel — silent reboot loop. It's the wall that took the longest to
find. **Don't try to fix modern udev. Go udev-less.**

Consequence: `/dev` is populated by ~144 static nodes baked at build
time. This kernel has no `CONFIG_DEVTMPFS` (a `mount -t devtmpfs`
attempt is a no-op). USB-A hotplug will NOT auto-create nodes for
plugged devices. If you need a new device node, `mknod` it manually.
**Don't install packages that depend on `libudev` / `udevadm` for
runtime behavior.**

### 3. `fw-helper` — userspace firmware loader

Pre-3.7 kernels can't load firmware directly from the filesystem —
they hand off to a userspace helper which used to be udev. We removed
udev, so `/sbin/fw-helper` fills the role. It's wired via:

```
echo /sbin/fw-helper > /proc/sys/kernel/hotplug
```

This happens in eth0's `pre-up` **before** the PFE driver calls
`request_firmware()`. If a driver ever times out with `probe failed
-110 (ETIMEDOUT)`, the helper isn't set / isn't reachable. Check
that first.

## eth0 is the only NIC and it is load-bearing — do NOT touch it

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    pre-up echo /sbin/fw-helper > /proc/sys/kernel/hotplug
    pre-up modprobe pfe disable_wifi_offload=1 lro_mode=1 tx_qos=1 alloc_on_init=1
    pre-up sleep 3
    address 192.168.0.16
    netmask 255.255.255.0
    gateway 192.168.0.1
    dns-nameservers 192.168.0.1 1.1.1.1
    post-up sysctl -w net.ipv4.conf.eth0.arp_notify=1 2>/dev/null || true
```

Each line is load-bearing:

- **`fw-helper` echo** — see §3 above. Firmware loading depends on it.
- **`disable_wifi_offload=1`** is the difference between "on the
  network" and "invisible." Without it, the PFE brings up its
  VWD/wifi-offload datapath and **hijacks host-bound RX**. Outbound
  works, unicast inbound works (NTP synced fine during the debug!),
  but inbound *broadcast* — ARP "who-has .16" — never reaches the
  Linux stack. The box answers nobody. The finding was: **the box
  looks 100% healthy from inside yet is unreachable.** If a rebuilt
  MyCloud ever pings out but nothing can ping it, this is almost
  certainly why.
- **`lro_mode=1 tx_qos=1 alloc_on_init=1`** — stock parameter set. Do
  not remove.
- **`sleep 3`** — pfe finishes bringing up the interface. Untested
  headroom either way.
- **`arp_notify=1`** — carrier comes up ~26–31 s after boot but the
  DHCP-style gratuitous ARP fires ~5 s in and is lost. `arp_notify`
  re-announces on carrier-up. **Not fully stress-tested for link-flap
  edge cases.**

**Read-only network inspection** (`ip`, `ss`, `netstat`, `tcpdump`,
`ip neigh`) is safe. **Do not** stop/rename/reconfigure `eth0` from
a session — you lose the box, and there's no serial console to
recover.

Also baked at `/etc/modprobe.d/pfe.conf` (belt-and-braces so a manual
`modprobe pfe` gets the right params too):

```
options pfe lro_mode=1 tx_qos=1 alloc_on_init=1 disable_wifi_offload=1
```

**IPv6 is fully up on eth0** — global address, ULA, and link-local
(3 addresses). This surprised us during wsdd2 debugging and is
relevant if you touch anything that iterates interface addresses.

## What's running right now (verified 2026-07-06)

Daemons: `sshd`, `smbd` + `nmbd` + `smbd-notifyd`, `wsdd2`, `chronyd`,
`rsyslogd`, `cron`, `lighttpd` (admin panel, port 80). Optional/off:
`minidlnad` (DLNA for the music share, toggled from the panel).

- **Time:** `chronyd` synced to debian pool (outbound-only NTP; the
  Sky router offers no NTP — tested). The vendor RTC drifts to 2012
  without NTP; chrony fixes it. Don't disable it.
- **avahi-daemon is DISABLED — and it never actually ran.** It can't:
  `libdaemon.so.0` is 32 KB-aligned. Every earlier "clio.local
  resolves" observation traced back to hosts-file entries or
  ~/.ssh/config, not mDNS. Flat names (`\\CLIO`, `http://clio/`)
  resolve fine from Windows via LLMNR (wsdd2) + NetBIOS (nmbd) + WSD.
  If `.local` names are ever wanted: rebuild libdaemon 64 KB-aligned
  (recipe above), re-enable avahi.
- **SSH:** `PermitRootLogin yes` (LAN only); `alpha` uses pubkey auth.
- **Admin panel:** `http://clio/` — digest auth, user `alpha`. Source
  + deploy script in `nas-panel/` in this working dir; the only
  privileged entry point is `/usr/local/lib/nas-panel/panel-op`
  (sudoers: `/etc/sudoers.d/nas-panel`).
- **wsdd2 depends on `/etc/machine-id`** (copied from
  `/var/lib/dbus/machine-id`, 2026-07-05). If it's ever missing,
  Explorer discovery silently dies — see `HANDOVER-SMB-WSDD.md`.
- `/etc/services` does not exist on the box. Nothing currently cares
  (wsdd2 falls back to hardcoded ports), but `getservbyname()` users
  will get NULL — restore from the `netbase` package if ever needed.

## USB-A port (assessed 2026-07-06, works)

`usb-storage` + `sd` are **built into** the vendor kernel. Static
nodes `/dev/sdb`–`sdb8`, `/dev/sdc`–`sdc8` are baked (no udev — new
nodes need mknod). Vendor-harvested `vfat`/`fat`/`msdos`/`fuse`/`xfs`
modules load fine (tested with a real FAT32 stick incl. long
filenames). NTFS/exFAT would need `ntfs-3g`/`exfat-fuse` packages
(alignment-check them!). **No automount** — mount/eject via the admin
panel (Status page), which picks the largest mountable partition and
exposes it as `\\CLIO\usb`.

## Vendor LED driver — COLOR-ONLY, never touch blink

`/sys/class/leds/system_led` (`color`: blue/red/green/yellow/white
all accepted; `brightness`; `blink`). Hard-won facts (2026-07-06):

- **`brightness` writes kernel-oops intermittently**
  (`led_brightness_store` → "bad PC value"; writing process dies,
  kernel survives, taint accumulates). Reproduced multiple times.
- **The `blink` attribute is write-dead** — reads "on" regardless of
  writing off/0/none. Attempting to manage it is pointless and the
  brightness+blink combination is where crashes clustered.
- **`color` writes have never crashed** across dozens of writes.

Policy baked into `led-status`/`panel-op led_set`: write `color` only
on state change (cache `/var/run/nas-led.state`), write `brightness`
only if it isn't already 255 (once per boot — boot default is 0 =
LED dark), NEVER write `blink`. Any new LED code must follow this.
Meaning: blue=good, yellow=service down/fs≥90%, red=SMART FAILED or
RAID degraded (solid — blink is not usable).

## Two quirks that look like problems but aren't

**Load average reads 3.00 with 100% idle CPU.** Kernel D-state
artifact — a stuck `cpu1_hotpl+` worker in uninterruptible sleep adds
~1 to the load average forever. Cosmetic. **Don't chase it.**

**Samba logs harmless `SO_REUSEPORT ... Protocol not available`.** The
3.2.26 kernel doesn't support `SO_REUSEPORT`; Samba falls back cleanly.
Ignore it.

## Package-install caveats — trust nothing without `dpkg -l`

The build scripts (`build-stretch-stage{2,3}.sh`) wrap almost every
`apt-get install` and every `smbpasswd` call in `|| true`. **A silent
install failure is entirely possible** and has happened before. Always
`dpkg -l | grep <pkg>` before trusting a package is present.

For anything you need to `apt install` now:

```
sudo apt-get -o Acquire::Check-Valid-Until=false update
sudo apt-get install -y <pkg>
```

Since installed (2026-07-05/06): `smbclient`, `tcpdump`,
`smartmontools` (smartctl only — smartd deliberately not enabled),
`lighttpd`, `minidlna`. Still absent: `strace`, `binutils`/`readelf`
(pull binaries back over scp and readelf them on the WSL host
instead), `nslookup`/`dig`.

## Credentials as-baked (change before this ever leaves LAN)

- root: `REDACTED`
- alpha (system + sudo): `REDACTED`
- alpha (SMB): `REDACTED` — SMB user record exists in the passdb
  (`pdbedit -L` confirms `alpha:1000:`, password last set 2026-07-01)

`/etc/sudoers.d/99-claude-temp` on the WSL2 build host is a temporary
passwordless-sudo grant for this project. **Remove when done.**

## Ranked dead-ends worth NOT repeating

Sorted by how much time each one costs before you realise:

1. **"Modern udev just needs a config tweak."** No. Modern udev
   hangs the boot at `S02udev`. You will spend days on this. Go
   udev-less.
2. **"Newer distro will have the modern fixes."** No — 64 KB → 4 KB
   alignment flip makes it *worse*. Stay on Stretch.
3. **"mke2fs 1.47 makes an unmountable fs."** Disproven by
   `dumpe2fs` diff vs stock — feature-identical. Don't waste a drive
   cycle on this.
4. **"Userland too new for the 3.2 kernel."** Disproven — both
   Stretch (2.24) and Trixie (2.41) glibc declare min-kernel `3.2.0`.
   Instrumented boot proved init runs. Look elsewhere.
5. **"Dropbear instead of openssh dodges `libsystemd`."** Samba
   pulls `libsystemd` via `libsamba-util`. You need the stub anyway.
6. **"Promiscuous / allmulticast mode fixes the inbound problem."**
   No — the PFE ignores Linux interface flags. Real fix is the
   `disable_wifi_offload` module param.
7. **"The vendor kernel supports CONFIG_DEVTMPFS."** No. Verify with
   `mount -t devtmpfs devtmpfs /tmp/x` — silent no-op. Static nodes it is.
8. **Cross-compile from Ubuntu 24.04 toolchain.** Header rot
   (`__time64`, `__isoc23_*`, `GLIBC_2.34`+ symbols) leaks into
   objects and won't link against Stretch's glibc 2.24. Do
   **chroot-native** builds via `qemu-arm-static` — see the wsdd2
   handover for the recipe.

## Debugging techniques that work here

- **`debugfs`** reads the ext3 rootfs without assembling md1 —
  `debugfs -R "cat /path" /dev/sdX1`. Useful during offline forensics
  if the box ever won't boot again. Not relevant while running.
- **Boot breadcrumbs** — the tarball still bakes an init marker
  (`/INIT-RAN.txt`), an rcS canary (on `/srv/nas/.canary/…`), and
  a full first-boot diag under `/srv/nas/first-boot-diag/`. If the
  box ever won't boot, pull the drive, `debugfs -R "cat /INIT-
  RAN.txt"` + ro-mount sda4 for the rest. See `FINDINGS.md §4` for
  the ladder.
- **Reproducibility gap** — the Attempt-7→10 fixes (udev stub,
  static nodes, fw-helper, libsystemd stub, pfe params, breadcrumbs)
  live in `rootfs-stretch/` + `harvest/` but are **not all folded
  back** into `build-stretch-stage*` yet. The tarball is the source
  of truth for from-scratch reproducibility right now. Everything
  applied ON TOP of the flashed image since 2026-07-05 (machine-id,
  users/shares, panel, recycle, USB, DLNA, rebuilt libs) is scripted
  and ordered in `REBUILD-DELTA.md` in this working dir.

## What is NOT known — do not assert

- Buster/Bullseye armhf: 64 KB-aligned or not? Untested.
- `arp_notify` under link-flap edge cases: not stress-tested.
- Concurrent Samba client behavior under RAM pressure: not tested.
- IPv6 end-to-end beyond default link-local + the wsdd2 attempts:
  not exercised.
- Anything about disks other than the WD30EFRX in this unit.

## Rules for anyone touching this box

1. Don't touch the kernel, PFE modules, or `eth0` config.
2. Don't add systemd anything. Don't install packages that link
   `libudev`. Don't replace `libsystemd.so.0` — check its alignment
   first.
3. Don't upgrade to a newer Debian.
4. `dpkg -l | grep <pkg>` before trusting anything the build "installed."
5. `readelf -lW ... | grep LOAD` before trusting anything you built
   or downloaded — align must be `0x10000`.
6. Prefer read-only diagnostics. Take a backup of `/etc` files before
   editing (no dotfile sync anywhere on this box).
