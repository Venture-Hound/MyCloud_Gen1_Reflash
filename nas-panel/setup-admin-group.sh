#!/bin/bash
# One-off on clio: introduce smbadmins group (panel "admin" concept),
# allow blank-password SMB accounts, migrate share access lists.
# Idempotent. Run as root.
set -e

echo "== group smbadmins (+alpha)"
getent group smbadmins >/dev/null || addgroup --quiet smbadmins
usermod -aG smbadmins alpha

echo "== null passwords = yes in [global] (blank-password accounts)"
if ! grep -q "null passwords" /etc/samba/smb.conf; then
	sed -i '/^\[global\]/a\   null passwords = yes' /etc/samba/smb.conf
fi

echo "== migrate valid users lines to @smbadmins"
# One stanza per family share — edit these to your own usernames (example
# names shown). This is a historical migration script; a fresh build from
# build/ creates shares with @smbadmins already in place (see make-shares.sh).
sed -i '/^\[alice\]/,/^\[/ s/^\(   \)valid users = .*/\1valid users = alice @smbadmins/' /etc/samba/smb.conf
sed -i '/^\[bob\]/,/^\[/   s/^\(   \)valid users = .*/\1valid users = bob @smbadmins/'   /etc/samba/smb.conf
sed -i '/^\[carol\]/,/^\[/ s/^\(   \)valid users = .*/\1valid users = carol @smbadmins/' /etc/samba/smb.conf
sed -i '/^\[alpha\]/,/^\[/  s/^\(   \)valid users = .*/\1valid users = alpha @smbadmins/'  /etc/samba/smb.conf
sed -i '/^\[admin\]/,/^\[/  s/^\(   \)valid users = .*/\1valid users = @smbadmins/'        /etc/samba/smb.conf

testparm -s /etc/samba/smb.conf >/dev/null && echo "testparm OK"
service smbd reload >/dev/null
grep -E "^\[|valid users|null passwords" /etc/samba/smb.conf | head -30
echo "SETUP-OK"
