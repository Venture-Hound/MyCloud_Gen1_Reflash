#!/bin/bash
cd "$(dirname "$0")" && . ./lib.sh
read_post

if [ "${REQUEST_METHOD:-GET}" = POST ]; then
	act=$(getv action)
	if [ "$(getv confirm)" != on ]; then
		page_top "Power"
		echo "<p><b>Tick the confirm box first.</b></p>"
		echo '<p><a href="/power.cgi">back</a></p>'
		page_end; exit 0
	fi
	case "$act" in
	poweroff)
		$SUDO $OPBIN poweroff >/dev/null 2>&1
		page_top "Powering off"
		cat <<'EOF'
<p><b>CLIO is shutting down now.</b></p>
<ol>
<li>The LED blinks yellow while services stop and disks unmount.</li>
<li>Wait until the LED goes dark/steady and the drive stops spinning
— about 30&ndash;40 seconds.</li>
<li>Then it is safe to unplug the power.</li>
<li>To start again: plug the power back in. Boot takes about a minute;
the LED settles blue when all is well.</li>
</ol>
EOF
		page_end; exit 0 ;;
	reboot)
		$SUDO $OPBIN reboot >/dev/null 2>&1
		page_top "Rebooting"
		echo "<p>Rebooting — the panel will be back in about a minute.</p>"
		page_end; exit 0 ;;
	esac
fi

page_top "Power"
cat <<'EOF'
<p>The MyCloud has no power button — this page is the soft switch.
A clean shutdown here avoids any risk to the filesystem from pulling
the plug on a live disk.</p>

<h2>Reboot</h2>
<form method=post><input type=hidden name=action value=reboot>
<label><input type=checkbox name=confirm> confirm</label>
<input type=submit value="Reboot now"></form>

<h2>Power off</h2>
<form method=post><input type=hidden name=action value=poweroff>
<label><input type=checkbox name=confirm> confirm</label>
<input class=danger type=submit value="Power off (then unplug)"></form>
EOF
page_end
