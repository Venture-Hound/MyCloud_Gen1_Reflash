#!/bin/bash
# deploy.sh — push the NAS panel to a running box and install. Run from
# your build host. Edit NASHOST below (or export it) if your box isn't
# reachable as clio.local. You'll be prompted for the sudo password on
# the box interactively — nothing here stores or automates it.
set -e
NASHOST="${NASHOST:-clio.local}"
cd "$(dirname "$0")"
ssh "alpha@$NASHOST" 'rm -rf /tmp/nas-panel && mkdir -p /tmp/nas-panel/www'
scp -q panel-op led-status lighttpd.conf sudoers-nas-panel \
	init-nas-led cron-nas-led remote-install.sh \
	recycle-purge smart-monthly cron-nas-maint "alpha@$NASHOST:/tmp/nas-panel/"
scp -q www/lib.sh www/*.cgi "alpha@$NASHOST:/tmp/nas-panel/www/"
ssh -t "alpha@$NASHOST" 'sudo bash /tmp/nas-panel/remote-install.sh'
