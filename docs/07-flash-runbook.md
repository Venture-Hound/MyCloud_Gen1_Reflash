# 7 · Flash runbook

*(Status: outline — to be drafted; genericize from the contemporaneous
RUNBOOK.md, which was written for one specific PC.)*

Covers:

- Attaching the drive to WSL2: elevated PowerShell `wsl --mount
  \\.\PHYSICALDRIVEn --bare`; device node **drifts** between attaches —
  always re-detect (`lsblk -dno NAME,SIZE,MODEL`).
- **Back up first** (`flash/01-backup-drive.sh`): partition table,
  kernel/config partitions, stock rootfs image. Restore-to-stock is a
  single `dd` to md1.
- Flashing (`flash/02-flash-rootfs.sh`): assemble md1
  `--update=super-minor`, `mkfs.ext3`, extract the tarball, verify the
  markers landed, `tune2fs -C 0` (mount-count baseline for the
  breadcrumb ladder), re-check `Preferred Minor : 1`, stop the array,
  **never rw-mount afterwards**.
- First boot: static IP, ~2 minutes, `ping` then ssh; if unreachable →
  pull the drive and read the ladder (ch. 5).
- Router hygiene: DHCP-reserve the static address.
- Post-success checklist: change default credentials, verify chrony
  (the RTC drifts to 2012 without NTP), keep it LAN-only.

Sources: `field-notes/RUNBOOK.md`, `flash/`,
`field-notes/HANDOFF-mid-debug.md` §11.
