#!/bin/bash
# Stage 2 (Stretch): configure the Debian 9 armhf rootfs for the WD MyCloud
# (Comcerto 2000). This is the stage that makes the box actually BOOT and
# be REACHABLE on the vendor 3.2.26 / 64 KB-page kernel — every step below
# fixes one of the walls documented in docs/03-choosing-an-os.md,
# docs/04-building-the-rootfs.md and docs/06-the-network-was-lying.md.
# Run from the repo root: bash build/build-stretch-stage2.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-$REPO/rootfs-stretch}"
HARVEST="${HARVEST:-$REPO/harvest/vendor-kernel-bits.tgz}"   # see docs/harvesting-vendor-bits.md — WD-proprietary, not shipped here
OVERLAY="$REPO/rootfs-overlay"
SP="${SP:-$REPO/.build-scratch}"
ROOTPW="CHANGE_ME_root_password"   # baked as literal text below — replace before flashing, or edit right after first boot
mkdir -p "$SP"

echo ">>> [1] debootstrap second stage (qemu-arm-static)"
[ -d "$TARGET/debootstrap" ] && sudo chroot "$TARGET" /debootstrap/debootstrap --second-stage

echo ">>> [1b] static /dev nodes — MUST run before the /dev bind mount in [3]"
# CRITICAL ORDERING. These nodes have to be created while $TARGET/dev is the
# real rootfs directory. If we waited until after step [3] bind-mounts the
# host's /dev over $TARGET/dev, every mknod would succeed but land in the
# HOST's /dev, then vanish from the rootfs the instant the bind mount is torn
# down — shipping a /dev with only the ~8 base nodes debootstrap makes. This
# kernel has no devtmpfs and udev is stubbed to a no-op, so nothing recreates
# them at boot: a short /dev is an unbootable (or at least unmountable /srv,
# no-ttyS0) box. dev-nodes.sh now also refuses to run against a mountpoint as
# a backstop. See docs/04-building-the-rootfs.md.
sudo TARGET="$TARGET" sh "$OVERLAY/dev-nodes.sh"

echo ">>> [2] apt sources (archive.debian.org) + accept expired Release"
sudo tee "$TARGET/etc/apt/sources.list" >/dev/null <<EOF
deb http://archive.debian.org/debian stretch main contrib non-free
deb http://archive.debian.org/debian-security stretch/updates main contrib non-free
EOF
sudo tee "$TARGET/etc/apt/apt.conf.d/99archive" >/dev/null <<EOF
Acquire::Check-Valid-Until "false";
APT::Install-Recommends "false";
EOF
echo ">>> [2b] install archive keyring into rootfs"
sudo mkdir -p "$TARGET/usr/share/keyrings" "$TARGET/etc/apt/trusted.gpg.d"
sudo cp "$SP/dak/usr/share/keyrings/debian-archive-keyring.gpg" "$TARGET/usr/share/keyrings/"
sudo cp "$SP/dak/usr/share/keyrings/debian-archive-keyring.gpg" "$TARGET/etc/apt/trusted.gpg.d/"

echo ">>> [3] bind mounts"
sudo mount -t proc proc "$TARGET/proc"
sudo mount -t sysfs sys "$TARGET/sys"
sudo mount -o bind /dev "$TARGET/dev"
sudo mount -o bind /dev/pts "$TARGET/dev/pts"
trap 'sudo umount -l "$TARGET/dev/pts" "$TARGET/dev" "$TARGET/sys" "$TARGET/proc" 2>/dev/null || true' EXIT

echo ">>> [4] essential userland (sysvinit as PID1, NOT systemd, NOT real udev)"
# Deliberately NOT installing the 'udev' package: modern udev (v232 on
# Stretch) hangs rcS on this kernel — the single most expensive discovery
# of this project (docs/05-flying-blind.md). We ship a no-op stub instead
# (step [9] below) that still Provides: udev so insserv's dependency graph
# stays satisfied.
sudo chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -e <<'CHROOT'
apt-get update
apt-get install -y --no-install-recommends \
  sysvinit-core insserv kmod \
  ifupdown isc-dhcp-client iproute2 iputils-ping \
  openssh-server net-tools nano less ca-certificates tzdata wget gnupg \
  samba-vfs-modules
apt-get clean
# make absolutely sure systemd is not PID1
dpkg -l systemd-sysv 2>/dev/null | grep -q '^ii' && apt-get purge -y systemd-sysv || true
CHROOT

echo ">>> [4b] libsystemd.so.0 — 64K-aligned no-op stub"
# sshd, smbd/nmbd (via libsamba-util) and dbus all link libsystemd.so.0
# even though nothing here runs systemd. The real Stretch armhf lib is
# 4K-aligned and won't load on a 64K-page kernel. Build our own stub
# (see libsystemd-stub/README.md — same recipe, run here instead of by
# hand) and pin it so a later apt operation can't silently restore the
# unloadable original.
sudo chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -e <<'CHROOT'
apt-get install -y --no-install-recommends libsystemd0 build-essential
CHROOT
sudo mkdir -p "$TARGET/root/libsystemd-stub"
sudo cp "$REPO/libsystemd-stub/libsystemd-stub.c" "$REPO/libsystemd-stub/libsystemd.map" "$TARGET/root/libsystemd-stub/"
sudo chroot "$TARGET" /bin/bash -e <<'CHROOT'
cd /root/libsystemd-stub
gcc -shared -fPIC -O2 \
    -Wl,--version-script=libsystemd.map \
    -Wl,-soname,libsystemd.so.0 \
    -Wl,-z,max-page-size=0x10000 \
    -o libsystemd.so.0.stub libsystemd-stub.c
