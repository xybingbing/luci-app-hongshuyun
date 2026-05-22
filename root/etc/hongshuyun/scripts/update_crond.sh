#!/bin/sh

/etc/hongshuyun/scripts/update_subscriptions.uc
/usr/bin/ubus call luci.hongshuyun resources_update '{"type":"all"}' >/dev/null 2>&1

