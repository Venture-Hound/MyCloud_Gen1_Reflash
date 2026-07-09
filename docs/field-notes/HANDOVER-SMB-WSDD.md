> **Contemporaneous working document, published as written** (credentials
> and personal names redacted). Claims below reflect what we believed at
> the time — some were later disproven; the RESOLVED banners and
> FINDINGS.md carry the corrections. Kept because watching the wrong
> theories die is half the value.

# CLIO — Samba + wsdd2 state (handover)

> ## ✅ RESOLVED 2026-07-05 — read this box first
>
> The discovery problem described below was **solved**. Two root causes:
>
> 1. **Server:** `wsd_init()` reads `/etc/machine-id` (via
>    `uuid_endpoint()`, wsd.c:95) and needs exactly 32 lowercase hex
>    chars. The file is a systemd-ism and didn't exist on this sysvinit
>    box → empty UUID → wsdd2 silently tore down both WSD multicast
>    endpoints *after* a successful bind+IGMP join. Fix:
>    `cp /var/lib/dbus/machine-id /etc/machine-id`. The error WAS
>    logged — `error: wsdd-mcast-v4: wsd_init: uuid_endpoint` — but to
>    SYSLOG (`/var/log/syslog`), not `/var/log/wsdd2.log` (stdout only).
> 2. **Client (WINPC):** the Windows hosts file had two lines fused by
>    a lost newline (`::1 dev.example.com192.168.0.16	clio	clio.local`)
>    making `clio`/`clio.local` aliases of `::1` — Explorer connected to
>    the PC's own SMB server. Fixed + `ipconfig /flushdns`. WSL's
>    auto-generated `/etc/hosts` had inherited the same fused line.
>
> **Corrections to claims below**, learned from source + live tests:
> - `-d` means "go daemon" (fork), NOT "don't daemonize". The stray
>   second wsdd2 instance came from a `-d` test.
> - `SO_REUSEADDR` IS set (wsdd2.c:373).
> - Real debug flags exist: `-W` (incremental), plus `-w/-u/-4`
>   selectors.
> - EADDRINUSE on bind = deliberate silent skip (wsdd2.c:387).
> - The remaining v6 EADDRINUSE log lines are dual-stack artifacts
>   (no IPV6_V6ONLY in source; v4 wildcard socket owns the port). Cosmetic.
>
> Full trail: `WORKLOG-SMB.md`. Canonical wsdd2 source: `./wsdd2-src/`.
> Everything below is kept as history of the investigation.

Companion to `HANDOVER-OS.md`. Focused on the SMB/discovery problem on
**clio** (`192.168.0.16` / `clio.local`).

Facts labelled `[FACT]` are verified via SSH on 2026-07-05. Hypotheses
are labelled and ranked.

## The problem statement

Windows can `ping clio.local` fine and `ssh alpha@clio.local` works,
but:
1. `CLIO` does not appear in Windows Explorer → Network.
2. `net view \\CLIO` returns Error 5 (Access Denied) — see §7.

## What's verified working — do not chase these

- **Samba is healthy.** `smbd` (pid 1551, RSS 24 MB), `nmbd` (RSS 11 MB),
  `smbd-notifyd` (RSS 14 MB). All listening: TCP 139, 445 (v4+v6);
  UDP 137, 138 (NetBIOS, v4).
- **SMB user `alpha` exists** — `pdbedit -L` returns `alpha:1000:`,
  password last set 2026-07-01, account flag `[U          ]` (enabled).
  Credential `REDACTED` works.
- **Loopback SMB works with SMB2/SMB3:**
  ```
  smbclient -L //localhost -U alpha%REDACTED -m SMB2   # ✓ lists shares
  smbclient -L //localhost -U alpha%REDACTED -m SMB3   # ✓ lists shares
  ```
  Without `-m SMB2`, `smbclient` defaults to SMB1 negotiation → server
  refuses (`min protocol = SMB2_10`) → `NT_STATUS_INVALID_NETWORK_RESPONSE`.
  **That error is a smbclient default quirk, not a bug.** Always pass
  `-m SMB2` for loopback tests.
- **`samba-common-bin` IS installed** (`2:4.5.16+dfsg-1+deb9u4`) —
  `smbpasswd`, `testparm`, `pdbedit` all work. Only `smbclient` (and
  `tcpdump`) needed a manual `apt install` — that was done on 2026-07-05.

## `/etc/samba/smb.conf` (live)

```ini
[global]
   workgroup = OLYMPUS
   server string = Muse of Memory
   netbios name = CLIO
   security = user
   map to guest = Bad User
   server min protocol = SMB2_10
   server role = standalone server
   disable netbios = no
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   deadtime = 15

[public]
   comment = Public (guest)
   path = /srv/nas/public
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 0775
   force group = users

[alpha]
   comment = alpha private
   path = /srv/nas/alpha
   browseable = yes
   read only = no
   guest ok = no
   valid users = alpha
   create mask = 0644
   directory mask = 0755
```

