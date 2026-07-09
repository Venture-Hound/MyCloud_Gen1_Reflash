# 3 · Choosing an OS (or: newer is worse)

*(Status: outline — to be drafted.)*

Covers:

- First plan: Devuan Excalibur (Trixie-era, no systemd). Failed to boot
  — and the *reason* took weeks to surface because it failed identically
  to early Stretch (the real wall was udev, ch. 5).
- The 64 KB-page discovery: every ELF LOAD segment must align to
  `0x10000`, or the loader refuses it with
  **"ELF load command alignment not page-aligned"**.
- The alignment flip: Debian armhf's default link alignment went
  **64 KB (Stretch, 2017) → 4 KB (Trixie, 2025)**. On Trixie *most of
  userland* won't load on this kernel. **Stretch is the sweet spot
  precisely because it is old** — only the systemd/udev family is
  misaligned (plus three stragglers found later: libdaemon, libXau,
  libogg — see `lib-rebuilds/`).
- Honest unknowns: Buster/Bullseye untested — they might still be 64 KB.
- Stretch practicalities: archive.debian.org sources,
  `-o Acquire::Check-Valid-Until=false`, EOL implications.

Sources: `field-notes/FINDINGS.md` §3.5–3.6, §5;
`field-notes/HANDOVER-OS.md` (alignment sections).
