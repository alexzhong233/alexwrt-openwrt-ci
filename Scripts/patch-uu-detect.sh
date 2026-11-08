#!/bin/bash
# SPDX-License-Identifier: MIT
#
# 修 luci-app-uugamebooster「重启后永久停在正在注册」。
#
# 状态页的 ready 要三个条件同时成立（luasrc/controller/uuplugin.lua）：
#   running    进程在
#   cloud      有一条到网易控制服务器的 ESTABLISHED
#   activated  /tmp/uu/activate_status 非空
#
# 前两个重启后都能自行恢复，第三个不行：文件在 tmpfs，重启即清空；而注册事实
# 存在网易云端，服务端认为设备已注册就不会再让插件重写这个文件。于是进程正常、
# 控制链路正常、手机 App 能绑定也能加速，UI 却永远显示「正在注册」。
#
# 修在插件自己的探测脚本里：记录缺失但控制链路已建立时，把 activated 兜底成
# connected。运行时不多任何进程、不多任何文件，也不动 /etc 下的持久分区。
#
# 放在这里而不是 Files/ 覆盖整个 uu-detect：上游仍在改这个脚本，只在源码里插三行，
# 其余改动可以正常跟上来。

set -e

PKG_NAME="luci-app-uugamebooster"
PKG_DIR="$(pwd)/package/$PKG_NAME"
TARGET="$PKG_DIR/root/usr/libexec/uuplugin/uu-detect"
MARKER='activated=connected'

warn() { echo "::warning::$*"; }

if [ ! -d "$PKG_DIR" ]; then
	echo "$PKG_NAME 未启用，跳过 uu-detect 补丁"
	exit 0
fi

if [ ! -f "$TARGET" ]; then
	warn "找不到 $TARGET，uu-detect 补丁未应用"
	exit 0
fi

if grep -q "$MARKER" "$TARGET"; then
	echo "uu-detect 已有注册兜底，跳过"
	exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# 锚定读取 activate_status 的那一条。awk 的字符串里不做变量插值，
# 打印出来的 $activated / $cloud 是字面量，正好是补丁要写进去的内容。
awk '
	{ print }
	/^[[:space:]]*activated=\$\(head -n1 \/tmp\/uu\/activate_status/ {
		print "\t# 这个文件在 tmpfs 上，重启必丢；云端认为已注册就不会重写它。"
		print "\t# 控制链路已建立时把注册状态兜底，否则页面会永久停在 registering。"
		print "\t[ -z \"$activated\" ] && [ -n \"$cloud\" ] && activated=connected"
	}
' "$TARGET" >"$TMP"

if ! grep -q "$MARKER" "$TMP"; then
	warn "uu-detect 里没找到 activate_status 的读取行，补丁未生效（上游可能改过这段）"
	exit 0
fi

# cat 回去而不是 mv：保留原文件的权限位。
cat "$TMP" >"$TARGET"

if ! sh -n "$TARGET" 2>/dev/null; then
	warn "打完补丁的 uu-detect 语法检查失败，请检查上游改动"
	exit 0
fi

echo "uu-detect 补丁已应用：注册记录缺失时用控制链路兜底"
