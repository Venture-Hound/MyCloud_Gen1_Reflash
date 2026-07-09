#!/bin/bash
# alignment-scan.sh — find shared objects whose LOAD segments are not
# 64K-aligned (those will not load on a 64 KB-page kernel).
#
# What actually breaks on this kernel: shared objects (.so) that get linked
# or dlopen'd. ld.so mmaps their LOAD segments and is strict about page
# alignment, so a 4K- or 32K-aligned library dies at load time with
#   "ELF load command alignment not page-aligned"
# and everything using it fails — silently, at runtime, with no apt warning.
#
# Main executables are a different story: this kernel's own ELF loader runs
# 4K-aligned armhf binaries fine (verified on the live box — stock
# mawk/less/touch ship 4K-aligned and execute normally). The Comcerto PFE
# firmware *.elf blobs aren't Linux binaries at all (they run on the packet
# engine). So this scanner only *fails* on misaligned shared objects;
# misaligned executables / other ELF are printed as "note" for information.
#
# Usage:
#   alignment-scan.sh <dir-or-file>...
#
# The target box likely has no binutils; pull its libs to the build host first:
#   ssh user@nas 'tar czf - /lib /usr/lib /usr/local 2>/dev/null' | \
#       tar xzf - -C /tmp/naslibs && alignment-scan.sh /tmp/naslibs
#
# Fatal offenders seen on Debian Stretch armhf, and the fix for each:
#   libsystemd.so.0 (4K) — sshd/smbd/dbus link it; replace with the 64K no-op
#                          stub (../libsystemd-stub/). apt still believes the
#                          real 4K package is installed ("apt says fine,
#                          readelf disagrees"), so it's held with apt-mark.
#   libdaemon.so.0  (32K) — silently kills avahi (not shipped here).
#   libXau.so.6     (32K) — kills minidlna  (optional DLNA path).
#   libogg.so.0     (32K) — kills minidlna  (optional DLNA path).
# Rebuild recipe for the optional-path libs: see ../lib-rebuilds/README.md.
#
# Two 4K shared objects are EXPECTED and harmless on a good build, so they are
# allow-listed below (reported "ok-known", not a failure):
#   libudev.so.1[.x.y]   — pulled in as a base dependency; nothing loads it.
#   libsystemd.so.0.17.0 — the real lib, orphaned when the stub replaced the
#                          libsystemd.so.0 symlink; unreferenced (the SONAME
#                          libsystemd.so.0 now resolves to the stub).
set -u

# basenames allowed to be misaligned (known-harmless — see note above)
allow='libudev.so.1 libudev.so.1.6.5 libsystemd.so.0.17.0'

is_so()   { case "$1" in *.so|*.so.*) return 0;; *) return 1;; esac; }
allowed() { b=$(basename "$1"); for a in $allow; do [ "$b" = "$a" ] && return 0; done; return 1; }

bad=0 checked=0 notes=0 known=0
for root in "$@"; do
    while IFS= read -r -d '' f; do
        [ "$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
        checked=$((checked + 1))
        for a in $(readelf -lW "$f" 2>/dev/null | awk '$1 == "LOAD" { print $NF }'); do
            [ $((a)) -lt $((0x10000)) ] || continue
            if ! is_so "$f"; then
                printf 'note       %-8s %s (executable/firmware — loads fine on this kernel)\n' "$a" "$f"
                notes=$((notes + 1))
            elif allowed "$f"; then
                printf 'ok-known   %-8s %s (expected, harmless)\n' "$a" "$f"
                known=$((known + 1))
            else
                printf 'MISALIGNED %-8s %s\n' "$a" "$f"
                bad=$((bad + 1))
            fi
            break
        done
    done < <(find "$root" \( -type f -o -type l \) \( -name '*.so*' -o -perm -111 \) -print0 2>/dev/null)
done
echo "checked=$checked misaligned_libs=$bad (known-harmless=$known, exec/other notes=$notes)"
[ "$bad" -eq 0 ]
