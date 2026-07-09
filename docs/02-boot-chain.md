# 2 · The boot chain, and its footguns

*(Status: outline — to be drafted.)*

Covers:

- U-Boot bootargs: `root=/dev/md1 raid=autodetect rootfstype=ext3
  noinitrd panic=3` — **no initramfs**; the kernel assembles the root
  array itself and names it purely from the RAID 0.90 superblock's
  **preferred-minor** field.
- `panic=3` = every early failure is a silent reboot loop.
- **The preferred-minor footgun**: any rw touch of the array while
  assembled under another number (WSL auto-assembles as md127) re-stamps
  the minor; `root=/dev/md1` then doesn't exist. Rule: re-stamp with
  `--update=super-minor` as the LAST array operation, never rw-mount
  after, verify with `mdadm --examine`.
- `debugfs` reads files off a RAID member with no assembly and no
  writes — the backbone of all post-mortem forensics.
- The mke2fs-1.47 scare and how a `dumpe2fs` superblock diff against
  stock disproved it without burning a drive cycle.

Sources: `field-notes/FINDINGS.md` §1, §3.7, §3.8;
`field-notes/HANDOFF-mid-debug.md` §2–3, §13.
