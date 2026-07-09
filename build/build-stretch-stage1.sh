#!/bin/bash
# Stage 1 (Stretch): debootstrap Debian 9 armhf minbase from archive.debian.org.
# Stretch glibc 2.24 runs on the vendor 3.2.26 kernel (Devuan Trixie/glibc 2.41 did NOT
# — see docs/03-choosing-an-os.md).
# Run from the repo root: bash build/build-stretch-stage1.sh
set -e
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-$REPO/rootfs-stretch}"
MIRROR=http://archive.debian.org/debian
SP="${SP:-$REPO/.build-scratch}"
mkdir -p "$SP"; cd "$SP"

echo ">>> fetching Debian archive keyring (for verification) from stretch"
KF=$(curl -s "$MIRROR/dists/stretch/main/binary-armhf/Packages.gz" | zcat \
      | awk '/^Package: debian-archive-keyring$/{p=1} p&&/^Filename:/{print $2; exit}')
KEYRING_OPT="--no-check-gpg"
if [ -n "$KF" ]; then
  curl -s -o dak.deb "$MIRROR/$KF"
  rm -rf dak && mkdir dak && dpkg-deb -x dak.deb dak
  GPG=$(find dak -name 'debian-archive-keyring.gpg' | head -1)
  [ -n "$GPG" ] && KEYRING_OPT="--keyring=$GPG" && echo "  keyring: $GPG"
fi
echo "  keyring opt: $KEYRING_OPT"

echo ">>> debootstrap stage 1 (foreign, armhf, minbase, no-merged-usr)"
sudo rm -rf "$TARGET"
sudo debootstrap --foreign --arch=armhf --variant=minbase --no-merged-usr \
  $KEYRING_OPT stretch "$TARGET" "$MIRROR"

echo ">>> copy qemu-arm-static for the second stage"
# Requires qemu-arm-static registered in binfmt_misc on the HOST with the
# 'F' (fix binary) flag, so later stages can remove this copy from the
# chroot without breaking anything — the kernel already holds an fd to
# the real interpreter from registration time.
sudo cp /usr/bin/qemu-arm-static "$TARGET/usr/bin/"
echo ">>> STAGE 1 COMPLETE"; sudo du -sh "$TARGET"