Cosmetic curios (not bugs):
- `pdbedit -L -v alpha` reports `Domain: WINPC`. That's Samba's
  default machine-SID domain string, unrelated to workgroup `OLYMPUS`.
- Home dir `\\clio\alpha` uses lowercase OS hostname, not netbios
  `CLIO`. Cosmetic.

## Why we built wsdd2 — and why kochinc's fork

**Modern Windows** (Win10 1709+) uses **WS-Discovery** (WSD) for
Explorer's Network browse view. Without a WSD responder, `CLIO` will
not appear even if Samba is perfect. NetBIOS still works for
`net use \\CLIO\...` (client falls back), but browse-discovery needs
WSD.

**Debian Stretch does not package `wsdd`** — stage3 tries `apt install
wsdd || true` and it silently fails.

Options considered:
- **christgau/wsdd** (Python): rejected. Pulls Python 3 + deps on a
  226 MB box. Blows the RAM budget.
- **Netgear/wsdd2** (C): the canonical ReadyNAS-lineage minimal C
  daemon. Original Netgear repo is 404 now.
- **kochinc/wsdd2**: live fork of the Netgear code (ReadyNAS v6.9.3-
  era). Pure C, no `libsystemd` dep, ~30 KB stripped. **Chosen.**

## The build — chroot-native, deliberately not cross-compile

[FACT] Cross-compile from Ubuntu 24.04 host toolchain
(`arm-linux-gnueabihf-gcc 13.3.0`) fails two ways. Both are pervasive
header problems, not sysroot-flag fixes:

1. **Symbol-version leak.** Objects end up referring to `GLIBC_2.34`
   and `GLIBC_2.38` symbols that don't exist in Stretch's
   `libc-2.24.so`. Setting `--sysroot=` alone doesn't override the
   toolchain's default library search paths.
2. **Time64/t64 transition.** Ubuntu 24.04's headers t64-transitioned
   glibc — objects end up with `__time64`, `__isoc23_fscanf`,
   `__isoc23_strtol`, `__setsockopt64` references Stretch's glibc
   doesn't provide.

**Chosen path — chroot-native.** User's words: *"bullet proof. I like
bullet proof."*

- Chroot into `/home/alpha/nas_old/Cloud3TB/rootfs-stretch/` via
  `qemu-arm-static` + binfmt_misc (registered `F` flag).
- `apt-get -o Acquire::Check-Valid-Until=false install build-essential`
  inside → gets stretch's own `gcc-6.3.0-18+deb9u1`.
- Build there. Native → stretch headers → no t64, no GLIBC 2.34, no
  cross-header surprises.

Sysroot pre-population debs at
`.../scratchpad/debs/libc6-dev_2.24-11+deb9u4_armhf.deb` and
`.../scratchpad/debs/linux-libc-dev_4.9.228-1_armhf.deb`.

**Build artifact (deployed at `/usr/local/sbin/wsdd2`):**
- 31 192 bytes stripped.
- SHA-256 `8efa9ea4ea8f9f135ad12ebf00ed1d5f31e8ad29525c0336c3f55a406acc2942`.
- ABI note `for GNU/Linux 3.2.0` (matches min-kernel of stretch glibc).
- `NEEDED` = `libc.so.6` only.
- All GLIBC syms at `GLIBC_2.4`.
- `LOAD` alignment `0x10000` (via `-Wl,-z,max-page-size=0x10000`).
- `qemu-arm-static` smoke test prints usage cleanly.

Source is not archived locally. Pulled to
`.../scratchpad/wsdd2-src/` on 2026-07-05 for the diagnostic dive.
Fresh sessions can `curl` from `raw.githubusercontent.com/kochinc/wsdd2/master/`
(HTTP 200 on `wsdd2.c`, `wsd.c`, `llmnr.c`, `wsdd2.h`, `Makefile`).
**TODO:** stash a canonical copy in this working dir.

## The init script (live)

`/etc/init.d/wsdd2` — `Required-Start: $network $remote_fs $syslog
smbd nmbd` (NOT `samba` — that fails `insserv` because samba scripts
are split). Backgrounds via `start-stop-daemon --background`. Logs
to `/var/log/wsdd2.log`.

Two rough edges:
- `Required-Stop:` line omits `smbd nmbd` (asymmetric with
  `Required-Start`). Not a bug.
- **The init script's `stop` doesn't reliably kill the running
  daemon.** After several restarts during debugging, `service wsdd2
  stop` returned "not running" while `pidof wsdd2` still returned a
  live pid. Suspect: PID-file / process-name mismatch in
  `start-stop-daemon --stop`. If you're iterating, verify with
  `pidof wsdd2` and `kill -9` if needed.

