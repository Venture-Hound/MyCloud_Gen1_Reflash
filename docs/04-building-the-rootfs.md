# 4 · Building the rootfs

*(Status: outline — to be drafted.)*

Covers:

- `debootstrap --arch=armhf --variant=minbase stretch` from
  archive.debian.org, staged builds under qemu-arm-static binfmt.
- **sysvinit end-to-end** — no systemd as PID 1 (RAM budget + the udev
  wall), no journalctl, `update-rc.d`/`service` idioms.
- **The udev-less design** (the project's most expensive lesson,
  discovered in ch. 5): udev v232 hangs rcS on this kernel; the fix is
  a no-op init stub that still `Provides: udev`, plus 37 static `/dev`
  nodes (this kernel has no `CONFIG_DEVTMPFS` — the best-effort devtmpfs
  mount in `rootfs-overlay/etc/init.d/devfs` is a silent no-op here).
- **The libsystemd stub** — why sshd/smbd/dbus need it even with no
  systemd anywhere (see `libsystemd-stub/README.md`), and the
  "apt says the package is fine, readelf says otherwise" trap.
- `sbin/fw-helper` — firmware loading on a pre-3.7 kernel once udev is
  gone (detail in ch. 6).
- Build stages 1–4 and how they consume `rootfs-overlay/` (single
  reproducible build; verify a fresh stage-4 tarball against a known
  good one before flashing).
- Baked diagnostics (initmarker/canary/firstboot-diag) — wired here,
  explained in ch. 5.

Sources: `build/`, `rootfs-overlay/`, `libsystemd-stub/`,
`field-notes/FINDINGS.md` §2.

## What the first folded build run found (2026-07-09)

The stage scripts fold together fixes that were each proven in isolation during
the original project. This section records what happened the first time they
were all run in one clean pass — because "each fix works alone" and "all the
fixes work together" are different claims, and exactly one of them was false.

### Bug: a rootfs that ships 8 `/dev` nodes instead of 37 — and the build still exits 0

**Symptom.** The first clean stage1→stage4 run returned 0 at every stage, yet
the packaged tree's `/dev` held only the ~8 nodes debootstrap makes, not the 37
the box needs. On this kernel — no `CONFIG_DEVTMPFS`, udev stubbed to a no-op —
nothing recreates device nodes at boot, so a rootfs missing `/dev/md1`,
`/dev/sda4`, `/dev/ttyS0` and the rest is unbootable / can't mount `/srv/nas`.
Nothing warned: every `mknod` had "succeeded".

**Evidence.** The *build host's* own `/dev` had grown exactly the nodes
`dev-nodes.sh` creates, with the exact major/minors it uses — `md1` (9,1),
`sda` (8,0), `sdb` (8,16), `sdc` (8,32). A WSL2 host has no md RAID, so
`/dev/md1` sitting on the host was the smoking gun.

**Cause.** Stage 2 bind-mounts the host's `/dev` over `$TARGET/dev` (step [3])
so apt's maintainer scripts inside the chroot can reach `/dev/null` etc. The
folded-in `dev-nodes.sh` call sat *after* that mount (in step [6]), so every
`mknod` landed in the host's `/dev` — the bind target — not the rootfs. When
the mount was torn down before packaging, the 37 nodes vanished and the tarball
shipped only the base nodes underneath. Classic bind-mount shadowing, and
silent, because `mknod` onto the bind mount succeeds. A textbook
"works alone, breaks together": `dev-nodes.sh` had been verified in isolation
(37/37 nodes, exact major/minors) — but against an *unmounted* directory.

**Fix.** Create the static nodes *before* `/dev` is ever bind-mounted — stage 2
now runs `dev-nodes.sh` as step **[1b]**, right after the second-stage
debootstrap and before the step-[3] mounts. The bind mount then just shadows
the real nodes (as intended) and they reappear on unmount. As a backstop,
`dev-nodes.sh` now refuses to run if its target `/dev` is a mountpoint —
turning a silent misfire into a loud error. Verified: the corrected run bakes
37 nodes and they survive into the tarball.

### Not a bug: the alignment scan's scary-looking output

A whole-tree run of `tools/alignment-scan.sh` flags ~34 items at 4K alignment
that are **not** problems, and the why is worth a paragraph.

On a 64 KB-page kernel a *shared object* (`.so`) that isn't 64K-aligned won't
load: `ld.so` mmaps its LOAD segments strictly, so a 4K/32K lib dies at runtime
with "ELF load command alignment not page-aligned" — silently, no apt warning.
That is the entire reason the libsystemd stub and the libdaemon/libXau/libogg
rebuilds exist.

*Main executables are different.* This kernel's ELF loader runs 4K-aligned
armhf binaries fine — verified on the live box, where stock `mawk` (awk),
`less` and `touch` are 4K-aligned and execute normally. So the 4K flags for
awk/less/nano/touch/pinentry/lzma/rmt are cosmetic, as are the Comcerto PFE
firmware `.elf` blobs (`class`/`util`/`tmu_c2000.elf`) — those aren't Linux
binaries; they run on the packet engine. The scanner's old comment claimed a
"full-box scan found exactly three" offenders, which was misleading: its own
usage only scanned `/lib`, `/usr/lib`, `/usr/local` and never `/usr/bin`. It
now *fails* only on misaligned shared objects, prints executables/firmware as
informational `note`, and allow-lists two harmless 4K libs a good build always
carries — `libudev.so.1` (a base dependency nothing loads) and
`libsystemd.so.0.17.0` (the real lib, orphaned when the stub replaced the
`libsystemd.so.0` symlink). A clean build reports `misaligned_libs=0`.

### Everything else verified clean

The other four "never run together" risks all held:

- **udev stays gone** — the udev *package* is never installed (only `libudev1`,
  the harmless lib); `dpkg -l` confirms it, and the no-op stub registers at
  `rcS.d/S02udev`.
- **The libsystemd stub survives stage 3's apt** — after the full build,
  `libsystemd0` is `hold ok installed` and `libsystemd.so.0` is still the 64K
  stub (LOAD `0x10000`), not restored to the 4K original.
- **wsdd2's Makefile honours the passed LDFLAGS** — the link line reads
  `cc -Wl,-z,max-page-size=0x10000 … -o wsdd2`; the binary is `0x10000`.
- **`samba-vfs-modules` yields a loadable `recycle.so`** — present and
  `0x10000`, so `vfs objects = recycle` actually works instead of failing the
  tree connect.

A full, path-genericised capture of the corrected run — benign warnings
annotated at the top — is in [`reference-build.log`](reference-build.log).
