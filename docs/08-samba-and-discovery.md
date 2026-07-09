# 8 · Samba, wsdd2, and the discovery saga

*(Status: outline — to be drafted. Act IV; synopsis in route map.)*

Covers:

- smb.conf choices for a 256 MB box (`deadtime`, SMB2 minimum, `map to
  guest = Bad User`) — see `rootfs-overlay/etc/samba/smb.conf.template`.
- Harmless-but-alarming log line: `SO_REUSEPORT ... Protocol not
  available` (3.2 kernel; Samba falls back cleanly).
- **Why WSD**: Win10 1709+ Explorer discovery needs a WS-Discovery
  responder; NetBIOS alone won't put the box in Network view. Stretch
  packages no wsdd. Choice matrix: christgau/wsdd (Python — blows the
  RAM budget) vs the NETGEAR-lineage C daemon → vendored
  `wsdd2/` (GPL-3.0, see PROVENANCE).
- **Cross-compiling fails, chroot-native works**: modern host
  toolchains leak `GLIBC_2.34+` symbol versions and time64 types that
  Stretch's glibc 2.24 lacks; build inside the armhf chroot instead.
- Init-script gotcha: `Required-Start: samba` fails insserv
  (**"Service samba has to be enabled to start service wsdd2"**) —
  Stretch splits smbd/nmbd; name both.
- **Root cause #1 (server)**: wsdd2 binds, joins the multicast group,
  then silently tears both WSD endpoints down. The error —
  `error: wsdd-mcast-v4: wsd_init: uuid_endpoint` — goes to **syslog**,
  not the daemon's own log. Cause: `/etc/machine-id` (a systemd-ism)
  doesn't exist on a sysvinit box; the fix is one `cp` from
  `/var/lib/dbus/machine-id`. Discovery dies for want of sixteen bytes
  of identity.
- **Root cause #2 (client)**: the Windows *hosts file* had two lines
  fused by a lost newline, aliasing the NAS name to `::1` — Explorer
  was connecting to the PC's own SMB server and rejecting perfectly
  good credentials. WSL inherits the same fused line into its
  auto-generated `/etc/hosts`. Diagnosis path: `Resolve-DnsName`,
  `net view`, Credential Manager.
- Windows-side background: guest-auth blocking since 1709, LLMNR /
  NetBIOS / WSD resolution layering, why family PCs need no hosts
  entries at all once WSD works.

Sources: `field-notes/HANDOVER-SMB-WSDD.md` (read the RESOLVED banner
first — the body below it preserves the investigation, including the
wrong turns); `field-notes/WORKLOG-SMB.md` (2026-07-05 entries);
`wsdd2/PROVENANCE.md`.

## Build-run verification (2026-07-09)

The Samba + wsdd2 path in `build/build-stretch-stage3.sh` was executed
end-to-end for the first time as part of the folded build and verified
structurally (no hardware flash — the box is in production, so verification is
`dpkg`/`readelf`/live-diff rather than a reflash). All of it held:

- **machine-id is baked, not post-flash.** Stage 2 step [11] generates it
  (`head -c16 /dev/urandom | od …`, no dbus dependency) as 32 lowercase hex, so
  wsdd2's `uuid_endpoint()` no longer dies silently for want of an identity.
- **smbadmins exists from the start** (stage 3), and the generated `smb.conf`
  grants `valid users = <owner> @smbadmins` on private shares — byte-for-byte
  the pattern live clio runs.
- **wsdd2 links 64K-aligned.** `-Wl,-z,max-page-size=0x10000` reaches the linker
  via make's implicit rule (confirmed in the build log; `readelf` shows LOAD
  `0x10000`); it installs to `/usr/local/sbin/wsdd2` and registers at
  `rc2.d/S03wsdd2` with `Required-Start: smbd nmbd`.
- **recycle works.** `samba-vfs-modules` installs a loadable `recycle.so`
  (`0x10000`), so `vfs objects = recycle` in the share templates is real, not a
  tree-connect failure.
- **avahi is confirmed absent** (never installed) — its `libdaemon.so.0` ships
  32K-aligned and couldn't load here anyway; WSD + LLMNR + NetBIOS cover Windows
  discovery without it.

Full run capture: [`reference-build.log`](reference-build.log).
