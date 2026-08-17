#!/bin/sh

set -eu

archive_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

command -v uci >/dev/null 2>&1 || {
	echo "This installer must run on OpenWrt."
	exit 1
}

ip -Version 2>&1 | grep -q '^ip utility' || {
	if command -v apk >/dev/null 2>&1; then
		echo "Install dependencies: apk update && apk add ip-full kmod-tun ca-bundle"
	else
		echo "Install dependencies: opkg update && opkg install ip-full kmod-tun ca-bundle"
	fi
	exit 1
}

[ -c /dev/net/tun ] || modprobe tun 2>/dev/null || true
[ -c /dev/net/tun ] || {
	echo "Missing /dev/net/tun. Install kmod-tun and reboot the router."
	exit 1
}

mkdir -p /usr/bin /etc/init.d /etc/config /etc/qwdtt
cp "$archive_dir/qwdtt-client" /usr/bin/qwdtt-client
cp "$archive_dir/files/etc/init.d/qwdtt" /etc/init.d/qwdtt
chmod 0755 /usr/bin/qwdtt-client /etc/init.d/qwdtt

if [ ! -e /etc/config/qwdtt ]; then
	cp "$archive_dir/files/etc/config/qwdtt" /etc/config/qwdtt
	chmod 0600 /etc/config/qwdtt
fi
if [ ! -e /etc/qwdtt/config.json ]; then
	cp "$archive_dir/files/etc/qwdtt/config.json" /etc/qwdtt/config.json
	chmod 0600 /etc/qwdtt/config.json
fi

sh "$archive_dir/files/etc/uci-defaults/99-qwdtt"
/etc/init.d/qwdtt enable

echo "qWDTT installed. Edit /etc/qwdtt/config.json and enable it with:"
echo "uci set qwdtt.main.enabled=1; uci commit qwdtt; /etc/init.d/qwdtt start"
