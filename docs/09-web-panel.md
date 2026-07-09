# 9 · The web admin panel

*(Status: outline — to be drafted. Act V opener; synopsis in route map.)*

Covers:

- The survey: Webmin (heavy), OMV/Cockpit (systemd), SWAT (dead),
  Python panels (RAM) → **bespoke tiny**: lighttpd (3.3 MB RSS) + bash
  CGIs, no framework, no database.
- **The security model** — the part worth copying:
  - the web user can sudo exactly **one** executable
    (`nas-panel/panel-op`), which re-validates every argument against
    strict patterns regardless of what the CGIs send;
  - every smb.conf change is **testparm-gated** — a bad edit never
    reaches the running Samba;
  - protected user/share lists block foot-guns from the UI;
  - HTTP digest auth (no cleartext password on the LAN wire), one
    credential, deliberately no roles for a family box.
- Feature tour: dashboard (services, disk, RAM, SMART always visible),
  users (add with optional blank password, admin grant/revoke via a
  real unix group in `valid users`), shares (typed templates:
  family/private/guest + access column), USB mount/eject, DLNA toggle,
  poweroff/reboot.
- Lockout recovery: regenerate the htdigest over ssh — one line
  (documented so the reader isn't afraid of their own auth).
- Deploying: `nas-panel/deploy.sh`; lighttpd needs an explicit
  `[::]:80` socket (v6-first clients otherwise get connection refused).

Sources: `nas-panel/` (the code is the doc);
`field-notes/WORKLOG-SMB.md` (2026-07-05 21:10 onward).