## kochinc/wsdd2 CLI surface — narrower than docs suggest

`-4 -6 -L -W -b:... -d -h -l -t -u -w`. No `-i` (auto-binds all up
interfaces with multicast), no `-N`. Workgroup and netbios name are
read from `/etc/samba/smb.conf` via `get_smbparm()` — Samba is source
of truth.

- **`-d` means "don't daemonize", NOT "debug output".** The
  foreground output is identical to `/var/log/wsdd2.log`. There is
  no verbose flag.
- **`-4` does NOT skip IPv6 endpoint attempts** — the IPv6 bind
  errors still hit the log with `-4` in play. Flag semantics differ
  from what the flag character suggests.

## Endpoints the daemon INTENDS to open

From `wsdd2.c` source review (2026-07-05), the `services[]` array
declares these:

| name             | family  | proto | port | mcast group      | note              |
|------------------|---------|-------|------|------------------|-------------------|
| `wsdd-mcast-v4`  | AF_INET | UDP   | 3702 | 239.255.255.250  | WSD receive       |
| `wsdd-mcast-v6`  | AF_INET6| UDP   | 3702 | ff02::c          | WSD receive       |
| `wsdd-http-v4`   | AF_INET | TCP   | 3702 | —                | WSD metadata GET  |
| `wsdd-http-v6`   | AF_INET6| TCP   | 3702 | —                | WSD metadata GET  |
| `llmnr-udp-v4/6` | both    | UDP   | 5355 | 224.0.0.252 / ff02::1:3 | LLMNR resolve |
| `llmnr-tcp-v4/6` | both    | TCP   | 5355 | —                | LLMNR resolve TCP |

