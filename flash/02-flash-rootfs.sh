#!/bin/bash
# Write the Stretch rootfs onto the MyCloud's root RAID (md1 over sdX1+sdX2).
# Keeps the vendor kernel (parts 5/6), config (7/8) and data (4) untouched.
# Run on WSL2 host AFTER 01-backup-drive.sh, with the drive attached (wsl --mount --bare).
# Usage:  sudo bash 02-flash-rootfs.sh /dev/sdX
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="${1:?usage: 02-flash-rootfs.sh /dev/sdX}"
TARBALL="${TARBALL:-$REPO/rootfs-stretch.tar.gz}"
[ -f "$TARBALL" ] || { echo "missing $TARBALL — run the build (stages 1-4) first"; exit 1; }

echo "=== assemble the root RAID from ${DEV}1 + ${DEV}2 (metadata 0.90) ==="
# CRITICAL: assemble as md1 and stamp preferred-minor=1. The vendor U-Boot
# bootargs hardcode `root=/dev/md1 raid=autodetect noinitrd` (no initramfs), so
# the kernel's in-kernel autodetect names the array purely from the 0.90
# superblock's preferred-minor field. Assembling/writing as md0 rewrites that to
# 0 -> kernel brings it up as /dev/md0 -> root=/dev/md1 missing -> panic=3 reboot
# loop (silent: no serial, no rootfs writes). --update=super-minor pins it to 1.
sudo mdadm --stop --scan 2>/dev/null || true
MD=/dev/md1
sudo mdadm --assemble --run --update=super-minor "$MD" "${DEV}1" "${DEV}2" 2>/dev/null \
  || sudo mdadm --assemble --run "$MD" "${DEV}1" "${DEV}2" 2>/dev/null \
  || sudo mdadm --assemble --run --scan 2>/dev/null || true
# find whichever md now contains our members
MD=$(lsblk -nro NAME "${DEV}1" | awk 'NR==2{print "/dev/"$1}')
[ -z "$MD" ] && MD=$(ls /dev/md* 2>/dev/null | head -1)
echo "root array = $MD"
sudo mdadm --examine "${DEV}1" | grep -i 'Preferred Minor'   # must read 1
sudo mdadm --detail "$MD" | grep -iE "version|raid level|state|devices" | head

read -rp "About to mkfs.ext3 $MD (wipes stock rootfs; backup done?) [type YES] " ok
[ "$ok" = "YES" ] || { echo "aborted"; exit 1; }

echo "=== mkfs ext3 (matches kernel cmdline rootfstype=ext3) ==="
sudo mkfs.ext3 -L rootfs "$MD"

echo "=== extract Stretch rootfs ==="
MNT=$(mktemp -d)
sudo mount "$MD" "$MNT"
sudo tar --numeric-owner --xattrs -xzf "$TARBALL" -C "$MNT"
sync
echo "=== verify key bits landed ==="
ls "$MNT/lib/modules/3.2.26/pfe.ko" && echo "  pfe.ko OK"
ls "$MNT"/lib/firmware/*c2000.elf && echo "  firmware OK"
# No active serial getty by design (see rootfs-overlay/etc/inittab) — the
# UART was never wired up, so we don't check for one here.
if grep -q '^ma::sysinit:/etc/init.d/initmarker' "$MNT/etc/inittab" && [ -x "$MNT/etc/init.d/initmarker" ]; then
  echo "  init marker wired OK (writes /INIT-RAN.txt before rcS)"
else
  echo "  !! init marker MISSING — rebuild (stage2 + stage4) before flashing"; exit 1
fi
if grep -q '^df::sysinit:/etc/init.d/devfs' "$MNT/etc/inittab" && [ -x "$MNT/etc/init.d/devfs" ]; then
  echo "  devtmpfs sysinit wired OK (populates /dev before rcS, udev-less)"
else
  echo "  !! devfs sysinit MISSING — rebuild before flashing"; exit 1
fi
if grep -q DISABLED "$MNT/etc/init.d/udev"; then
  echo "  udev stubbed OK (udevd never starts; it was hanging the 3.2.26 boot)"
else
  echo "  !! udev NOT stubbed — would hang on 3.2.26; rebuild"; exit 1
fi
[ -b "$MNT/dev/sda4" ] && [ -b "$MNT/dev/md1" ] && echo "  static fallback /dev nodes OK"
LSALIGN=$(readelf -lW "$MNT/lib/arm-linux-gnueabihf/libsystemd.so.0" 2>/dev/null | awk '/LOAD/{print $NF; exit}')
if [ "$LSALIGN" = "0x10000" ]; then echo "  libsystemd 64K-aligned stub OK (loads on 64K-page kernel)"; else
  echo "  !! libsystemd align=$LSALIGN (need 0x10000 for 64K-page kernel) — rebuild stub"; exit 1; fi
[ -x "$MNT/sbin/fw-helper" ] && echo "  fw-helper present OK" || { echo "  !! fw-helper MISSING"; exit 1; }
grep -q 'modprobe pfe' "$MNT/etc/network/interfaces" && echo "  pfe firmware-load via eth0 pre-up OK"
if grep -q '^pfe' "$MNT/etc/modules" 2>/dev/null; then echo "  !! pfe still in /etc/modules (loads before fw-helper)"; exit 1; else echo "  pfe deferred out of /etc/modules OK"; fi

sudo umount "$MNT"; rmdir "$MNT"
echo "=== reset fs mount-count baseline to 0 (a boot that mounts root will make it >=1) ==="
sudo tune2fs -C 0 "$MD"
sudo tune2fs -l "$MD" | grep -iE 'Mount count|Filesystem state'
echo "=== re-affirm RAID preferred-minor STILL 1 after fs writes (MUST read 1) ==="
sudo mdadm --examine "${DEV}1" | grep -i 'Preferred Minor'
sudo mdadm --stop "$MD" 2>/dev/null || true
sync
echo "=== FLASH COMPLETE ==="
echo "Next: (PowerShell admin)  wsl --unmount <\\.\PHYSICALDRIVEn>"
echo "Put the drive back, power on, wait ~2 min, then: ping 192.168.0.16 && ssh alpha@192.168.0.16"
echo "No serial console is used anywhere in this project (see docs/05-flying-blind.md)."
echo "If it's unreachable: pull the drive again and read the breadcrumb ladder —"
echo "  mount-count -> /INIT-RAN.txt -> .canary/boot-canary.txt -> first-boot-diag/latest.txt"
echo "  (procedure + verdict logic in docs/05-flying-blind.md)."
