#!/bin/bash
# remote-install.sh — installs the NAS panel on clio. Run as root there.
set -e
SRC=/tmp/nas-panel

echo "== dirs"
install -d -m 755 /usr/local/lib/nas-panel /usr/local/nas-panel/www

echo "== privileged wrappers"
install -m 755 "$SRC/panel-op" "$SRC/led-status" /usr/local/lib/nas-panel/
install -m 755 "$SRC/recycle-purge" "$SRC/smart-monthly" /usr/local/lib/nas-panel/
install -m 644 "$SRC/cron-nas-maint" /etc/cron.d/nas-maint

echo "== www"
install -m 755 "$SRC"/www/*.cgi /usr/local/nas-panel/www/
install -m 644 "$SRC"/www/lib.sh /usr/local/nas-panel/www/

echo "== sudoers (visudo-validated before install)"
visudo -cf "$SRC/sudoers-nas-panel"
install -m 440 "$SRC/sudoers-nas-panel" /etc/sudoers.d/nas-panel

echo "== lighttpd"
cp -an /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
install -m 644 "$SRC/lighttpd.conf" /etc/lighttpd/lighttpd.conf
PANELPASS="CHANGE_ME_panel_password"   # change this before deploying, or straight after — see docs/09-web-panel.md for the one-line htdigest regen if you forget
H=$(printf 'alpha:CLIO NAS:%s' "$PANELPASS" | md5sum | cut -d' ' -f1)
printf 'alpha:CLIO NAS:%s\n' "$H" > /etc/lighttpd/nas-panel.htdigest
chown www-data:root /etc/lighttpd/nas-panel.htdigest
chmod 400 /etc/lighttpd/nas-panel.htdigest

echo "== LED boot hook + cron"
install -m 755 "$SRC/init-nas-led" /etc/init.d/nas-led
update-rc.d nas-led defaults >/dev/null 2>&1 || true
install -m 644 "$SRC/cron-nas-led" /etc/cron.d/nas-led

echo "== restart lighttpd"
service lighttpd restart

# (LED color vocabulary was probed once on 2026-07-05: blue/yellow/
# red/green/white + blink all accepted. Do NOT re-probe on deploys —
# rapid sysfs writes provoke the vendor driver's kernel oops.)

echo "== set LED from health now (retry once — first write after a
   driver oops can kill the writing process)"
/usr/local/lib/nas-panel/led-status || /usr/local/lib/nas-panel/led-status || true
echo "LED now: color=$(cat /sys/class/leds/system_led/color) blink=$(cat /sys/class/leds/system_led/blink) brightness=$(cat /sys/class/leds/system_led/brightness)"

echo "DEPLOY-OK"
