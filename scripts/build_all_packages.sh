#!/bin/bash
set -euo pipefail

TAG="${1:-v1.0.3}"
VER="${2:-1.0.3}"
VER="${VER#v}"

DIST_DIR="$(pwd)/dist"
mkdir -p "$DIST_DIR"

APK_BIN="${APK_BIN:-apk}"
IPKG_BUILD_BIN="${IPKG_BUILD_BIN:-ipkg-build}"

TARGETS=(
  "x86_64:x86_64:x86_64"
  "i386:i386_pentium4 i386:x86 i386"
  "aarch64:aarch64_generic aarch64_cortex-a53 aarch64:aarch64 aarch64_generic aarch64_cortex-a53"
  "armv7:arm_cortex-a7_neon-vfpv4 arm_cortex-a9 arm_cortex-a15_neon-vfpv4 armv7:armv7"
  "armv6:arm_arm1176jzf-s_vfp armv6:armhf armv6"
  "armv5:arm_arm926ej-s armv5:armel armv5"
  "mipsel:mipsel_24kc mipsel:mipsel"
  "mipsel_hardfloat:mipsel_24kf mipsel_hardfloat:mipselhf mipsel_hardfloat"
  "mips:mips_24kc mips:mips"
  "mips_hardfloat:mips_24kf mips_hardfloat:mipshf mips_hardfloat"
  "mips64:mips64:mips64"
  "mips64el:mips64el:mips64el"
  "riscv64:riscv64_generic riscv64:riscv64"
)

for target_info in "${TARGETS[@]}"; do
  IFS=":" read -r name ipk_arches apk_arches <<< "$target_info"
  client_bin="bin/qwdtt-client-${name}"
  if [ ! -f "$client_bin" ]; then
    echo "Warning: binary $client_bin not found, skipping $name" >&2
    continue
  fi

  echo "=== Packaging $name ==="

  # 1. Raw tar.gz archive
  RAW_DIR="$(mktemp -d /tmp/qwdtt-raw-XXXXXX)"
  cp "$client_bin" "$RAW_DIR/qwdtt-client"
  cp install.sh README.md LICENSE "$RAW_DIR/"
  cp -r files "$RAW_DIR/"
  tar -czf "$DIST_DIR/qwdtt-openwrt-${name}.tar.gz" -C "$RAW_DIR" qwdtt-client install.sh files README.md LICENSE
  rm -rf "$RAW_DIR"

  # 2. Package tree
  ROOT_DIR="$(mktemp -d /tmp/qwdtt-root-XXXXXX)"
  SCRIPTS_DIR="$(mktemp -d /tmp/qwdtt-scripts-XXXXXX)"

  mkdir -p "$ROOT_DIR/usr/bin" "$ROOT_DIR/etc/init.d" "$ROOT_DIR/etc/config" "$ROOT_DIR/etc/qwdtt" "$ROOT_DIR/etc/uci-defaults"

  cp "$client_bin" "$ROOT_DIR/usr/bin/qwdtt-client"
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

  # IPK packaging
  for arch in $ipk_arches; do
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
    sudo "$IPKG_BUILD_BIN" "$IPK_DIR" "$DIST_DIR" >/dev/null
    sudo rm -rf "$IPK_DIR"

    if [ -f "$DIST_DIR/wdtt_${VER}-1_${arch}.ipk" ]; then
      sudo cp -p "$DIST_DIR/wdtt_${VER}-1_${arch}.ipk" "$DIST_DIR/wdtt_${VER}_${arch}.ipk"
      sudo cp -p "$DIST_DIR/wdtt_${VER}-1_${arch}.ipk" "$DIST_DIR/wdtt_${VER}_openwrt_${arch}.ipk"
    fi
  done

  # APK packaging
  for arch in $apk_arches; do
    sudo chown -R 0:0 "$ROOT_DIR" "$SCRIPTS_DIR"
    sudo "$APK_BIN" mkpkg \
      --files "$ROOT_DIR" \
      --output "$DIST_DIR/wdtt_${VER}-1_${arch}.apk" \
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
    sudo cp -p "$DIST_DIR/wdtt_${VER}-1_${arch}.apk" "$DIST_DIR/wdtt_${VER}_${arch}.apk"
    sudo cp -p "$DIST_DIR/wdtt_${VER}-1_${arch}.apk" "$DIST_DIR/wdtt_${VER}_openwrt_${arch}.apk"
  done

  sudo rm -rf "$ROOT_DIR" "$SCRIPTS_DIR"
done

sudo chown -R "$(id -u):$(id -g)" "$DIST_DIR"
cd "$DIST_DIR"
sha256sum * > sha256sums.txt
ls -lh