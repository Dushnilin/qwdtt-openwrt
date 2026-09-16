#!/bin/sh

set -eu

command -v uci >/dev/null 2>&1 || {
	echo "This installer must run on OpenWrt."
	exit 1
}

# Auto-install or verify dependencies (ip-full, kmod-tun, ca-bundle)
ensure_deps() {
	missing_deps=""
	if ! ip -Version 2>&1 | grep -q '^ip utility'; then
		missing_deps="ip-full"
	fi
	if [ ! -c /dev/net/tun ]; then
		modprobe tun 2>/dev/null || true
		if [ ! -c /dev/net/tun ]; then
			missing_deps="$missing_deps kmod-tun"
		fi
	fi
	if [ ! -f /etc/ssl/certs/ca-certificates.crt ] && [ ! -d /etc/ssl/certs ]; then
		missing_deps="$missing_deps ca-bundle"
	fi

	if [ -n "$missing_deps" ]; then
		echo "Installing missing dependencies:$missing_deps..."
		if command -v apk >/dev/null 2>&1; then
			apk update && apk add $missing_deps || {
				echo "Failed to auto-install dependencies. Please run: apk update && apk add $missing_deps"
				exit 1
			}
		elif command -v opkg >/dev/null 2>&1; then
			opkg update && opkg install $missing_deps || {
				echo "Failed to auto-install dependencies. Please run: opkg update && opkg install $missing_deps"
				exit 1
			}
		else
			echo "Please install missing dependencies manually: $missing_deps"
			exit 1
		fi
	fi

	[ -c /dev/net/tun ] || modprobe tun 2>/dev/null || true
	[ -c /dev/net/tun ] || {
		echo "Missing /dev/net/tun. Install kmod-tun and reboot the router."
		exit 1
	}
}

detect_arch() {
	raw_arch=""
	if command -v apk >/dev/null 2>&1; then
		raw_arch="$(apk --print-arch 2>/dev/null || true)"
	elif command -v opkg >/dev/null 2>&1; then
		raw_arch="$(opkg print-architecture 2>/dev/null | awk 'NR>1 {print $2}' | tail -n 1 || true)"
	fi
	[ -n "$raw_arch" ] || raw_arch="$(uname -m 2>/dev/null || true)"

	case "$raw_arch" in
		x86_64|amd64)
			echo "x86_64"
			;;
		i386|i486|i586|i686|x86)
			echo "i386"
			;;
		aarch64*|arm64*)
			echo "aarch64"
			;;
		armv7*|arm_cortex-a7*|arm_cortex-a9*|arm_cortex-a15*)
			echo "armv7"
			;;
		armv6*|arm_arm1176*)
			echo "armv6"
			;;
		armv5*|arm926ej-s*)
			echo "armv5"
			;;
		mipsel*|mipsle*)
			echo "mipsel"
			;;
		mips64el*|mips64le*)
			echo "mips64el"
			;;
		mips64*)
			echo "mips64"
			;;
		mips*)
			echo "mips"
			;;
		riscv64*)
			echo "riscv64"
			;;
		*)
			echo "$raw_arch"
			;;
	esac
}

archive_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
temp_dir=""

# If qwdtt-client is not present next to install.sh, download it automatically
if [ ! -f "$archive_dir/qwdtt-client" ]; then
	echo "qwdtt-client binary not found locally in $archive_dir. Detecting router architecture..."
	ARCH="$(detect_arch)"
	echo "Detected architecture: $ARCH"
	temp_dir="$(mktemp -d /tmp/qwdtt-install-XXXXXX)"
	trap 'rm -rf "$temp_dir"' EXIT INT TERM

	TAR_URL="https://github.com/Dushnilin/qwdtt-openwrt/releases/latest/download/qwdtt-openwrt-${ARCH}.tar.gz"
	echo "Downloading $TAR_URL ..."
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$TAR_URL" -o "$temp_dir/archive.tar.gz"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$temp_dir/archive.tar.gz" "$TAR_URL"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -qO "$temp_dir/archive.tar.gz" "$TAR_URL"
	else
		echo "Neither curl, wget, nor uclient-fetch found. Please install curl or wget."
		exit 1
	fi

	tar -xzf "$temp_dir/archive.tar.gz" -C "$temp_dir"
	archive_dir="$temp_dir"
fi

ensure_deps

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

if [ -f "$archive_dir/files/etc/uci-defaults/99-qwdtt" ]; then
	sh "$archive_dir/files/etc/uci-defaults/99-qwdtt"
fi
/etc/init.d/qwdtt enable

echo "============================================================"
echo "qWDTT installed successfully!"
echo "Edit /etc/qwdtt/config.json and enable it with:"
echo "uci set qwdtt.main.enabled=1; uci commit qwdtt; /etc/init.d/qwdtt start"
echo "============================================================"
