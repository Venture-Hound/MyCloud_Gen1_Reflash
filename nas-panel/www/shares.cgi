#!/bin/bash
cd "$(dirname "$0")" && . ./lib.sh
read_post

PROTECTED="global public admin alpha homes printers"
is_protected(){ case " $PROTECTED " in *" $1 "*) return 0;; *) return 1;; esac; }

msg=""
if [ "${REQUEST_METHOD:-GET}" = POST ]; then
	case "$(getv action)" in
	add)
		name=$(getv name); typ=$(getv type); owner=$(getv owner)
		out=$($SUDO $OPBIN share-add "$name" "$typ" "$owner" 2>&1) ;;
	del)
		name=$(getv name)
		if [ "$(getv confirm)" = on ]; then
			out=$($SUDO $OPBIN share-del "$name" 2>&1)
		else
			out="ERR: tick the confirm box to remove"
		fi ;;
	*)	out="ERR: bad action" ;;
	esac
	msg=$(printf '%s' "$out" | esc)
fi

page_top "Shares"
[ -n "$msg" ] && echo "<p><b>$msg</b></p>"

echo "<h2>Current shares</h2>"
echo "<table><tr><th>Share</th><th>Who has access</th><th>Remove</th></tr>"
$SUDO $OPBIN share-list 2>/dev/null | while IFS=$'\t' read -r s acc; do
	echo "<tr><td><b>\\\\CLIO\\$s</b></td><td>$(printf '%s' "$acc" | esc)</td>"
	if is_protected "$s"; then
		echo "<td><small>(protected)</small></td>"
	else
		echo "<td><form class=inline method=post><input type=hidden name=action value=del><input type=hidden name=name value=$s><label><input type=checkbox name=confirm> confirm</label> <input class=danger type=submit value=Remove></form></td>"
	fi
	echo "</tr>"
done
echo "</table>"

cat <<'EOF'
<h2>Add share</h2>
<form method=post>
<input type=hidden name=action value=add>
Name: <input name=name pattern="[a-z][a-z0-9]{1,15}" title="lowercase letters+digits" required>
Type: <select name=type>
<option value=family>family (all users read/write)</option>
<option value=private>private (one owner + alpha)</option>
<option value=guest>guest (no password, e.g. media players)</option>
</select>
Owner (private only): <input name=owner size=10>
<input type=submit value=Add>
</form>
<p><small>Directory is created under /srv/nas/&lt;name&gt;. Removing a share
never deletes files — it only stops sharing them.</small></p>
EOF
page_end
