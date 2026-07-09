#!/bin/bash
# Safety-net backup of the WD MyCloud drive BEFORE flashing Devuan.
# Run on the WSL2 host AFTER: (PowerShell, admin)  wsl --mount <\\.\PHYSICALDRIVEn> --bare
# Usage:  sudo bash 01-backup-drive.sh /dev/sdX
# Backs up: partition table, kernel parts (5,6), config parts (7,8), one rootfs mirror (1).
# Does NOT touch the 2.7TB data partition (4).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="${1:?usage: 01-backup-drive.sh /dev/sdX  (the whole disk, e.g. /dev/sdd)}"
OUT="${OUT:-$REPO/backups/backup-$(date +%Y%m%d)}"
mkdir -p "$OUT"

echo "=== sanity check on $DEV ==="
lsblk -o NAME,SIZE,TYPE,MODEL "$DEV"
SIZE=$(blockdev --getsize64 "$DEV")
echo "size: $SIZE bytes (~$((SIZE/1000/1000/1000)) GB)"
# WD30EFRX is ~3.0 TB. Refuse if it looks like the wrong disk (<2.5TB or >3.5TB).
if [ "$SIZE" -lt 2500000000000 ] || [ "$SIZE" -gt 3500000000000 ]; then
  echo "!!! $DEV is not ~3TB — WRONG DISK? Aborting."; exit 1
fi
read -rp "Confirm this is the WD MyCloud drive and back it up? [type YES] " ok
[ "$ok" = "YES" ] || { echo "aborted"; exit 1; }

echo "=== partition table ==="
sudo sfdisk -d "$DEV" | tee "$OUT/partition-table.sfdisk"
sudo sgdisk --backup="$OUT/gpt-backup.bin" "$DEV" 2>/dev/null || true
sudo dd if="$DEV" of="$OUT/first-34-sectors.bin" bs=512 count=34 2>/dev/null

echo "=== imaging small partitions (kernel 5,6 / config 7,8) and rootfs mirror (1) ==="
for p in 5 6 7 8 1; do
  src="${DEV}${p}"
  [ -b "$src" ] || { echo "  $src missing, skip"; continue; }
  echo "  dd $src -> p${p}.img"
  sudo dd if="$src" of="$OUT/p${p}.img" bs=4M conv=noerror,sync status=progress
done

echo "=== checksums ==="
( cd "$OUT" && md5sum p*.img > checksums.md5 && cat checksums.md5 )
echo "=== BACKUP COMPLETE -> $OUT ==="
ls -la "$OUT"
