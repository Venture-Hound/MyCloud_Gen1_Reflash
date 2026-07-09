# Shared helpers for CLIO NAS panel CGIs. Sourced, never served
# (blocked by url.access-deny in lighttpd.conf).
SUDO=/usr/bin/sudo
OPBIN=/usr/local/lib/nas-panel/panel-op

http_header(){ printf 'Content-Type: text/html; charset=utf-8\r\n\r\n'; }

esc(){ sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

urldecode(){ local d="${1//+/ }"; printf '%b' "${d//%/\\x}"; }

read_post(){
	POST_DATA=""
	if [ "${REQUEST_METHOD:-GET}" = POST ]; then
		POST_DATA=$(head -c "${CONTENT_LENGTH:-0}")
	fi
}

getv(){ # field name -> decoded value
	local raw
	raw=$(printf '%s' "$POST_DATA" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1)
	urldecode "$raw"
}

page_top(){ # title
	http_header
	cat <<EOF
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$1 — CLIO</title>
<style>
 body{font-family:system-ui,sans-serif;margin:1.2em;max-width:52em;background:#fff;color:#222}
 nav{margin-bottom:1em;padding-bottom:.5em;border-bottom:1px solid #ccc}
 nav a{margin-right:1.2em;text-decoration:none;font-weight:bold}
 table{border-collapse:collapse;margin:.5em 0}
 td,th{border:1px solid #bbb;padding:.3em .6em;text-align:left;vertical-align:top}
 .ok{color:#0a7a0a}.bad{color:#c00;font-weight:bold}.warn{color:#b87700}
 pre{background:#f4f4f4;padding:.6em;overflow-x:auto;font-size:.85em}
 form.inline{display:inline}
 input[type=submit].danger{color:#c00}
 small{color:#666}
</style></head><body>
<nav><a href="/">Status</a><a href="/users.cgi">Users</a><a href="/shares.cgi">Shares</a><a href="/smart.cgi">Disk</a><a href="/power.cgi">Power</a></nav>
<h1>$1</h1>
EOF
}

page_end(){ echo "</body></html>"; }
