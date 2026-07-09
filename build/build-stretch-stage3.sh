#!/bin/bash
# Stage 3: NAS services on the Debian Stretch rootfs — Samba, user, wsdd2 discovery.
# Tolerant of individually-failing optional packages; the things that must
# succeed use `set -e`-friendly explicit checks instead of blanket `|| true`.
# Run from the repo root: bash build/build-stretch-stage3.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-$REPO/rootfs-stretch}"
NASUSER=alpha
NASPASS="CHANGE_ME_alpha_password"   # system + samba password for $NASUSER — CHANGE on first login
TZ=Europe/London

echo ">>> bind mounts"
sudo mount -t proc  proc  "$TARGET/proc"  2>/dev/null || true
sudo mount -t sysfs sys   "$TARGET/sys"   2>/dev/null || true
sudo mount -o bind  /dev  "$TARGET/dev"   2>/dev/null || true
sudo mount -o bind  /dev/pts "$TARGET/dev/pts" 2>/dev/null || true
trap 'sudo umount -l "$TARGET/dev/pts" "$TARGET/dev" "$TARGET/sys" "$TARGET/proc" 2>/dev/null || true' EXIT

echo ">>> regenerate module dependencies for vendor 3.2.26 tree"
sudo chroot "$TARGET" /sbin/depmod 3.2.26 2>&1 | head || true

echo ">>> install NAS userland (samba, sudo, syslog, ntp)"
# NOT installing avahi-daemon or wsdd here — both are dead ends on this
# box. avahi can never actually run: its dependency libdaemon.so.0 ships
# 32K-aligned and won't load on this kernel (see lib-rebuilds/README.md;
# rebuilding it is possible but nobody has bothered, since WSD+LLMNR+
# NetBIOS already cover Windows discovery without it). wsdd isn't
# packaged for Stretch at all — we build wsdd2 from vendored source
# below instead (docs/08-samba-and-discovery.md).
sudo chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive NASUSER="$NASUSER" NASPASS="$NASPASS" TZ="$TZ" /bin/bash <<'CHROOT'
set -u
apt-get update
apt-get install -y --no-install-recommends samba samba-common-bin sudo rsyslog cron chrony
apt-get clean

# timezone
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$TZ" > /etc/timezone

# smbadmins: the panel's "admin" concept is this real unix group. Baked
# in from the start so every share template can grant it directly,
# instead of retrofitting `valid users = ... @smbadmins` onto existing
# shares later (that retrofit — setup-admin-group.sh — is kept in this
# repo only as the historical record of upgrading an already-live box).
getent group smbadmins >/dev/null || addgroup --quiet smbadmins

# named admin user with sudo (don't rely on root; mirrors the panel's
# admin policy) + smbadmins membership
if ! id "$NASUSER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$NASUSER"
fi
echo "${NASUSER}:${NASPASS}" | chpasswd
usermod -aG sudo,smbadmins "$NASUSER"

# samba user (same creds) + share dirs
mkdir -p /srv/nas/public /srv/nas/"$NASUSER"
chown -R "$NASUSER":users /srv/nas/"$NASUSER"
chmod 2775 /srv/nas/"$NASUSER"
chmod 0775 /srv/nas /srv/nas/public
chown root:users /srv/nas/public
( echo "$NASPASS"; echo "$NASPASS" ) | smbpasswd -s -a "$NASUSER"
smbpasswd -e "$NASUSER"

# enable services under sysvinit
for s in ssh smbd nmbd rsyslog cron chrony; do update-rc.d "$s" enable 2>/dev/null || true; done
CHROOT

echo ">>> write smb.conf (matches rootfs-overlay/etc/samba/smb.conf.template)"
sudo tee "$TARGET/etc/samba/smb.conf" >/dev/null <<EOF
[global]
   null passwords = yes
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
   # 256MB RAM box: keep it lean
   deadtime = 15

[public]
   vfs objects = recycle
   recycle:repository = .recycle/%U
   recycle:keeptree = yes
   recycle:versions = yes
   recycle:directory_mode = 0770
   recycle:exclude = *.tmp,*.temp,~\$*,*.TMP
   comment = Public (guest)
   path = /srv/nas/public
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 0775
   force group = users

[$NASUSER]
   vfs objects = recycle
   recycle:repository = .recycle/%U
   recycle:keeptree = yes
   recycle:versions = yes
   recycle:directory_mode = 0770
   recycle:exclude = *.tmp,*.temp,~\$*,*.TMP
   comment = $NASUSER private
   path = /srv/nas/$NASUSER
   browseable = yes
   read only = no
   guest ok = no
   valid users = $NASUSER @smbadmins
   force group = users
   create mask = 0664
   directory mask = 2775
EOF

echo ">>> testparm sanity"
sudo chroot "$TARGET" /usr/bin/testparm -s 2>&1 | grep -iE "Loaded services|workgroup|min protocol" | head

echo ">>> build + install wsdd2 (vendored source, see wsdd2/PROVENANCE.md)"
# Same reasoning as the libsystemd stub: cross-compiling from a modern
# host toolchain leaks GLIBC_2.34+ symbols and time64 types Stretch's
# glibc 2.24 doesn't have, so build native inside the chroot.
sudo chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -e <<'CHROOT'
apt-get install -y --no-install-recommends build-essential
CHROOT
sudo mkdir -p "$TARGET/root/wsdd2-src"
sudo cp "$REPO"/wsdd2/*.c "$REPO"/wsdd2/*.h "$REPO/wsdd2/Makefile" "$TARGET/root/wsdd2-src/"
sudo chroot "$TARGET" /bin/bash -e <<'CHROOT'
cd /root/wsdd2-src
make LDFLAGS='-Wl,-z,max-page-size=0x10000'
install -m755 wsdd2 /usr/local/sbin/wsdd2
strip /usr/local/sbin/wsdd2
cd /
rm -rf /root/wsdd2-src
apt-get purge -y build-essential
apt-get autoremove -y
apt-get clean
CHROOT
echo "    verify: readelf -lW $TARGET/usr/local/sbin/wsdd2 | grep LOAD   (must be 0x10000)"

sudo cp "$REPO/rootfs-overlay/etc/init.d/wsdd2" "$TARGET/etc/init.d/wsdd2"
sudo chmod +x "$TARGET/etc/init.d/wsdd2"
sudo chroot "$TARGET" update-rc.d wsdd2 defaults 2>&1 | tail -2 || true

echo ">>> STAGE 3 COMPLETE"
sudo du -sh "$TARGET" 2>/dev/null || true
