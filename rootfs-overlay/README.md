# rootfs-overlay — the hand-won fixes, as real files

This tree is copied verbatim into the rootfs by the build scripts (see
`build/`), so every fix is inspectable here as a plain file rather than
buried in a heredoc. Layout mirrors the target filesystem root.

| File | What it is / why it exists |
|---|---|
| `etc/inittab` | Wires the two `sysinit` actions that run **before** rcS: `initmarker` (boot breadcrumb) then `devfs`, then rcS. Lines 9–11 are the interesting ones. |
| `etc/init.d/initmarker` | Earliest boot breadcrumb — writes `/INIT-RAN.txt` on the root fs the moment `/sbin/init` parses inittab. Rung 2 of the no-serial debugging ladder (`docs/05-flying-blind.md`). |
| `etc/init.d/devfs` | Best-effort `mount -t devtmpfs`. **On this kernel it is a silent no-op** (no `CONFIG_DEVTMPFS`) — real `/dev` coverage comes from ~144 static nodes baked at build time. Kept because it costs nothing and would shadow the static nodes harmlessly on a kernel that has devtmpfs. |
| `etc/init.d/udev` | **No-op stub that still `Provides: udev`.** Modern udev (v232) hangs rcS on the 3.2.26 kernel — the single most expensive discovery of the project. The stub keeps insserv's dependency graph satisfied while udevd never runs. |
| `etc/init.d/canary` | Early-rcS breadcrumb → writes to the data partition. Rung 3 of the ladder. |
| `etc/init.d/firstboot-diag` | End-of-boot diagnostic dump (ip/lsmod/dmesg-pfe/services) to the data partition. Rung 4. |
| `etc/init.d/wsdd2` | SysV init for the WSD/LLMNR daemon. `Required-Start: … smbd nmbd` — NOT `samba` (Stretch splits the init scripts; insserv rejects a `samba` facility). |
| `etc/init.d/nas-led` | Boot-time LED status (delegates to the panel's `led-status`; see `nas-panel/`). COLOR-ONLY policy — the vendor LED driver kernel-oopses on brightness writes (`docs/10-peripherals.md`). |
| `sbin/fw-helper` | Userspace firmware loader. Pre-3.7 kernels can't load firmware from the filesystem themselves; the helper that used to do it was udev, which we removed. Registered via `echo /sbin/fw-helper > /proc/sys/kernel/hotplug` in eth0's `pre-up`, **before** the PFE driver's `request_firmware()`. Symptom when missing: `pfe: probe failed -110` and no eth0. |
| `etc/network/interfaces` | The load-bearing eth0 stanza. Every line matters — above all `disable_wifi_offload=1`, without which the PFE hijacks inbound broadcast RX and the box is unreachable while looking perfectly healthy from inside. |
| `etc/modprobe.d/pfe.conf` | Same PFE parameters again, so a manual `modprobe pfe` also gets them (belt and braces). |
| `etc/samba/smb.conf.template` | Sanitized share templates (one exemplar of each share type the panel generates). |

Not in this tree (deliberately): the vendor kernel modules and PFE
firmware are WD-proprietary and must be harvested from a stock image —
see `docs/01-hardware.md` for the method. The static `/dev` node baking
and the libsystemd stub installation live in the build scripts.
