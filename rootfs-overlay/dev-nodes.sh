#!/bin/sh
# Bake static /dev nodes. This kernel has no CONFIG_DEVTMPFS (the
# devfs sysinit action's `mount -t devtmpfs` is a silent no-op) and udev
# is stubbed to no-op (see etc/init.d/udev) because modern udev hangs
# rcS on the vendor 3.2.26 kernel. Without udev or devtmpfs, nothing
# else will ever create these nodes — and without them nothing boots
# past a very early, very silent failure.
#
# Run against a target root, e.g.:
#   sudo TARGET=/path/to/rootfs sh dev-nodes.sh
# Idempotent — safe to re-run (skips nodes that already exist).
#
# List reproduced from the live, working system's /dev (2026-07-09):
# console/tty/ttyS0 (serial + console), null/zero/full/random/urandom
# (standard), md1 (root RAID), sda+sda1-8 (system disk, GPT), sdb+sdb1-8
# and sdc+sdc1-8 (USB-A port — two drive slots' worth of static nodes,
# since there's no hotplug to create them on demand; see
# docs/10-peripherals.md). /dev/pts and /dev/shm are NOT listed here —
# those come from the standard devpts mount and a base-files symlink,
# neither of which needs a custom fix.
set -e
TARGET="${TARGET:-.}"
D="$TARGET/dev"

# Backstop against the bind-mount trap: if $D is a mountpoint (e.g. the host's
# /dev bind-mounted over the target during a chroot build), every mknod below
# would succeed but land on the HOST, not in the rootfs — a silent failure
# that ships a near-empty /dev. Refuse loudly instead. Create the nodes BEFORE
# bind-mounting /dev (see build-stretch-stage2.sh step [1b]).
if mountpoint -q "$D" 2>/dev/null; then
    echo "dev-nodes: ERROR: $D is a mountpoint; nodes would hit the host, not the rootfs" >&2
    exit 1
fi

mkdir -p "$D"

mk() { # type major minor mode name
    t=$1 maj=$2 min=$3 mode=$4 name=$5
    [ -e "$D/$name" ] && return 0
    mknod -m "$mode" "$D/$name" "$t" "$maj" "$min"
}

mk c 5 1 666 console
mk c 5 0 666 tty
mk c 4 64 660 ttyS0
mk c 1 3 666 null
mk c 1 5 666 zero
mk c 1 7 666 full
mk c 1 8 666 random
mk c 1 9 666 urandom
mk c 5 2 666 ptmx

mk b 9 1 660 md1

# Kernel SCSI-disk minor scheme reserves a fixed 16-minor block per
# disk letter (sda=0-15, sdb=16-31, sdc=32-47, ...) regardless of how
# many partition nodes actually exist — so bases below are 16*index,
# not sequentially packed.
disk_index=0
for disk in a b c; do
    base=$((disk_index * 16))
    mk b 8 "$base" 660 "sd${disk}"
    for p in 1 2 3 4 5 6 7 8; do
        mk b 8 "$((base + p))" 660 "sd${disk}${p}"
    done
    disk_index=$((disk_index + 1))
done
# sda is the system disk (always present); sdb/sdc are two USB-A drive
# slots' worth of static nodes — no hotplug, so these must pre-exist
# for any USB drive the panel might later mount.

echo "dev-nodes: $(find "$D" -maxdepth 1 \( -type c -o -type b \) | wc -l) device nodes present"
