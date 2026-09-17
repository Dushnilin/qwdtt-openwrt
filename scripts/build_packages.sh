#!/bin/bash
set -euo pipefail

NAME="${1:-x86_64}"
IPK_ARCHES="${2:-x86_64}"
APK_ARCHES="${3:-x86_64}"
TAG="${4:-v1.0.3}"
VER="${5:-1.0.3}"

# Clean version without leading 'v'
VER="${VER#v}"

mkdir -p dist

# 1. Raw tar.gz archive for manual installs / legacy scripts
tar -czf "dist/qwdtt-openwrt-${NAME}.tar.gz" qwdtt-client install.sh files README.md LICENSE

# 2. Prepare root filesystem tree for packages
ROOT_DIR="$(mktemp -d /tmp/qwdtt-pkg-root-XXXXXX)"
SCRIPTS_DIR="$(mktemp -d /tmp/qwdtt-pkg-scripts-XXXXXX)"

trap 'rm -rf "$ROOT_DIR" "$SCRIPTS_DIR"' EXIT

mkdir -p "$ROOT_DIR/usr/bin" "$ROOT_DIR/etc/init.d" "$ROOT_DIR/etc/config" "$ROOT_DIR/etc/qwdtt" "$ROOT_DIR/etc/uci-defaults"

cp qwdtt-client "$ROOT_DIR/usr/bin/qwdtt-client"
ln -sf qwdtt-client "$ROOT_DIR/usr/bin/qwdtt"
ln -sf qwdtt-client "$ROOT_DIR/usr/bin/wdtt"
chmod 0755 "$ROOT_DIR/usr/bin/qwdtt-client"

cp files/etc/init.d/qwdtt "$ROOT_DIR/etc/init.d/qwdtt"
chmod 0755 "$ROOT_DIR/etc/init.d/qwdtt"

cp files/etc/config/qwdtt "$ROOT_DIR/etc/config/qwdtt"
chmod 0600 "$ROOT_DIR/etc/config/qwdtt"

cp files/etc/qwdtt/config.json "$ROOT_DIR/etc/qwdtt/config.json"
chmod 0600 "$ROOT_DIR/etc/qwdtt/config.json"

echo "$VER" > "$ROOT_DIR/etc/qwdtt/.version"
chmod 0644 "$ROOT_DIR/etc/qwdtt/.version"

cp files/etc/uci-defaults/99-qwdtt "$ROOT_DIR/etc/uci-defaults/99-qwdtt"
chmod 0755 "$ROOT_DIR/etc/uci-defaults/99-qwdtt"

# Control scripts
cat > "$SCRIPTS_DIR/post-install.sh" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
if [ -f /etc/uci-defaults/99-qwdtt ]; then
    sh /etc/uci-defaults/99-qwdtt
fi
/etc/init.d/qwdtt enable >/dev/null 2>&1 || true
exit 0
EOF
chmod 0755 "$SCRIPTS_DIR/post-install.sh"

cat > "$SCRIPTS_DIR/pre-deinstall.sh" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/qwdtt stop >/dev/null 2>&1 || true
/etc/init.d/qwdtt disable >/dev/null 2>&1 || true
exit 0
EOF
chmod 0755 "$SCRIPTS_DIR/pre-deinstall.sh"

# Build IPK packages
for arch in $IPK_ARCHES; do
  IPK_DIR="$(mktemp -d /tmp/qwdtt-ipk-XXXXXX)"
  cp -a "$ROOT_DIR/." "$IPK_DIR/"
  mkdir -p "$IPK_DIR/CONTROL"
  cp "$SCRIPTS_DIR/post-install.sh" "$IPK_DIR/CONTROL/postinst"
  cp "$SCRIPTS_DIR/pre-deinstall.sh" "$IPK_DIR/CONTROL/prerm"
  cat > "$IPK_DIR/CONTROL/conffiles" <<'EOF'
/etc/config/qwdtt
/etc/qwdtt/config.json
EOF
  cat > "$IPK_DIR/CONTROL/control" <<EOF
Package: wdtt
Version: ${VER}-1
Depends: ca-bundle, kmod-tun, ip-full
Provides: qwdtt
Section: net
Architecture: ${arch}
Maintainer: Dushnilin
Description: qWDTT client for OpenWrt
EOF
  sudo chown -R 0:0 "$IPK_DIR"
  sudo ipkg-build "$IPK_DIR" dist >/dev/null
  sudo rm -rf "$IPK_DIR"
  if [ -f "dist/wdtt_${VER}-1_${arch}.ipk" ]; then
    cp -p "dist/wdtt_${VER}-1_${arch}.ipk" "dist/wdtt_${VER}_${arch}.ipk"
    cp -p "dist/wdtt_${VER}-1_${arch}.ipk" "dist/wdtt_${VER}_openwrt_${arch}.ipk"
  fi
done

# Build APK packages
for arch in $APK_ARCHES; do
  sudo chown -R 0:0 "$ROOT_DIR" "$SCRIPTS_DIR"
  sudo apk.static mkpkg \
    --files "$ROOT_DIR" \
    --output "dist/wdtt_${VER}-1_${arch}.apk" \
    -I "name:wdtt" \
    -I "version:${VER}-r1" \
    -I "description:qWDTT client for OpenWrt" \
    -I "arch:${arch}" \
    -I "license:GPL-3.0" \
    -I "origin:wdtt" \
    -I "maintainer:Dushnilin" \
    -I "url:https://github.com/Dushnilin/qwdtt-openwrt" \
    -I "depends:ca-bundle kmod-tun ip-full" \
    -I "provides:qwdtt" \
    -s "post-install:${SCRIPTS_DIR}/post-install.sh" \
    -s "pre-deinstall:${SCRIPTS_DIR}/pre-deinstall.sh"
  cp -p "dist/wdtt_${VER}-1_${arch}.apk" "dist/wdtt_${VER}_${arch}.apk"
  cp -p "dist/wdtt_${VER}-1_${arch}.apk" "dist/wdtt_${VER}_openwrt_${arch}.apk"
done

sudo chown -R "$(id -u):$(id -g)" dist
for f in dist/*; do
  [ -f "$f" ] || continue
  sha256sum "$f" > "${f}.sha256"
done

ls -lh dist/