(Note the daemon calls the WSD receive endpoint `wsdd-mcast-vN`, NOT
`wsdd-udp-vN`. Grep the log for `mcast` if you need to see mcast
failures — but see next section for why you won't.)

## The actual root cause of Explorer discovery failure

**[FACT]** On this box, wsdd2 opens: WSD-HTTP TCP v4, LLMNR TCP v4,
LLMNR UDP v4, LLMNR UDP v6 (×3, once per IPv6 address on eth0). It
does **NOT** open `wsdd-mcast-v4` or `wsdd-mcast-v6`.

Verified across every restart cycle:

```
$ sudo netstat -tunlp | grep wsdd2
tcp   0.0.0.0:5355  LISTEN  wsdd2      # LLMNR TCP v4
tcp   0.0.0.0:3702  LISTEN  wsdd2      # WSD HTTP transfer TCP v4
udp   0.0.0.0:5355          wsdd2      # LLMNR UDP v4
udp6  :::5355               wsdd2      # LLMNR UDP v6 × 3
```

No UDP 3702, v4 or v6.

```
$ sudo cat /proc/net/igmp   # eth0 rows
FC0000E0 = 224.0.0.252 (LLMNR)  ✓ joined
010000E0 = 224.0.0.1   (all-hosts, kernel default) ✓
```

`239.255.255.250` (WSD, would encode `FAFFFFEF`) is **not joined**.

Consequences:
1. Cannot receive multicast Probe requests from Windows → cannot
   respond → **not discoverable via active probing.**
2. `sudo timeout 12 tcpdump -i eth0 'udp and port 3702'` during and
   after `service wsdd2 restart` captured **0 packets** → not
   emitting Hello broadcasts either.

The log is unhelpful — it prints `open_ep` failures for
`wsdd-http-v6` (× 3, one per IPv6 addr on eth0) and `llmnr-tcp-v6`
(× 3) but **never mentions `wsdd-mcast`** at all. Whatever is
preventing the multicast endpoint from opening, the daemon isn't
reporting it. Either:
- The iteration skips the mcast entries before calling `open_ep()`, or
- `open_ep()` fails on them without logging (unlike the http/tcp
  failures which DO log via a `perror`-style path).

The source declares the endpoints in `wsdd2.c` at lines 30–52 —
they're not missing from the array. The failure is in the runtime
path.

## Also learned about kochinc/wsdd2 the hard way

- **No `SO_REUSEADDR`.** Kill a foreground `-d` run and the sockets
  linger in TIME_WAIT; the next init-restart hits `EADDRINUSE` on v4
  endpoints too. Wait a minute or forcibly reboot the daemon later.
- **`Required-Stop` and PID handling in the init script are shaky.**
  See §7. `pidof` + explicit `kill -9` is the reliable path during
  iteration.
- **IPv6 3× retries explained:** eth0 has three IPv6 addresses
  (global `2a02:c7e:...`, ULA `fd4e:...`, link-local `fe80::...`).
  The daemon likely iterates per-address for AF_INET6 endpoints and
  each retry after the first hits `EADDRINUSE` from its own earlier
  wildcard bind.

## Hypotheses for the missing WSD-UDP endpoint — ranked

Given source review + observed behavior:

1. **[HYPOTHESIS, medium-high]** `wsd_init` (the per-endpoint
   `.init` callback for `wsdd-mcast-*` — see `wsd.c`) is failing
   silently, and open_ep tears down the endpoint without logging.
   Multicast join can fail on interfaces with unusual link
   behavior. Would need to instrument `wsd_init` or strace the
   `setsockopt(IP_ADD_MEMBERSHIP)` call to confirm.
2. **[HYPOTHESIS, medium]** The daemon's interface iteration
   filters out interfaces without a specific flag combination
   (BROADCAST + MULTICAST + up). eth0 has `<BROADCAST,MULTICAST,UP,
   LOWER_UP>` — should qualify. But something in the filter may not
   like the PFE-driven eth0.
3. **[HYPOTHESIS, low, but ruled out cleanly]** Bug in flag parsing
   causing the mcast services to be filtered out. Grep shows lines
   598–617 handle `_LLMNR` / `_WSDD` service filtering by name
   substring — `wsdd-mcast-v4` contains `wsdd`, would match
   `_WSDD`, should not be filtered. Not this.

The disproven hypothesis from an earlier pass:

- **[DISPROVEN]** "Pass `-4` to skip the IPv6 issues and mcast will
  come up." Tried on 2026-07-05. Result: mcast still absent, IPv6
  bind errors still logged. `-4` doesn't fix it and doesn't even
  suppress v6 attempts.

## Concrete next moves

In order of effort/likelihood:

1. **Read `open_ep()` and `wsd_init()` end-to-end** in the fetched
   source (`.../scratchpad/wsdd2-src/`) — find the silent-fail
   path. Look for the `IP_ADD_MEMBERSHIP` setsockopt and any early
   `return -1` that doesn't log.
2. **strace the mcast setsockopt** — `sudo strace -f -e trace=network
   /usr/local/sbin/wsdd2 -d 2>&1 | head -80`. Look for
   `setsockopt(*, IPPROTO_IP, IP_ADD_MEMBERSHIP, ...)` on
   239.255.255.250 and its return value.
3. **Patch a `fprintf(stderr, ...)` into the mcast failure path**,
   rebuild in the same chroot, redeploy. Only ~5 lines of C to
   confirm.
4. **Consider the christgau/wsdd Python daemon** despite the RAM
   cost — measure it first (`ps -o rss` after startup). If it fits
   in 15 MB it might be acceptable; if it's 40+ MB, no.
5. **NetBIOS-only fallback for now.** Discovery via WSD is dead
   until the mcast issue is fixed, but `\\CLIO\alpha` via NetBIOS
   fallback should work from Windows if the Credential Manager
   entry is right — see next section.

## Windows-side considerations for `net view \\CLIO` Error 5

Two independent factors, both plausible:

1. **Windows blocks guest SMB2+ auth on the client side** since
   Win10 1709. Explorer won't send guest credentials even to a
   healthy guest share. Fix: cache alpha creds in Windows Credential
   Manager, or `net use \\CLIO\alpha /user:alpha *` prompting once.
   The registry flip `AllowInsecureGuestAuth = 1` exists but is
   not recommended.
2. **Discovery/browse services on the Windows client.** Even with
   valid creds, `net view` may fail if Function Discovery Provider
   Host (FDPH) / Function Discovery Resource Publication (FDResPub)
   aren't running or the network profile is Public. Check
   `services.msc` + network profile before drawing wsdd2
   conclusions from Error 5 alone.

## Rollback / clean-uninstall (if wsdd2 needs to go)

```sh
sudo service wsdd2 stop
pidof wsdd2 && sudo kill -9 $(pidof wsdd2)     # init stop is unreliable
sudo update-rc.d -f wsdd2 remove
sudo rm /etc/init.d/wsdd2 /usr/local/sbin/wsdd2 \
       /var/run/wsdd2.pid /var/log/wsdd2.log
```

Samba is independent — leaving it running is safe. LLMNR + NetBIOS
name resolution keeps working via `nmbd`.

## What is NOT verified

- Whether Windows FDPH / FDResPub services are running on the
  target Win10/11 box, and what network profile is active. Need
  eyeballs on Windows.
- Whether `IP_ADD_MEMBERSHIP` on `239.255.255.250` succeeds on the
  PFE-driven eth0 in general (not just via wsdd2). A tiny C stub
  could probe this in ~30 lines.
- Whether the PFE's `disable_wifi_offload=1` mode alters the RX
  path for arbitrary multicast groups the same way it did for
  broadcasts pre-fix. Unlikely but not ruled out.
