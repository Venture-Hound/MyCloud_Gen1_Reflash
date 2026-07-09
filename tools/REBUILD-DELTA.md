# REBUILD-DELTA — what's baked in vs. what you still do by hand

Earlier drafts of this project flashed a minimal image and then hand-applied
a long list of fixes over SSH (machine-id, wsdd2, the smbadmins group,
device nodes...). That list has since been **folded into `build/`** — see
`docs/04-building-the-rootfs.md` and `docs/08-samba-and-discovery.md` — so
a fresh `build → flash` now produces a box with all of that already in
place. What's left below is genuinely box-specific: things that need a
running, reachable NAS, or a choice only you can make (your family's
usernames, whether you want DLNA).

## Now baked into `build/` (nothing to do)

| What | Where it's baked |
|---|---|
| No-op udev stub, static `/dev` nodes, devtmpfs sysinit, libsystemd stub, the load-bearing `eth0` config (fw-helper, PFE params, `arp_notify`) | `build-stretch-stage2.sh`, consuming `rootfs-overlay/` |
| `/etc/machine-id` (wsdd2 dies silently without it) | `build-stretch-stage2.sh` step 11 |
| Samba base config, `smbadmins` group, `samba-vfs-modules` (recycle bin support), wsdd2 built from vendored source + init script | `build-stretch-stage3.sh` |
| avahi never installed (it can't run — `libdaemon.so.0` ships 32K-aligned; see `lib-rebuilds/README.md` if you ever want it) | `build-stretch-stage3.sh` (simply not installed) |

## Still done after flashing, on the running box

| # | What | How |
|---|---|---|
| 1 | Your family's users + shares | Edit the `FAMILY` list in `tools/make-shares.sh`, then run it as root over ssh. Shares are created with recycle bin + `@smbadmins` from the start. |
| 2 | Admin web panel | `nas-panel/deploy.sh` (edit `NASHOST` if not `clio.local`; prompts for the box's sudo password, nothing is stored). Set a real panel password in `nas-panel/remote-install.sh` (`PANELPASS`) before deploying, or regenerate it after — see `docs/09-web-panel.md`. |
| 3 | `[usb]` share | `nas-panel/setup-usb-dlna-recycle.sh` |
| 4 | *(optional)* DLNA | Same script, plus the two lib rebuilds it warns about — `lib-rebuilds/README.md` (libogg, libXau; both ship 32K-aligned on Stretch and won't load until rebuilt). Off by default; toggled from the panel once minidlna is installed. |
| 5 | Change every placeholder credential | `CHANGE_ME_root_password` / `CHANGE_ME_alpha_password` (build stage2/3), `CHANGE_ME_temp_password` (make-shares.sh), `CHANGE_ME_panel_password` (nas-panel/remote-install.sh) — grep the repo for `CHANGE_ME_` before you flash, or change them right after first boot. |

## Upgrading an already-flashed older box

If you're bringing an existing box (built before this fold-back) up to the
current design rather than reflashing from scratch, `nas-panel/
setup-admin-group.sh` is kept as the historical migration script — it
retrofits the `smbadmins` group and `null passwords = yes` onto an
already-configured `smb.conf`. A fresh build from `build/` doesn't need it;
stage3 creates the group and the share templates correctly from the start.

## Also part of current state (config, no script)

- Windows-side hosts-file / Credential Manager fixes are client-machine
  specific — see `docs/08-samba-and-discovery.md` for the failure mode and
  fix, nothing to script here.
- `smb.conf` live backups: the panel's `panel-op` and `make-shares.sh` both
  copy the config before editing it (`smb.conf.bak-YYYY-MM-DD`).
