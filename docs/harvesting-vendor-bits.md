# Harvesting the vendor kernel modules and firmware

*(Status: outline — to be drafted.)*

Not redistributed here: WD's `pfe.ko` (built for the exact vendor
3.2.26 kernel) and the PFE firmware blobs (`*_c2000.elf`). These are
proprietary and specific to WD's build — copying someone else's would
almost certainly not load. You harvest your own from your own unit.

Covers (to be written up in full):

- Booting the drive once, stock, and pulling `/lib/modules/3.2.26/`
  (specifically the `pfe.ko` driver) plus `/lib/firmware/` off the
  running box or its mounted root partition — this is the same
  `p1`/rootfs partition the rest of the project treats as disposable,
  so do this **before** the first custom flash, or restore stock
  temporarily from a backup to get a second chance.
- What files matter: the kernel module, the firmware ELF(s) it
  requests (see `dmesg | grep -i firmware` on a stock boot), and the
  `/etc/modprobe.d` parameters stock ships (diffing these against a
  bare `modprobe pfe` is what surfaced `disable_wifi_offload=1` —
  see [`06-the-network-was-lying.md`](06-the-network-was-lying.md)).
- Where they get baked into the build: `build/build-stretch-stage2.sh`
  expects a `vendor-kernel-bits.tgz` staged at a known path — see that
  script's header comment for the exact expected layout.
- A pointer to WD's official firmware downloads (for anyone starting
  from a completely wiped or dead drive with no stock partition left
  to harvest from) and to the community de-brick resources that
  document the stock partition layout for other Gen-1 units.

If your unit's drive is already gone, or you can't get one clean stock
boot to harvest from, the community MyCloud rescue threads are the
next stop — partition layouts and firmware links referenced in
[`01-hardware.md`](01-hardware.md).
