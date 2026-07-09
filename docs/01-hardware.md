# 1 · What the hardware actually is

*(Status: outline — to be drafted. Act I opener; synopsis lives in the
route map.)*

Covers:

- Correcting the internet: **Comcerto 2000** (Mindspeed/Freescale,
  dual Cortex-A9, armhf) — NOT the Armada 370 many forum posts claim.
  Armada tooling and kernels do not apply.
- ~256 MB RAM (~226 usable) and what that budget means (pure-C daemons
  only; every service is a real cost).
- Ethernet = **PFE** (Packet Forwarding Engine), a proprietary hardware
  datapath with **no mainline driver** → the decision that shapes
  everything: keep the vendor 3.2.26 kernel, replace only userland.
- The 64 KB page size (how it was deduced from ELF alignment; full
  story in ch. 3).
- Disk layout table (GPT, p1/p2 root RAID1 md1 ext3, p3 swap, p4 data,
  p5–p8 kernel/U-Boot) — the only thing ever rewritten is md1.
- Harvesting the vendor bits (`/lib/modules/3.2.26`, PFE firmware
  `*_c2000.elf`) from a stock image — method only; the blobs are WD's
  and are not redistributed here.
- Prior art & references: fox-exe's MyCloud resources, the WD Community
  de-brick guides.

Sources: `field-notes/FINDINGS.md` §1, §7; DeBrick-era notes (2021).
