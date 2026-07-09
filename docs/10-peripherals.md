# 10 · Peripherals: LED, USB, recycle bin, DLNA, SMART

*(Status: outline — to be drafted.)*

Covers:

- **The LED that crashes the kernel.** The vendor driver's
  `led_brightness_store` oopses intermittently ("bad PC value"; the
  writing process dies, the kernel survives). A dmesg census after a
  night of 5-minute cron writes: 51 oopses, **100% in brightness
  writes, zero in color writes**; the `blink` attribute is write-dead.
  The negotiated peace, baked into `nas-panel/led-status`: **COLOR-ONLY**
  — write `color` only on state change, `brightness` once per boot,
  `blink` never. Meaning: blue = good, yellow = service down / fs ≥ 90%,
  red = SMART failure or degraded RAID (solid — blink isn't usable).
- **USB without udev**: usb-storage + sd are built into the vendor
  kernel, but no hotplug node creation — static `/dev/sdb*`/`sdc*`
  nodes are baked; the panel mounts the largest mountable partition and
  exposes it as one share. FAT32 via vendor-harvested modules; NTFS and
  exFAT would need packages (alignment-check them first). The share's
  mountpoint stays root-owned while unmounted **on purpose** (blocks
  writes into the hidden directory).
- **Recycle bin**: `vfs_recycle` per share, per-user tree
  (`.recycle/%U`, keeptree), 30-day purge cron. Gotcha: the module
  lives in **samba-vfs-modules** — without that package every
  recycle-enabled share fails tree connect with
  `NT_STATUS_BAD_NETWORK_NAME`.
- **DLNA**: minidlna, panel-toggled (off by default, ~13 MB RSS when
  on). Blocked twice by 32 K-aligned libs (libogg, then libXau) → the
  full-box alignment scan and rebuilds (`lib-rebuilds/README.md`).
- **SMART**: smartctl only (no smartd — pull, not push); dashboard
  shows health on every visit using `-n standby` so the check never
  wakes the disk; monthly long self-test via a
  run-if-due-at-4am-or-next-boot stamp scheme (`nas-panel/smart-monthly`).
- Deliberate non-feature: **no disk spindown** (a NAS drive parked and
  woken all day wears faster than one that spins).

Sources: `field-notes/HANDOVER-OS.md` (LED / USB sections),
`field-notes/WORKLOG-SMB.md` (2026-07-06 entries), `nas-panel/`,
`lib-rebuilds/README.md`.
