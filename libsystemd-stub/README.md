# libsystemd.so.0 — 64 KB-aligned no-op stub

## Why this exists

The vendor 3.2.26 kernel uses **64 KB pages**; every userspace ELF LOAD
segment must be 0x10000-aligned or the loader rejects it with
*"ELF load command alignment not page-aligned."* Debian Stretch armhf is
broadly 64 KB-aligned **except the systemd/udev family** — including the
real `libsystemd.so.0`, which is 4 KB-aligned and therefore unloadable.

That would kill far more than systemd (which we don't run — the box is
sysvinit): `sshd`, `smbd`/`nmbd` (via `libsamba-util`), `dbus`, `ps` and
`logger` all link `libsystemd.so.0`. Swapping openssh for dropbear does
NOT dodge it — Samba still pulls it in.

Since nothing on a sysvinit box needs libsystemd to *do* anything, the
fix is a stub: every exported symbol resolves and returns 0. The version
map (`libsystemd.map`) reproduces the real library's symbol versions so
versioned references resolve too.

## Building

Build **inside the Stretch armhf chroot** (native, via qemu binfmt),
same as everything else that runs on the box:

```sh
gcc -shared -fPIC -O2 \
    -Wl,--version-script=libsystemd.map \
    -Wl,-soname,libsystemd.so.0 \
    -Wl,-z,max-page-size=0x10000 \
    -o libsystemd.so.0.stub libsystemd-stub.c
readelf -lW libsystemd.so.0.stub | grep LOAD   # every Align must be 0x10000
```

Install over `/lib/arm-linux-gnueabihf/libsystemd.so.0`, then `ldconfig`.

## The trap to remember

`apt` still records the package as `libsystemd0` at its normal version —
**package metadata lies about what's on disk.** Any upgrade touching
libsystemd0 can silently restore the real (unloadable) library and break
the next boot. Check with:

```sh
readelf -lW /lib/arm-linux-gnueabihf/libsystemd.so.0 | grep LOAD
# 0x10000 = stub in place.  0x1000 = real lib is back; fix before rebooting.
```

Pin/hold the package, and re-check after any apt operation that mentions
systemd.
