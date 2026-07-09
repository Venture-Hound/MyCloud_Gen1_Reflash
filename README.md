# MyCloud_Gen1_Debian_Stretch_Reflash

Wherein I mount a rescue of an ancient ruin of a 1st generation WD MyCloud NAS · Discover it has excitingly non-standard proprietary hardware we will just have to live with · Realise we have travelled beyond the realms of Devuan Excalibur but meet Stretch, who still understands many of the strange local customs · And thence we manage to find our way home again, giving our new friend a proper network identity, a Samba server, a WS-Discovery daemon, and a web control panel · A most extraordinary journey: I felt my travelogue might be a helpful guide to anyone tempted to follow these winding paths.

> **The plain version, for search engines:** replacing the stock OS on a
> 1st-generation, single-bay WD MyCloud (Mindspeed/Freescale **Comcerto
> 2000** SoC, *not* Armada 370) with a custom **Debian 9 (Stretch) armhf**
> userland, while keeping WD's vendor kernel (its ethernet runs through a
> proprietary hardware engine with no mainline Linux driver). Result: a
> plain Samba NAS with modern Windows discovery and a lightweight web
> admin panel, on the vendor kernel, no cloud. Bring-up was done with
> **no serial console**. Start at [`docs/00-route-map.md`](docs/00-route-map.md).

## Giving our MyCloud NAS a new lease on life

Or, avoiding the manner of an adventurous Victorian explorer: if you
don't know it, the MyCloud is WD's basic single-drive network-attached
storage, designed for home use, with an ethernet connection to plug into
your router. Out of the box it provides network shares and a lightweight
media server — but ours was ancient, and after some drive issues and a
semi-successful attempt to reload the original drive images, it had gone
into the cupboard and been ignored for years. Fixing it up was beyond me
in any reasonable amount of time and effort.

Then Claude Code arrived, and I could pull the drive, put it on a SATA3
cable, and have Claude take a look. Credit where credit is due: Opus is
a lot better at low-level Linux systems management than I will ever be.
It took Opus to guide me into this jungle. It took Fable to get through
to the other side.

So we re-flashed an ailing first-generation WD MyCloud with a customised
version of Debian Stretch, to bring it back into use as an effective
domestic NAS. The basic re-flash with a new Debian had its moments, but
the real fun started when we discovered the non-standard proprietary
ethernet engine that we felt had to be treated as sacrosanct — no
mainline driver exists for it, so the vendor's own 2012-era kernel had
to stay. That kernel turned out to use **64 KB memory pages**, not the
usual 4 KB, which made Stretch the newest Debian we could use without
wave-upon-wave of recompilation — we still had to do a little. And did I
mention the mere **256 MB of RAM**? So we cut out udev and systemd for a
low-overhead static init (it's a locked-down appliance, after all), and
wrangled that non-standard ethernet engine until it would actually admit
inbound traffic. Then we installed and de-snagged a Samba server, built
a native WS-Discovery daemon so it announces itself properly to Windows
PCs, and gave it a lightweight web control panel for management — all
bash and lighttpd, no frameworks, no database. We even tamed the status
LED on the case so it gives the same chirpy blue when everything is good
(and discovered, the hard way, that poking it the wrong way can crash
the kernel).

We learnt a lot along the way, and the point of this repo is to share
those lessons on the off-chance someone else decides they want to get a
Gen-1 MyCloud back up and running. The contemporaneous working notes are
published largely as written — including the theories that turned out
wrong — because watching a bad theory die is often more useful than a
tidied-up summary that skips straight to the answer.

## Key decisions

- Early work was done with the drive pulled and on a SATA3 cable,
  directly flashing candidate builds.
- The proprietary low-level ethernet engine was left untouched — a
  potential "can of worms," and the one part nobody else can supply.
- We settled on Debian Stretch: newer armhf flips its default link
  alignment to 4 KB and simply won't boot on this kernel's 64 KB pages.
- Stripped the OS down to save memory, and found (or built) the
  lightest possible software for everything it runs.
- No serial console — bring-up used a home-grown breadcrumb-ladder
  method instead (see [`docs/05-flying-blind.md`](docs/05-flying-blind.md)),
  which turned out to be the most reusable idea in the whole project.

## Our new MyCloud NAS

End result:
- WD MyCloud Gen 1, 3 TB WD Red drive, ~256 MB RAM (~226 MB usable)
- Proprietary low-level ethernet engine, odd module parameters,
  everything compiled to 64 KB page alignment
- Debian 9 Stretch armhf (old but workable — mostly 64 KB-friendly, a
  little targeted recompilation for the rest)
- No udev, no systemd — sysvinit, to save RAM and dodge a kernel-hanging
  udev bug
- Samba, a native WS-Discovery daemon, SMART monitoring, NTP via chrony
- A bespoke web control panel — bash CGI scripts under lighttpd

## License and credit

Everything in this repo that we wrote is **MIT-licensed** (see
[`LICENSE`](LICENSE)). The one exception is [`wsdd2/`](wsdd2/), which
vendors upstream GPL-3.0 source (a NETGEAR-lineage WS-Discovery daemon,
via [kochinc/wsdd2](https://github.com/kochinc/wsdd2)) unmodified — see
[`wsdd2/PROVENANCE.md`](wsdd2/PROVENANCE.md). Also relied on: Samba,
lighttpd, smartmontools, minidlna, chrony, and qemu-user-static — thank
you to those projects and their maintainers. Full attribution and prior
art (including the community MyCloud rescue guides that gave us our
starting map) are in [`docs/01-hardware.md`](docs/01-hardware.md).

## Safety

Only the ~1.9 GB root RAID (`md1`, ext3) is ever rewritten. The vendor
kernel partitions and the multi-terabyte data partition are never
touched, and a full stock-image backup makes restoring the original
firmware a single `dd`. "Bricked" here only ever meant "boots but
invisible" — always re-flashable. Tested on exactly one unit; disk model
and partition sizes will vary. Keep it LAN-only — don't port-forward —
and change the build's default credentials before it ever leaves one.

V.H. — 9th July 2026