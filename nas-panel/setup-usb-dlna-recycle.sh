#!/bin/bash
# One-off setup on a running box: add the [usb] share, install+configure
# minidlna (off by default — DLNA is an optional feature, toggled from
# the panel). Idempotent. Run as root.
#
# For a box built from the corrected build/ scripts, avahi is never
# installed, the extra USB static device nodes are already baked by
# rootfs-overlay/dev-nodes.sh, and recycle is already on every share
# make-shares.sh creates — this script no longer needs to retrofit any
# of that. It's kept narrow to just the two things that remain genuinely
# post-flash: the USB share, and DLNA (which needs two more chroot lib
# rebuilds — see lib-rebuilds/README.md — so it stays opt-in rather than
# baked into every fresh build).
set -e

echo "== usb mountpoint + [usb] share"
mkdir -p /srv/nas/usb
if ! grep -q '^\[usb\]' /etc/samba/smb.conf; then
	cat >> /etc/samba/smb.conf <<'EOF'

[usb]
   comment = USB drive (mount via admin panel)
   path = /srv/nas/usb
   browseable = yes
   read only = no
   guest ok = no
   valid users = @users
   force group = users
   create mask = 0664
   directory mask = 2775
EOF
	testparm -s >/dev/null
	service smbd reload >/dev/null
	echo "[usb] share added"
fi

echo "== minidlna (installed but OFF until started from panel)"
echo "   NOTE: needs 64K-aligned libogg + libXau first — see lib-rebuilds/README.md."
echo "   Stretch ships both 32K-aligned; minidlnad will fail to start until rebuilt."
if ! dpkg -l minidlna 2>/dev/null | grep -q ^ii; then
	apt-get -o Acquire::Check-Valid-Until=false update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minidlna 2>&1 | tail -2
fi
sed -i \
	-e 's|^media_dir=.*|media_dir=A,/srv/nas/music|' \
	-e 's|^#friendly_name=.*|friendly_name=CLIO Music|' \
	-e 's|^friendly_name=.*|friendly_name=CLIO Music|' \
	-e 's|^#inotify=.*|inotify=yes|' \
	/etc/minidlna.conf
service minidlna stop 2>/dev/null || true
update-rc.d minidlna disable 2>/dev/null || true
echo "minidlna configured for /srv/nas/music, disabled at boot"

echo "SETUP-OK"
