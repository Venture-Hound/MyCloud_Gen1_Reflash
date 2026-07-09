#!/bin/bash
# Back up the LIVE MyCloud OS partitions over SSH to a target dir (e.g. an
# external drive). Non-destructive: reads only. Run while the NAS is on
# the network. You'll be prompted for the root password interactively —
# this script does not store or automate it.
set -uo pipefail
DEST="${1:?usage: 00-backup-over-ssh.sh /path/to/MyCloud-backup-DATE}"
NASHOST="${NASHOST:-192.168.0.16}"   # or clio.local, if reachable
# Very old sshd on the vendor image only offers legacy RSA host/pubkey
# signatures that modern OpenSSH clients disable by default — these
# compat flags are required, not optional, against this specific box.
# ControlMaster/ControlPersist reuse one connection across every dd
# below, so a password-auth root login only prompts once.
CTL="$(mktemp -u)"
SSH="ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPath=$CTL -o ControlPersist=120 root@${NASHOST}"
trap 'ssh -o ControlPath="$CTL" -O exit root@${NASHOST} 2>/dev/null || true' EXIT

mkdir -p "$DEST"
echo ">>> partition table + disk info"
$SSH 'sfdisk -d /dev/sda 2>/dev/null; echo "---PARTITIONS---"; cat /proc/partitions; echo "---SMART---"; smartctl -i /dev/sda 2>/dev/null' > "$DEST/disk-info.txt"
$SSH 'sync'

# partition : human label
for spec in "1:rootfs" "5:kernel-a" "6:kernel-b" "7:config-a" "8:config-b"; do
  p="${spec%%:*}"; label="${spec##*:}"
  out="$DEST/sda${p}-${label}.img"
  echo ">>> imaging /dev/sda${p} (${label}) -> $(basename "$out")"
  $SSH "dd if=/dev/sda${p} bs=1M 2>/dev/null" | dd of="$out" bs=1M status=progress
done

echo ">>> checksums (this can take a minute)"
( cd "$DEST" && md5sum *.img > checksums.md5 && cat checksums.md5 )
echo ">>> sizes"
ls -la "$DEST"
echo ">>> BACKUP COMPLETE -> $DEST"
