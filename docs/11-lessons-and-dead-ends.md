# 11 · Lessons and dead-ends, ranked

*(Status: outline — to be drafted. Coda; synopsis in route map.)*

Covers:

- **Dead-ends ranked by what they cost** (adapted from FINDINGS §5 and
  HANDOVER-OS): modern-udev-just-needs-a-tweak (days); newer-distro-
  will-be-better (the alignment flip makes it worse); the mke2fs and
  userland-age theories (disproven offline — the cheap way); dropbear-
  dodges-libsystemd (Samba pulls it anyway); promiscuous-mode-fixes-RX
  (the PFE ignores interface flags); cross-compiling from a modern
  toolchain (header rot).
- **The iron rules** for anyone touching such a box: don't touch
  kernel/PFE/eth0; readelf-check everything (`tools/alignment-scan.sh`);
  `dpkg -l` before trusting an install; chroot-native builds; prefer
  read-only diagnostics; back up before editing.
- **Method lessons** that generalize: instrument, don't guess (the
  breadcrumb ladder); disprove theories offline before spending a
  hardware cycle; run the sanity test that localizes the fault (stock
  restore); when a daemon "logs nothing", check *the other* log
  (syslog vs daemon log); package metadata can lie about what's on
  disk.
- **Honest unknowns**: Buster/Bullseye alignment untested; arp_notify
  under link-flap not stress-tested; one unit, one disk model; behavior
  under RAM-pressure concurrency untested.
- Quirks that look like bugs and aren't: load average pinned at ~3 by a
  stuck kernel worker (cosmetic); the SO_REUSEPORT log line.

Sources: `field-notes/FINDINGS.md` §3, §5;
`field-notes/HANDOVER-OS.md` (ranked dead-ends, iron rules, unknowns).
