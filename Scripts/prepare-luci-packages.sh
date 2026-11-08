#!/bin/bash
# SPDX-License-Identifier: MIT
#
# 把 LuCI/ 下自建的界面包拷进构建树。
#
# LuCI/ 里每个子目录是一个独立软件包（JS 版 LuCI：htdocs/luci-static/resources/view/
# + root/usr/share/luci/menu.d + root/usr/share/rpcd/acl.d），全部拷进 package/。
# 以后加页面只要在 LuCI/ 下加目录，不用改这个脚本。
#
# 为什么这一步不能省：这些包不在 Scripts/Packages.sh 的 UPDATE_PACKAGE 列表里，
# Verify Package Selection 只会把它们当成「平台不适用」发一条 warning。万一漏拷，
# 构建照常成功、固件里却少了页面，属于最容易被忽略的静默失败。
#
# 目录故意不叫 Package：Windows 上 Package 和构建树里的 package/ 是同一个目录，
# 本地调试时会互相覆盖。

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

if [ ! -d "$REPO_ROOT/LuCI" ]; then
	echo "::warning::本地 LuCI 目录不存在，自建页面不会进固件"
	exit 0
fi

for LUCI_SRC in "$REPO_ROOT"/LuCI/*/; do
	[ -d "$LUCI_SRC" ] || continue
	LUCI_PKG=$(basename "$LUCI_SRC")
	rm -rf "./package/$LUCI_PKG"
	cp -R "$LUCI_SRC" ./package/
	echo "$LUCI_PKG 就绪：$(find "./package/$LUCI_PKG" -type f \( -name '*.js' -o -name '*.json' \) | wc -l) 个界面文件"
done
