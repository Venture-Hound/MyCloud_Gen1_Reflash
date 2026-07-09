#!/bin/bash
cd "$(dirname "$0")" && . ./lib.sh
read_post

msg=""
if [ "${REQUEST_METHOD:-GET}" = POST ]; then
	case "$(getv action)" in
	usb-mount)  msg=$($SUDO $OPBIN usb-mount 2>&1) ;;
	usb-eject)  msg=$($SUDO $OPBIN usb-eject 2>&1) ;;
	dlna-start) msg=$($SUDO $OPBIN dlna-start 2>&1) ;;
	dlna-stop)  msg=$($SUDO $OPBIN dlna-stop 2>&1) ;;
	esac
fi

page_top "CLIO status"
[ -n "$msg" ] && echo "<p><b>$(printf '%s' "$msg" | esc)</b></p>"

S=$($SUDO $OPBIN status 2>&1)
getsec(){ printf '%s\n' "$S" | awk -v s="## $1" '$0==s{f=1;next} /^## /{f=0} f'; }

smart=$(getsec smart)
case "$smart" in
	PASSED)  sm="<span class=ok>PASSED</span>" ;;
	standby) sm="<span class=ok>disk in standby (not woken for check)</span>" ;;
	FAILED)  sm="<span class=bad>FAILED — back up data and replace the disk!</span>" ;;
	*)       sm="<span class=warn>$(printf '%s' "$smart" | esc)</span>" ;;
esac

md=$(getsec md)
if printf '%s' "$md" | grep -o '\[[U_]*\]' | grep -q '_'; then
	mdst="<span class=bad>DEGRADED</span>"
else
	mdst="<span class=ok>OK</span>"
fi

echo "<table>"
echo "<tr><th>SMART health</th><td>$sm</td></tr>"
echo "<tr><th>RAID (md1)</th><td>$mdst <small>$(printf '%s\n' "$md" | head -1 | esc)</small></td></tr>"
echo "<tr><th>Uptime</th><td>$(getsec uptime | esc)</td></tr>"
echo "<tr><th>Memory (MB)</th><td><small>$(getsec mem | esc)</small></td></tr>"
echo "<tr><th>LED</th><td><small>$(getsec led | esc)</small></td></tr>"
echo "</table>"

echo "<h2>Disk space</h2>"
echo "<table><tr><th>Filesystem</th><th>Size</th><th>Used</th><th>Avail</th><th>Use%</th><th>Mount</th></tr>"
getsec df | while read -r fs size used avail pct mnt; do
	p=${pct%\%}
	cls=ok
	[ "${p:-0}" -ge 90 ] 2>/dev/null && cls=bad
	echo "<tr><td>$fs</td><td>$size</td><td>$used</td><td>$avail</td><td class=$cls>$pct</td><td>$mnt</td></tr>"
done
echo "</table>"

echo "<h2>Services</h2><table>"
getsec services | while read -r s st; do
	c=bad; [ "$st" = up ] && c=ok
	echo "<tr><th>$s</th><td class=$c>$st</td></tr>"
done
echo "</table>"

echo "<h2>USB drive</h2>"
usb=$($SUDO $OPBIN usb-status 2>&1)
case "$usb" in
absent)
	echo "<p>No USB drive plugged in.</p>" ;;
mounted*)
	echo "<p class=ok>Mounted: ${usb#mounted } — available as <b>\\\\CLIO\\usb</b></p>"
	echo "<form method=post><input type=hidden name=action value=usb-eject><input type=submit value='Eject (before unplugging)'></form>" ;;
*)
	echo "<p>Drive detected, not mounted.</p>"
	echo "<form method=post><input type=hidden name=action value=usb-mount><input type=submit value='Mount as \\\\CLIO\\usb'></form>" ;;
esac

echo "<h2>Music player server (DLNA)</h2>"
dl=$($SUDO $OPBIN dlna-status 2>&1)
if [ "$dl" = running ]; then
	echo "<p class=ok>Running — players see \"CLIO Music\" on the network.</p>"
	echo "<form method=post><input type=hidden name=action value=dlna-stop><input type=submit value='Stop DLNA'></form>"
else
	echo "<p>Stopped.</p>"
	echo "<form method=post><input type=hidden name=action value=dlna-start><input type=submit value='Start DLNA'></form>"
fi

page_end
