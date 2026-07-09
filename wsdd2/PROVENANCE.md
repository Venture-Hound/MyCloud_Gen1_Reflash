# Provenance — vendored wsdd2 source

- **Upstream:** https://github.com/kochinc/wsdd2 — a fork of NETGEAR's
  `wsdd2` (the WS-Discovery + LLMNR daemon from ReadyNAS firmware).
  NETGEAR's original repository has since disappeared from GitHub, which
  is exactly why a copy is vendored here.
- **Commit:** `9b1911358e1929632b15e4fe8527fddc42dc139d` (2018-09-12,
  upstream master head at time of vendoring).
- **Fetched:** 2026-07-05; every file re-verified byte-identical to the
  upstream commit on 2026-07-09.
- **Modifications: none.** The daemon needed no source changes on our
  target — the discovery failure was environmental (`/etc/machine-id`
  missing on a sysvinit box; see `docs/08-samba-and-discovery.md`).
- **License:** GPL-3.0-or-later (copyright 2016 NETGEAR, 2016 Hiro
  Sugawara — see file headers and `LICENSE`, copied verbatim from
  upstream). This directory is the only non-MIT part of this repository.

## The binary we run

Built chroot-native inside a Debian Stretch armhf chroot (qemu-user
binfmt) with `LDFLAGS='-Wl,-z,max-page-size=0x10000'` — cross-compiling
from a modern host toolchain fails against Stretch's glibc 2.24 (symbol
version and time64 header leaks). Result:

- 31,192 bytes stripped, `NEEDED` = libc.so.6 only, all symbols ≤ GLIBC_2.4
- ELF `LOAD` alignment 0x10000 (required by the 64 KB-page vendor kernel)
- sha256 `8efa9ea4ea8f9f135ad12ebf00ed1d5f31e8ad29525c0336c3f55a406acc2942`

Deployed to `/usr/local/sbin/wsdd2`; SysV init script at
`rootfs-overlay/etc/init.d/wsdd2` (note its `Required-Start:` uses
`smbd nmbd`, not `samba` — Stretch's split Samba init scripts provide no
combined `samba` facility and `insserv` refuses it).
