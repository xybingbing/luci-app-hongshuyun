#!/bin/sh

CFG="hongshuyun"
SECTION="subscription"
CRONTAB="/etc/crontabs/root"
CMD="/etc/hongshuyun/scripts/update_crond.sh"

enabled="$(uci -q get ${CFG}.${SECTION}.auto_update)"
hour="$(uci -q get ${CFG}.${SECTION}.auto_update_time)"

[ -n "$hour" ] || hour="2"

mkdir -p /etc/crontabs >/dev/null 2>&1
touch "$CRONTAB" >/dev/null 2>&1

grep -vF "$CMD" "$CRONTAB" > "${CRONTAB}.tmp" 2>/dev/null || true

if [ "$enabled" = "1" ]; then
	echo "0 ${hour} * * * ${CMD}" >> "${CRONTAB}.tmp"
fi

mv -f "${CRONTAB}.tmp" "$CRONTAB"

/etc/init.d/cron restart >/dev/null 2>&1

