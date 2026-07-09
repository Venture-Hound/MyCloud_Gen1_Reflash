#!/bin/bash
cd "$(dirname "$0")" && . ./lib.sh
read_post

msg=""
if [ "${REQUEST_METHOD:-GET}" = POST ]; then
	case "$(getv action)" in
	add)
		name=$(getv name); pass=$(getv pass)
		ws=noshare; [ "$(getv withshare)" = on ] && ws=share
		out=$(printf '%s\n' "$pass" | $SUDO $OPBIN user-add "$name" "$ws" 2>&1) ;;
	pass)
		name=$(getv name); pass=$(getv pass)
		out=$(printf '%s\n' "$pass" | $SUDO $OPBIN user-pass "$name" 2>&1) ;;
	admon)
		out=$($SUDO $OPBIN user-admin "$(getv name)" on 2>&1) ;;
	admoff)
		out=$($SUDO $OPBIN user-admin "$(getv name)" off 2>&1) ;;
	del)
		name=$(getv name)
		if [ "$(getv confirm)" = on ]; then
			out=$($SUDO $OPBIN user-del "$name" 2>&1)
		else
			out="ERR: tick the confirm box to delete"
		fi ;;
	*)	out="ERR: bad action" ;;
	esac
	msg=$(printf '%s' "$out" | esc)
fi

page_top "Users"
[ -n "$msg" ] && echo "<p><b>$msg</b></p>"

echo "<h2>SMB users</h2>"
echo "<table><tr><th>User</th><th>Admin</th><th>Set new password</th><th>Remove</th></tr>"
$SUDO $OPBIN user-list 2>/dev/null | while IFS=$'\t' read -r u adm; do
	echo "<tr><td><b>$u</b></td>"
	if [ "$u" = alpha ]; then
		echo "<td class=ok>yes (always)</td>"
	elif [ "$adm" = admin ]; then
		echo "<td><span class=ok>yes</span> <form class=inline method=post><input type=hidden name=action value=admoff><input type=hidden name=name value=$u><input type=submit value=Revoke></form></td>"
	else
		echo "<td>&mdash; <form class=inline method=post><input type=hidden name=action value=admon><input type=hidden name=name value=$u><input type=submit value='Make admin'></form></td>"
	fi
	echo "<td><form class=inline method=post><input type=hidden name=action value=pass><input type=hidden name=name value=$u><input name=pass type=password size=10> <input type=submit value=Set></form></td>"
	if [ "$u" = alpha ]; then
		echo "<td><small>(protected)</small></td>"
	else
		echo "<td><form class=inline method=post><input type=hidden name=action value=del><input type=hidden name=name value=$u><label><input type=checkbox name=confirm> confirm</label> <input class=danger type=submit value=Delete></form></td>"
	fi
	echo "</tr>"
done
echo "</table>"

cat <<'EOF'
<h2>Add user</h2>
<form method=post>
<input type=hidden name=action value=add>
Name: <input name=name pattern="[a-z][a-z0-9]{1,15}" title="lowercase letters+digits" required>
Password: <input name=pass type=password> <small>(blank = no password asked)</small>
<label><input type=checkbox name=withshare checked> create private share</label>
<input type=submit value=Add>
</form>
<p><small>Admins can open every share. Deleting a user keeps their files
under /srv/nas (only access is removed). Setting an empty password in
the password box removes the password. Passwords here are SMB
passwords — what Windows asks for.</small></p>
EOF
page_end