install -m644 libsystemd.so.0.stub /lib/arm-linux-gnueabihf/libsystemd.so.0
ldconfig
apt-mark hold libsystemd0
cd /
rm -rf /root/libsystemd-stub
apt-get purge -y build-essential
apt-get autoremove -y
apt-get clean
CHROOT
echo "    verify: readelf -lW $TARGET/lib/arm-linux-gnueabihf/libsystemd.so.0 | grep LOAD   (must be 0x10000)"

echo ">>> [5] vendor kernel modules + firmware + autoload"
sudo tar xzf "$HARVEST" -C "$TARGET" lib/modules lib/firmware

echo ">>> [6] rootfs-overlay/ — the hand-won fixes, as real files"
# Everything below is documented file-by-file in rootfs-overlay/README.md.
sudo cp "$OVERLAY/etc/init.d/udev"      "$TARGET/etc/init.d/udev"
sudo cp "$OVERLAY/etc/init.d/devfs"     "$TARGET/etc/init.d/devfs"
sudo cp "$OVERLAY/etc/init.d/initmarker" "$TARGET/etc/init.d/initmarker"
sudo cp "$OVERLAY/etc/init.d/canary"    "$TARGET/etc/init.d/canary"
sudo cp "$OVERLAY/etc/init.d/firstboot-diag" "$TARGET/etc/init.d/firstboot-diag"
sudo chmod +x "$TARGET"/etc/init.d/{udev,devfs,initmarker,canary,firstboot-diag}
sudo cp "$OVERLAY/etc/inittab" "$TARGET/etc/inittab"
sudo cp "$OVERLAY/sbin/fw-helper" "$TARGET/sbin/fw-helper"
sudo chmod +x "$TARGET/sbin/fw-helper"
sudo cp "$OVERLAY/etc/network/interfaces" "$TARGET/etc/network/interfaces"
sudo cp "$OVERLAY/etc/modprobe.d/pfe.conf" "$TARGET/etc/modprobe.d/pfe.conf"
# (the 37 static /dev nodes were already baked in step [1b], before /dev was
# bind-mounted — doing it here instead would silently write them to the host)
# udev is a direct inittab sysinit action (devfs/initmarker), NOT
# insserv-managed — no update-rc.d needed for those. The no-op udev
# stub DOES go through insserv (it Provides: udev for the dependency
# graph), so register it:
sudo chroot "$TARGET" update-rc.d udev defaults 2>&1 | tail -2 || true
sudo chroot "$TARGET" update-rc.d canary defaults 2>&1 | tail -2 || true
sudo chroot "$TARGET" update-rc.d firstboot-diag defaults 2>&1 | tail -2 || true

echo ">>> [7] resolv.conf (interfaces file itself now comes from rootfs-overlay/)"
sudo tee "$TARGET/etc/resolv.conf" >/dev/null <<EOF
nameserver 192.168.0.1
nameserver 1.1.1.1
EOF

echo ">>> [8] fstab"
sudo tee "$TARGET/etc/fstab" >/dev/null <<EOF
/dev/md1   /            ext3  defaults,noatime,nodiratime,errors=remount-ro  0 1
/dev/sda4  /srv/nas     ext4  defaults,noatime,nofail                        0 2
proc       /proc        proc  defaults                                       0 0
tmpfs      /tmp         tmpfs defaults,size=100M,nr_inodes=20k               0 0
EOF
sudo mkdir -p "$TARGET/srv/nas"

echo ">>> [9] hostname/hosts"
echo clio | sudo tee "$TARGET/etc/hostname" >/dev/null
sudo tee "$TARGET/etc/hosts" >/dev/null <<EOF
127.0.0.1   localhost
127.0.1.1   clio
EOF

echo ">>> [10] ssh permit root (LAN only, initial)"
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$TARGET/etc/ssh/sshd_config"

echo ">>> [11] machine-id (wsdd2 dies silently without this — see docs/08-samba-and-discovery.md)"
# /etc/machine-id is a systemd-ism read by wsdd2's uuid_endpoint(); it
# needs exactly 32 lowercase hex chars. No dbus dependency needed —
# generate it directly.
head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n' | sudo tee "$TARGET/etc/machine-id" >/dev/null
sudo chmod 444 "$TARGET/etc/machine-id"

echo ">>> [12] root password + cleanup qemu"
echo "root:${ROOTPW}" | sudo chroot "$TARGET" /usr/sbin/chpasswd
sudo rm -f "$TARGET/usr/bin/qemu-arm-static"
echo ">>> STAGE 2 COMPLETE"; sudo du -sh "$TARGET" 2>/dev/null || true
