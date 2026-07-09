> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# WORKLOG — SMB/WSDD fix on clio (contemporaneous)

Terse running log so any Claude Code instance can pick up mid-stream.
Read `Configuring_SAMBA_on_Clio.md` (mission), `HANDOVER-OS.md` (box
ground truth), `HANDOVER-SMB-WSDD.md` (SMB/WSDD state as of 2026-07-05)
FIRST. This file only logs what happened AFTER those.

Format: `date time — action — result/why`. Newest at bottom.

---

2026-07-05 ~19:00 — Session start (Fable). Verified ssh alpha@clio.local
+ sudo→root OK. Read all 3 handover docs. Plan confirmed with user:
(1) trace open_ep()/wsd_init() silent-fail in wsdd2 source,
(2) strace IP_ADD_MEMBERSHIP live, (3) patch/rebuild in chroot if
needed, (4) then Windows-side checks, (5) then users/shares buildout.

2026-07-05 19:10 — Found TWO wsdd2 instances running (5619 w/ `-d`,
5669 no args) — strays from earlier manual tests. Fetched missing
wsdd.h; stashed canonical source at ./wsdd2-src/ (handover TODO done).

2026-07-05 19:20 — Source read (wsdd2.c). Corrections to
HANDOVER-SMB-WSDD.md claims: (a) `-d` = "go daemon" (fork), NOT
"don't daemonize"; the stray 5619 was a `-d` test's forked child.
(b) SO_REUSEADDR IS set (wsdd2.c:373). (c) open_ep() errors go to
SYSLOG (/var/log/syslog, /var/log/user.log), NOT /var/log/wsdd2.log —
previous session grepped the wrong log. (d) There IS debug: -W
incremental; -w/-u/-4 isolate endpoints. (e) EADDRINUSE on bind =
silent skip by design (wsdd2.c:387).

2026-07-05 19:30 — ROOT CAUSE. Syslog showed on every start:
`error: wsdd-mcast-v4: wsd_init: uuid_endpoint`. wsd.c:95
uuid_endpoint() reads /etc/machine-id, requires exactly 32 lowercase
hex; missing file → empty uuid → wsd_init fails → open_ep tears down
BOTH mcast endpoints after the (successful!) bind+IGMP join. /etc/
machine-id is a systemd-ism — absent on this sysvinit box. dbus one
exists at /var/lib/dbus/machine-id (REDACTED-MACHINE-ID).
Also noted: /etc/services missing on box (harmless here — code falls
back to hardcoded port 3702; hygiene item).

2026-07-05 19:43 — FIX APPLIED + VERIFIED. `cp /var/lib/dbus/
machine-id /etc/machine-id; chmod 444`. Killed strays, single clean
`service wsdd2 start` (pid 6040). Result: UDP 3702 bound v4+v6;
/proc/net/igmp eth0 now has FAFFFFEF (239.255.255.250). tcpdump:
CLIO Hello → Windows box 192.168.0.2 Probe within 1 s → CLIO
ProbeMatch reply (v4 and v6). Full WSD handshake working. Remaining
syslog EADDRINUSE lines (wsdd-http-v6/llmnr-tcp-v6) are dual-stack
cosmetic — v4 sockets already cover those ports; no IPV6_V6ONLY in
source. Fix persists across reboots (plain file). TODO: fold
/etc/machine-id creation into build scripts/tarball for
reproducibility; correct HANDOVER-SMB-WSDD.md.

2026-07-05 19:50 — User report: CLIO appears in Explorer→Network (✓)
but click → long hang → cred prompt rejecting alpha/REDACTED. Yet
\\192.168.0.16 works fine (shares listed, browse/write OK — Windows
login mapped to guest via `map to guest = Bad User`). Diagnosed via
powershell.exe FROM WSL (key trick — this WSL sits on the affected
Windows PC, hostname WINPC, 192.168.0.2): `Resolve-DnsName clio` →
CNAME `dev.example.com192.168.0.16` → ::1 (!). WINDOWS HOSTS FILE
had two lines fused (missing newline — DDEV hosts-write collision):
`::1 dev.example.com192.168.0.16<TAB>clio<TAB>clio.local`. So \\CLIO
connected to ::1 = WINPC' own SMB server → its cred prompt rejected
Samba creds. Explains hang + rejection completely.

