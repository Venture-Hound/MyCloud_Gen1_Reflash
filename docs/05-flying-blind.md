# 5 · Flying blind — debugging without a serial console ★

*(Status: outline — to be drafted. The reusable jewel of the repo;
worth the most drafting care.)*

Covers:

- The handicap: UART is a 1.27 mm board-edge pad we never connected;
  `panic=3` makes every early failure a **silent reboot loop**.
- The anti-method that wasted attempts 1–5: swap a suspect, flash, watch
  nothing happen, invent a new theory. Two plausible theories ("mke2fs
  too new", "userland too new for a 3.2 kernel") both **disproven
  offline** — dumpe2fs superblock diff vs stock; ELF ABI-tag check —
  without burning a drive cycle.
- The stock-restore sanity test: proves disk + kernel + boot chain +
  RAID handling are fine, so **the fault is exclusively our rootfs**.
- **The breadcrumb ladder** (attempt 6). Each rung writes to a place
  that needs progressively more of the system to be alive:
  1. root-superblock **mount count** (`tune2fs -C 0` at flash time) —
     did the kernel mount root?
  2. `/INIT-RAN.txt` from the **first inittab sysinit action** — did
     `/sbin/init` exec and parse inittab?
  3. early-rcS **canary** on the data partition — did rcS start?
  4. **first-boot-diag** at end of multiuser — what's the
     network/module/service state?
  5. **net-diag**, `setsid`-detached (backgrounded children of init
     scripts get killed on script exit) — is the box even receiving
     inbound frames?
- Verdict logic: highest rung present = where boot died. One flash
  cycle located the wall (udev) that five guessing cycles had missed.
- Reading it all back: `wsl --mount --bare`, `debugfs` against a raw
  RAID member, ro-mount of the data partition.

Sources: `field-notes/FINDINGS.md` §4, §6;
`field-notes/HANDOFF-mid-debug.md` §13 (the ladder, as designed);
`rootfs-overlay/etc/init.d/{initmarker,canary,firstboot-diag}`.
