#!/bin/bash
# Create family users + shares on a running box. Idempotent — safe to re-run.
# Run as root on the NAS itself (over ssh), after stage2/stage3 have been
# flashed and the box is up. Edit the FAMILY list and TEMP_PASSWORD below
# for your own household before running.
set -e

FAMILY="alice bob carol"          # <- edit: your family usernames
TEMP_PASSWORD="CHANGE_ME_temp_password"   # starter SMB password — change per-user via the panel after first login, or leave blank there for a no-password account

cp -an /etc/samba/smb.conf "/etc/samba/smb.conf.bak-$(date +%Y-%m-%d)"

echo "=== users"
for u in $FAMILY; do
  if ! id -u "$u" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$u"
  fi
  usermod -aG users "$u"
  if ! pdbedit -L | grep -q "^$u:"; then
    (echo "$TEMP_PASSWORD"; echo "$TEMP_PASSWORD") | smbpasswd -a -s "$u"
  fi
  mkdir -p "/srv/nas/$u"
  chown "$u:users" "/srv/nas/$u"
  chmod 2770 "/srv/nas/$u"
  echo "user $u ok"
done

usermod -aG users alpha
mkdir -p /srv/nas/admin /srv/nas/music
chown alpha:users /srv/nas/admin && chmod 2770 /srv/nas/admin
chown alpha:users /srv/nas/music && chmod 2775 /srv/nas/music

RECYCLE='   vfs objects = recycle
   recycle:repository = .recycle/%U
   recycle:keeptree = yes
   recycle:versions = yes
   recycle:directory_mode = 0770
   recycle:exclude = *.tmp,*.temp,~$*,*.TMP'

echo "=== shares"
for u in $FAMILY; do
  if ! grep -q "^\[$u\]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf <<EOF

[$u]
$RECYCLE
   comment = $u private
   path = /srv/nas/$u
   browseable = yes
   read only = no
   guest ok = no
   valid users = $u @smbadmins
   force group = users
   create mask = 0664
   directory mask = 2775
EOF
    echo "share [$u] added"
  fi
done

if ! grep -q "^\[admin\]" /etc/samba/smb.conf; then
  cat >> /etc/samba/smb.conf <<EOF

[admin]
$RECYCLE
   comment = Admin (admins only)
   path = /srv/nas/admin
   browseable = yes
   read only = no
   guest ok = no
   valid users = @smbadmins
   create mask = 0660
   directory mask = 2770
EOF
  echo "share [admin] added"
fi

if ! grep -q "^\[music\]" /etc/samba/smb.conf; then
  cat >> /etc/samba/smb.conf <<EOF

[music]
$RECYCLE
   comment = music (guest ok)
   path = /srv/nas/music
   browseable = yes
   read only = no
   guest ok = yes
   force group = users
   create mask = 0664
   directory mask = 2775
EOF
  echo "share [music] added"
fi

echo "=== validate config"
testparm -s >/dev/null
echo "testparm OK"

echo "=== reload smbd"
service smbd reload

echo "=== SMB users now:"
pdbedit -L
