#!/bin/bash
# SPDX-License-Identifier: MIT
#
# 把 workbuddy2api 和它的 LuCI 界面装进构建树。
#
# 上游的 OpenWrt 包只带骨架（Makefile + init.d + uci 配置 + 预热脚本），
# 应用本体 wb_*.py 和 dashboard.html 留在仓库根目录，靠 wrt/openwrt/build-apk.sh
# 在打包前同步进 files/usr/lib/workbuddy2api/。我们不走它的打包脚本，
# 所以这一步得自己补，否则 Makefile 里的 $(error 找不到应用源码) 会让 defconfig 直接失败。
#
# LuCI 界面是本仓库自己写的（LuCI/luci-app-workbuddy2api），一并拷进去。
# 目录故意不叫 Package：Windows 上 Package 和构建树里的 package/ 是同一个目录，
# 本地调试时会互相覆盖。

set -e

PKG_NAME="workbuddy2api"
LUCI_PKG="luci-app-workbuddy2api"
REPO_URL="https://github.com/ardeyouxipianyi/workbuddy2api-hub"
REPO_BRANCH="main"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
LUCI_SRC="$REPO_ROOT/LuCI/$LUCI_PKG"
PKG_DIR="$(pwd)/package/$PKG_NAME"

warn() { echo "::warning::$*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---- 1. 取上游 ------------------------------------------------------------
if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP/repo" >/dev/null 2>&1; then
	warn "拉取 $REPO_URL 失败，workbuddy2api 不进入本次构建"
	exit 0
fi

if [ ! -d "$TMP/repo/wrt/openwrt/$PKG_NAME" ]; then
	warn "上游已无 wrt/openwrt/$PKG_NAME，workbuddy2api 不进入本次构建"
	exit 0
fi

# ---- 2. 包骨架 ------------------------------------------------------------
rm -rf "$PKG_DIR"
cp -R "$TMP/repo/wrt/openwrt/$PKG_NAME" "$PKG_DIR"

# ---- 3. 补应用源码 --------------------------------------------------------
APP_DST="$PKG_DIR/files/usr/lib/$PKG_NAME"
mkdir -p "$APP_DST"

if ! cp "$TMP/repo"/wb_*.py "$APP_DST"/ 2>/dev/null; then
	warn "上游根目录没有 wb_*.py，workbuddy2api 不进入本次构建"
	rm -rf "$PKG_DIR"
	exit 0
fi

if [ ! -f "$APP_DST/wb_proxy.py" ]; then
	warn "缺少 wb_proxy.py 入口，workbuddy2api 不进入本次构建"
	rm -rf "$PKG_DIR"
	exit 0
fi

if [ -f "$TMP/repo/dashboard.html" ]; then
	cp "$TMP/repo/dashboard.html" "$APP_DST/"
else
	warn "缺少 dashboard.html，网关能跑但管理面板打不开"
fi

# 上游 release 流程会比对这两处版本号，对不上就拒绝出包。这里只提示不阻断，
# 因为我们跟上的是分支最新提交，版本号由上游自己保证。
MAKEFILE_VER=$(sed -n 's/^PKG_VERSION:=//p' "$PKG_DIR/Makefile" | head -n1)
APP_VER=$(sed -n 's/.*server_version = "wb-proxy\/\([0-9.]*\)".*/\1/p' "$APP_DST/wb_proxy.py" | head -n1)
if [ -n "$MAKEFILE_VER" ] && [ -n "$APP_VER" ] && [ "$MAKEFILE_VER" != "$APP_VER" ]; then
	warn "版本号不一致：Makefile=$MAKEFILE_VER，wb_proxy.py=$APP_VER（上游可能正处于发版间隙）"
fi

echo "workbuddy2api 就绪：Makefile 版本 ${MAKEFILE_VER:-未知}，应用版本 ${APP_VER:-未知}"
echo "  应用文件：$(find "$APP_DST" -maxdepth 1 -type f | wc -l) 个"

# ---- 3.5 首次启动初始化 ------------------------------------------------
# 上游把这些放在 postinst 里，但编进固件时 postinst 会被 IPKG_INSTROOT 守卫跳过，
# 设备上又不会重装包，所以必须靠 uci-defaults 在首次启动补一次。
UCI_DEFAULTS_SRC="$SCRIPT_DIR/uci-defaults/99-workbuddy2api"
if [ -f "$UCI_DEFAULTS_SRC" ]; then
	mkdir -p "$PKG_DIR/files/etc/uci-defaults"
	cp "$UCI_DEFAULTS_SRC" "$PKG_DIR/files/etc/uci-defaults/99-workbuddy2api"
	chmod 755 "$PKG_DIR/files/etc/uci-defaults/99-workbuddy2api"
	echo "首次启动初始化已挂到 uci-defaults"
else
	warn "缺少 $UCI_DEFAULTS_SRC，数据目录和 sysupgrade 保留需要手动处理"
fi

# ---- 4. LuCI 界面 --------------------------------------------------------
if [ -d "$LUCI_SRC" ]; then
	rm -rf "./package/$LUCI_PKG"
	cp -R "$LUCI_SRC" ./package/
	echo "$LUCI_PKG 就绪：$(find "./package/$LUCI_PKG/luasrc" -type f | wc -l) 个 Lua 文件"
else
	warn "本地 $LUCI_SRC 不存在，网关会装上但没有 LuCI 界面"
fi
