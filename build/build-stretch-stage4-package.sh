#!/bin/bash
# Stage 4: package the finished rootfs into a flashable tarball + manifest.
# Run from the repo root: bash build/build-stretch-stage4-package.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-$REPO/rootfs-stretch}"
OUT="${OUT:-$REPO/rootfs-stretch.tar.gz}"

# make sure nothing is still bind-mounted inside the target
for m in dev/pts dev sys proc; do mountpoint -q "$TARGET/$m" && sudo umount -l "$TARGET/$m" || true; done

echo ">>> packaging $TARGET -> $OUT"
sudo tar --numeric-owner --xattrs -czf "$OUT" -C "$TARGET" .
echo ">>> done"
ls -la "$OUT"
echo -n "md5: "; md5sum "$OUT"
echo ">>> uncompressed size (what must fit on md1, ~1.9GB partition):"
sudo du -sh "$TARGET"
