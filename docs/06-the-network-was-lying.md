# 6 · The network was lying

*(Status: outline — to be drafted. Act III; synopsis in route map.)*

Covers:

- **Firmware without udev**: pre-3.7 kernels can't load firmware from
  the filesystem; they call a userspace helper — which used to be udev.
  Symptom: `pfe: probe failed -110` (`request_firmware` timeout), no
  eth0. Fix: `sbin/fw-helper` + `echo /sbin/fw-helper >
  /proc/sys/kernel/hotplug` in eth0's `pre-up`, *before* the driver
  loads.
- **The `disable_wifi_offload=1` saga** — the hardest bug of the
  project. Box boots, syncs NTP outbound, serves nothing inbound: the
  PFE's VWD/wifi-offload datapath hijacks host-bound broadcast RX, so
  ARP "who-has" never reaches Linux and nobody can find the box, while
  everything looks healthy from inside. Promiscuous/allmulticast do
  nothing (the PFE ignores Linux interface flags). Found by **diffing
  stock's `/etc/modules`**. Moral: when a vendor datapath exists, the
  host's view of its own NIC is fiction.
- The full load-bearing eth0 stanza, line by line
  (`rootfs-overlay/etc/network/interfaces`), incl. `arp_notify=1` for
  the late-carrier gratuitous-ARP loss, and the belt-and-braces
  `modprobe.d/pfe.conf`.
- Surprise: IPv6 comes up fully (3 addresses) — matters later for wsdd2.

Sources: `field-notes/FINDINGS.md` §2.6–2.7, §3.2, §3.4;
`field-notes/HANDOVER-OS.md` (eth0 section).
