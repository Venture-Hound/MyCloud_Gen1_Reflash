# Rebuilding misaligned libraries for the 64 KB-page kernel

Some Stretch armhf packages ship libraries with ELF LOAD alignment below
0x10000. They install cleanly and then simply refuse to load at runtime
(`ELF load command alignment not page-aligned`). A **full-box scan**
(`tools/alignment-scan.sh`) found exactly three misaligned libraries on
the finished system, plus one more that arrived with minidlna:

| Library | Shipped align | Consequence |
|---|---|---|
| `libudev.so.1` | 4 K | none — nothing we run loads it (udev-less design) |
| `libdaemon.so.0` | 32 K | **avahi-daemon can never run** (it fails silently; `.local` mDNS was never actually served) |
| `libXau.so.6` | 32 K | blocks `minidlnad` |
| `libogg.so.0` | 32 K | blocks `minidlnad` |

No binaries are shipped here — just the recipe. Build **native in the
Stretch chroot** (qemu binfmt); cross-compiling from a modern host leaks
glibc symbol versions and time64 types that Stretch's glibc 2.24 lacks.

```sh
# 1. fetch the Stretch-era source (archive.debian.org)
#    e.g. libogg_1.3.2.orig.tar.gz, libxau_1.0.8.orig.tar.gz
# 2. inside the armhf chroot:
sudo chroot rootfs-stretch /bin/bash -c "
  cd /root && tar xzf <lib>_<ver>.orig.tar.gz && cd <lib>-<ver> &&
  ./configure --prefix=/usr --libdir=/usr/lib/arm-linux-gnueabihf \
      LDFLAGS='-Wl,-z,max-page-size=0x10000' && make -j2"
# 3. verify BEFORE deploying:
readelf -lW <built .so> | grep LOAD        # every Align must be 0x10000
# 4. on the box: install -m644 over the shipped .so, ldconfig
# 5. pin it so apt can't clobber the fix:
apt-mark hold <package>                    # e.g. libogg0, libxau6
```

Keep the replaced originals (`/root/*.orig-32k` on our box) so the swap
is reversible and auditable.

**Rule that saves you here:** readelf-check every library a new package
pulls in, at install time — a clean install plus a misaligned lib is
silent until whatever needs it mysteriously won't start.
