#!/bin/bash
cd "$(dirname "$0")" && . ./lib.sh
read_post

msg=""
if [ "${REQUEST_METHOD:-GET}" = POST ]; then
	t=$(getv test)
	case "$t" in
	short|long) msg=$($SUDO $OPBIN smart-test "$t" 2>&1 | esc) ;;
	*) msg="ERR: bad test type" ;;
	esac
fi

page_top "Disk (SMART)"
[ -n "$msg" ] && echo "<pre>$msg</pre>"

cat <<'EOF'
<form class=inline method=post><input type=hidden name=test value=short>
<input type=submit value="Run short self-test (~2 min)"></form>
<form class=inline method=post><input type=hidden name=test value=long>
<input type=submit value="Run long self-test (~7 h, NAS stays usable)"></form>
<p><small>Test progress and results appear in the report below
(sections "Self-test execution status" and "Self-test log"). Refresh the
page to update.</small></p>
EOF

echo "<h2>Full SMART report</h2>"
echo "<pre>$($SUDO $OPBIN smart-full 2>&1 | esc)</pre>"
page_end