2026-07-05 20:04 — HOSTS FIX APPLIED. Backup at
./hosts.backup-2026-07-05. Split line 39 into `::1 dev.example.com`
+ `192.168.0.16\tclio\tclio.local` (CRLF preserved). Needed elevated
PowerShell via UAC (3 attempts: sed temp-file EPERM; then printf ate
backslashes writing the .ps1 — use Write tool not printf for Windows
paths!). ipconfig /flushdns. Verified: Resolve-DnsName clio → A
192.168.0.16; `net view \\CLIO` lists alpha+public (Error 5 GONE);
Test-NetConnection clio:445 True. Awaiting user Explorer retest.
Lesson recorded: powershell.exe from WSL = full Windows-side
diagnostics/fix capability (UAC via Start-Process -Verb RunAs).

2026-07-05 20:15 — USER CONFIRMS Explorer works: CLIO visible,
shares open, alpha share opened with stored creds (Credential
Manager has alpha entries for CLIO, clio.local AND 192.168.0.16 —
so the earlier "\\192.168.0.16 needed no creds" was stored creds,
not guest mapping). LLMNR-only resolve test confirms family PCs
need NO hosts entry — WSD+LLMNR+NetBIOS+mDNS all served by clio.
DISCOVERY PROBLEM CLOSED.

2026-07-05 21:10 — WEB ADMIN PANEL built + deployed ("bespoke tiny"
route chosen over Webmin; OMV/Cockpit rejected = systemd, SWAT dead,
Python panels = RAM). Stack: lighttpd 1.4.45 (stretch pkg, 3.3 MB RSS)
+ bash CGIs + single sudo-able root wrapper. All source staged in
./nas-panel/ (deploy.sh re-deploys everything). On clio:
  /usr/local/nas-panel/www/*.cgi + lib.sh   (UI: status/users/shares/
    smart/power; digest auth realm "CLIO NAS", user alpha pw REDACTED
    — /etc/lighttpd/nas-panel.htdigest)
  /usr/local/lib/nas-panel/panel-op         (ONLY thing www-data may
    sudo — /etc/sudoers.d/nas-panel; re-validates all input; testparm
    gates every smb.conf change; protected users+shares list)
  /usr/local/lib/nas-panel/led-status       (cron */5 + boot via
    /etc/init.d/nas-led: blue=good, yellow=svc down/fs>=90%, red
    blink=SMART FAILED or md degraded; smartctl -n standby never
    wakes disk)
Also installed: smartmontools 6.5 (SMART: PASSED on WD30EFRX),
smartd NOT enabled (user wants pull-not-push checks). LED driver
vocab verified: blue/yellow/red/green/white + blink attr all accepted
via /sys/class/leds/system_led. Gotchas hit: (1) lighttpd needed
explicit [::]:80 socket (WSL resolved clio.local to v6 first);
(2) WSL /etc/hosts had its OWN stale copy of the fused Windows hosts
line (WSL regenerates at boot — fixed in place); (3) one TRANSIENT
led-status segfault during install, not reproducible, cron self-heals
— watch it; (4) printf-with-backslashes lesson again.
E2E tested via HTTP POSTs: user add (immediately SMB-loginable) /
pass / del, share add family+private / del, confirm-gates, protected-
share refusal, testparm still clean, RAM 72 MB used / 143 avail.
UNTESTED: poweroff/reboot buttons (need user at the box to verify
halt behavior + replug); LED visual mapping needs user eyeball.

2026-07-05 21:30 — User confirmed: panel works, LED solid blue. NTP
question settled: chrony already synced to debian pool (4 sources,
sub-ms), Sky router answers no NTP (w32tm timeout), outbound-only =
not "exposure". No change.

