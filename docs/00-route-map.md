# Route map

Replacing the OS on a 1st-gen WD MyCloud (Comcerto 2000 SoC, vendor
3.2.26 kernel, **64 KB pages**, 256 MB RAM) with Debian 9 Stretch —
Samba, WSD discovery for modern Windows, and a lightweight web admin
panel — with **no serial console** at any point.

If you came here from a search engine with one specific error, jump
straight to its chapter; each stands alone. If you're attempting the
whole journey, read in order. If you just like a story, start at the
[README](../README.md).

Two things here are reusable far beyond MyClouds:

- **The no-serial debugging method** — a breadcrumb ladder that turns
  silent `panic=3` reboot loops into a binary search
  ([ch. 5](05-flying-blind.md)).
- **The 64 KB-page discipline** — readelf-check everything, newer
  distros are *worse*, chroot-native builds, and the
  `max-page-size` rebuild recipe ([ch. 3](03-choosing-an-os.md),
  [lib-rebuilds/](../lib-rebuilds/README.md)).

---

**Act I — The Patient.** *In which we meet a small appliance long
consigned to a cupboard · the internet proves confidently wrong about
what is inside it · the ethernet turns out to be bespoke and answerable
to no one · and we resolve to replace everything except the one part
nobody else can supply.*

1. [What the hardware actually is](01-hardware.md)
2. [The boot chain, and its footguns](02-boot-chain.md)

**Act II — Flying Blind.** *In which the machine is given four new
operating systems and says nothing about any of them · a promising
theory is tried at length and found innocent · the patient is briefly
restored to factory condition to prove the fault is ours · breadcrumbs
are laid through the forest · and the culprit proves to be the component
whose only job is to notice when hardware arrives.*

3. [Choosing an OS (or: newer is worse)](03-choosing-an-os.md)
4. [Building the rootfs](04-building-the-rootfs.md)
5. [Flying blind — debugging without a serial console](05-flying-blind.md) ★

**Act III — The Network Was Lying.** *In which the box makes outbound
calls but receives none · asks the time and is told it, yet cannot be
pinged · flags are waved at the network card, which ignores them, being
above that sort of thing · and the answer is found written in the
factory's own configuration all along.*

6. [The network was lying](06-the-network-was-lying.md)
7. [Flash runbook](07-flash-runbook.md)

**Act IV — Becoming a NAS.** *In which files are served but Windows
declines to notice · a small daemon is compiled the hard way, twice ·
discovery fails for want of sixteen bytes of identity · and the final
villain is revealed to be a missing line break on an entirely different
computer.*

8. [Samba, wsdd2, and the discovery saga](08-samba-and-discovery.md)

**Act V — Making It Liveable.** *In which several respectable control
panels are declined on grounds of obesity · a new one is raised from
shell scripts and optimism · the status light is found capable of
crashing the kernel, and a lasting peace is negotiated · and two more
libraries must be rebuilt before a single note of music is heard.*

9. [The web admin panel](09-web-panel.md)
10. [Peripherals: LED, USB, recycle bin, DLNA, SMART](10-peripherals.md)

**Coda.** *In which our mistakes are ranked by cost · the roads not
worth taking are signposted · and notes are left for the next
traveller.*

11. [Lessons and dead-ends, ranked](11-lessons-and-dead-ends.md)

---

The [field-notes/](field-notes/) directory holds the contemporaneous
working documents, published as written — including the theories that
later died.

## Safety

Only the ~1.9 GB root RAID (`md1`, ext3) is ever rewritten. The vendor
kernel partitions and the multi-TB data partition are untouched, and a
full stock image backup makes restore a single `dd`. "Bricked" here only
ever meant "boots but invisible" — always re-flashable. Tested on
exactly one unit; keep it LAN-only and change the build's default
credentials.