2026-07-05 21:45 — AVAHI MYTH BUST: avahi-daemon does NOT run and
never has on this box — /usr/lib/arm-linux-gnueabihf/libdaemon.so.0
is 32K-aligned (0x8000, readelf'd a pulled copy) → "ELF load command
alignment not page-aligned". All prior "clio.local resolves"
observations were hosts-file/ssh-config illusions. HANDOVER-OS.md
"avahi running" claim is WRONG — correct when folding docs. Options:
rebuild libdaemon 64K in chroot (restores mDNS), or drop avahi and
rely on WSD+LLMNR+NetBIOS (flat names work fine from Windows).

2026-07-05 21:50 — USB-A port assessed: usb-storage + sd are BUILT-IN
to vendor kernel (/sys/bus/usb/drivers), /dev/sdb+sdb1 statically
baked (only 1 partition node — bake more if needed), vendor-harvested
fat/vfat/msdos/fuse/xfs .ko all present; modprobe vfat + fuse tested
OK, registered in /proc/filesystems. So: FAT32 mountable now, NTFS
needs ntfs-3g pkg (alignment-check on install), exFAT needs
exfat-fuse pkg. NO automount (no udev) — manual mount or wire a
panel Mount/Eject button + [usb] share. NLS codepage support for
vfat untested until a real stick is plugged.

2026-07-06 00:10 — USB LIVE TEST with user's stick: 15GB FAT32
detected sdb/sdb1, vfat mount + long filenames + umount all clean.
SAME dmesg revealed KERNEL OOPS in vendor LED driver
(led_brightness_store, "bad PC value") — this was the real cause of
the earlier led-status "segfault", and repeats occasionally under
the 5-min cron. Kernel survives, writing process dies. MITIGATION
(in led-status + panel-op led_set): write only on state change
(cache /var/run/nas-led.state), blink off first / blink on last,
never brightness while blinking. LED write rate now ~0/hr.

2026-07-06 00:30 — Feature round per user: (a) avahi disabled
(update-rc.d; it never ran anyway — libdaemon 32K). (b) Baked static
nodes sdb2-8, sdc, sdc1-8. (c) vfs_recycle added to all 7 shares +
new-share templates; purge cron 04:30 (>30 days,
/usr/local/lib/nas-panel/recycle-purge). (d) [usb] share (@users) +
panel Mount/Eject (largest mountable partition heuristic, vfat/ext).
(e) SMART long test monthly-if-due via daily 04:10 check
(smart-monthly + stamp file). (f) minidlna installed + configured
(media_dir=/srv/nas/music, friendly_name="CLIO Music"), boot-disabled,
panel Start/Stop toggle. All in nas-panel/ + setup-usb-dlna-recycle.sh.

2026-07-06 00:40 — minidlnad BLOCKED: stretch's libogg.so.0 is
32K-aligned! Rebuilt libogg 1.3.2 in qemu chroot with
-Wl,-z,max-page-size=0x10000 → installed on clio (orig at
/root/libogg.so.0.8.2.orig-32k), apt-mark hold libogg0. Then
libXau.so.6 hit the same wall. FULL-BOX .so SCAN (all libs tar'd to
WSL, readelf'd): exactly 3 misaligned on entire box — libudev (4K,
unused by design), libdaemon (32K, avahi - moot), libXau (32K).
libXau 1.0.8 rebuild running in chroot. Lesson for docs: alignment
exceptions are NOT limited to systemd family; readelf-check every
new package's libs.

2026-07-06 00:50 — Docs folded: HANDOVER-SMB-WSDD.md got RESOLVED
banner + corrections; HANDOVER-OS.md updated (avahi truth, alignment
rule, machine-id, USB, LED driver bug, running daemons, tools);
REBUILD-DELTA.md created (ordered delta from flashed image to
current state). User deferred credential hardening (task #11) —
may make more changes first.

2026-07-06 01:00 — RECYCLE FIX: tree connect BAD_NETWORK_NAME after
adding vfs recycle = recycle.so missing → apt install
samba-vfs-modules (add to any rebuild!). E2E pass: SMB delete lands
in .recycle/<user>/ with tree preserved.

2026-07-06 01:10 — LED ENDGAME. Deploy-time vocab test removed (was
re-poking the bug each deploy). Probed blink attr: WRITE-DEAD (reads
"on" for off/0/none). Reproduced oops on demand: brightness write
with blink engaged. dmesg census: 51 oopses since boot, 100% of
traces in led_brightness_store — zero in color/blink stores (old
cron wrote all three every 5 min overnight). FINAL POLICY: COLOR-ONLY
(color on change via /var/run/nas-led.state cache; brightness only
if !=255, i.e. once per boot; blink never). red = solid now.
led-status runs exit-0 repeatably. Kernel survived all 51 oopses —
cosmetic-ish but stop provoking it.

2026-07-06 05:30 — libXau 1.0.8 rebuilt 64K in chroot, installed
(orig at /root/libXau.so.6.0.0.orig-32k), apt-mark hold libxau6.
minidlnad loads clean. DLNA E2E via panel verbs: start OK (13 MB
RSS, port 8200), status, stop OK, boot-enable/disable follows
toggle. USB E2E via panel verbs: status/mount(vfat,15G)/browse/
eject all OK. Dashboard renders USB + DLNA blocks. RAM: 77 MB used
/ 138 avail. Docs updated: HANDOVER-OS (LED color-only section,
alignment inventory, USB, avahi), HANDOVER-SMB-WSDD (RESOLVED
banner), REBUILD-DELTA.md, memory. REMAINING with user: LED visual
check (solid vs blinking after driver crashes), poweroff/reboot
button test at the box, then deferred credential hardening (#11).

2026-07-06 13:30 — UI TWEAKS round (user request): (1) blank-password
users — `null passwords = yes` in [global] (deprecated-warning is
harmless), panel add/set-password accept empty → smbpasswd -n.
(2) Admin concept = unix group `smbadmins` (gid 1003); all private
shares + [admin] migrated to `valid users = <owner> @smbadmins`;
panel Users page has Make admin/Revoke; alpha always admin; new-share
template uses @smbadmins. (3) Shares table now has "Who has access"
column (parsed from smb.conf by panel-op share-list, TSV). E2E
verified incl. grant→open others' share→revoke→denied cycle
(setup-admin-group.sh + deploy). NOTE: user made panel changes
independently — the third account was recreated under a corrected
spelling (uid 1004; the empty orphan dir from the old spelling
removed), music share recreated as guest type, alice's SMB password
is no longer REDACTED. Docs referring to the earlier spelling are
historical.

2026-07-06 13:45 — DRAG-AND-DROP mystery solved: samba logs showed
tree-connect lookups for share names like "untitled-2.txt" = user
dropping files onto \\CLIO ROOT (share list, not a folder) —
Explorer can never accept that; must drop INSIDE a share. Real bugs
found+fixed while looking: [alpha] share had build-era masks
(0644/0755, no force group, dir alpha:alpha) → any OTHER admin
writing into it would be fs-denied; now 0664/2775 + force group
users + dir 2770 alpha:users (recursive g+rwX applied). /srv/nas/usb
root:755 while unmounted is DELIBERATE (blocks accidental writes to
the hidden mountpoint dir).

2026-07-05 20:25 — Users+shares buildout (make-shares.sh, idempotent,
also at /tmp/make-shares.sh on clio). Created system+SMB users
alice(1001) bob(1002) carol(1003), initial SMB pw `REDACTED`
(CHANGE LATER, like alpha/root). Dirs /srv/nas/{alice,bob,carol}
owner:users 2770; admin (alpha only) 2770; music 2775. smb.conf:
appended [alice][bob][carol] (valid users = owner+alpha, force
group users), [admin] (alpha only), [music] (read only + write list
= @users + guest ok = yes for player devices). Backup at
/etc/samba/smb.conf.bak-2026-07-05. testparm OK, smbd reloaded,
smbclient + Windows net view show all 7 disk shares. NOTE: new
users' Windows boxes just need \\CLIO + their creds on first open.
