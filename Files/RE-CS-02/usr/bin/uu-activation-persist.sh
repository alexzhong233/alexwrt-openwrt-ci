#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 持久化 uuplugin 的注册记录，修掉"重启后永远显示正在注册"。
#
# 上游把激活记录写在 /var/tmp/uu/activate_status，而 OpenWrt 的 /var 是
# tmpfs，重启就清空。luci-app-uugamebooster 的状态页拿这个文件判断 phase：
#
#   running   uu-detect 找到自己的 uuplugin 进程
#   cloud     netstat 里有一条到网易控制服务器的 ESTABLISHED
#   activated /tmp/uu/activate_status 非空          <-- 只有这一项在 tmpfs
#   三者齐了才 ready，缺 activated 就是"正在注册"
#
# 注册这件事本身发生在网易云端，重启后插件不会把记录重新写一遍（服务端认为
# 设备已注册，不再下发），于是这个文件永久缺失：UI 卡在"正在注册"，手机 App
# 却能正常绑定和加速。这个脚本把记录落到 /etc/uu 并在开机时放回去。
#
# 注意：它是 UI 状态的修复，不参与加速。解绑设备或换账号后，旧记录会让页面
# 误报 ready（实际绑定会失败），此时删掉 /etc/uu/activate_status 即可。
#
# 用法：
#   uu-activation-persist.sh restore   一次性恢复（开机用）
#   uu-activation-persist.sh save      一次性保存
#   uu-activation-persist.sh status    打印两份记录是否存在
#   uu-activation-persist.sh watch     常驻，每 INTERVAL 秒同步一次

set -u

PERSIST_DIR="${PERSIST_DIR:-/etc/uu}"
PERSIST="$PERSIST_DIR/activate_status"
INTERVAL="${INTERVAL:-30}"
TAG="uu-activation-persist"

# uu-detect 读 /tmp/uu/activate_status，而 init 脚本的 RUN_DIR 是 /var/tmp/uu。
# OpenWrt 上两者通常是同一目录，但不做假设：两个都写一遍，幂等且开销可忽略。
LIVE_DIRS="/var/tmp/uu /tmp/uu"

log() {
	logger -t "$TAG" "$*" 2>/dev/null || printf '%s: %s\n' "$TAG" "$*" >&2
}

restore() {
	local d

	[ -s "$PERSIST" ] || return 0

	for d in $LIVE_DIRS; do
		[ -d "$d" ] || mkdir -p "$d" 2>/dev/null
		# 插件已经自己写过就不要覆盖：那份一定比备份新。
		[ -s "$d/activate_status" ] && continue
		cp -f "$PERSIST" "$d/activate_status" 2>/dev/null &&
			log "已恢复注册记录：$PERSIST -> $d/activate_status"
	done
}

save() {
	local src=""

	if [ -s /var/tmp/uu/activate_status ]; then
		src=/var/tmp/uu/activate_status
	elif [ -s /tmp/uu/activate_status ]; then
		src=/tmp/uu/activate_status
	fi

	[ -n "$src" ] || return 1
	# 没变就不动，避免每分钟重写 flash。
	[ "$src" -nt "$PERSIST" ] || return 1

	mkdir -p "$PERSIST_DIR" 2>/dev/null
	# 先写临时文件再 mv：断电时不会留下半截记录。
	cp -f "$src" "$PERSIST.tmp" 2>/dev/null &&
		mv -f "$PERSIST.tmp" "$PERSIST" 2>/dev/null || {
		rm -f "$PERSIST.tmp" 2>/dev/null
		return 1
	}

	log "已保存注册记录：$src -> $PERSIST"
	return 0
}

show_status() {
	local d

	printf 'persisted=%s\n' "$([ -s "$PERSIST" ] && echo present || echo missing)"
	for d in $LIVE_DIRS; do
		printf 'live:%s=%s\n' "$d" \
			"$([ -s "$d/activate_status" ] && echo present || echo missing)"
	done
	printf 'phase=%s\n' "$(phase)"
}

# 与上游 controller 的判定保持同一口径，方便一条命令回答"到底 ready 没有"。
phase() {
	local det cloud activated running

	det=$("${DETECT:-/usr/libexec/uuplugin/uu-detect}" 2>/dev/null)
	running=$(printf '%s\n' "$det" | sed -n 's/^ours=//p')
	cloud=$(printf '%s\n' "$det" | sed -n 's/^cloud=//p')
	activated=$(printf '%s\n' "$det" | sed -n 's/^activated=//p')

	[ -n "$running" ] || {
		echo stopped
		return
	}
	[ -n "$cloud" ] || {
		echo starting
		return
	}
	[ -n "$activated" ] || {
		echo registering
		return
	}
	echo ready
}

case "${1:-watch}" in
restore)
	restore
	;;
save)
	save
	;;
status)
	show_status
	;;
watch)
	restore
	while :; do
		save
		sleep "$INTERVAL"
	done
	;;
*)
	echo "用法：$0 [restore|save|status|watch]" >&2
	exit 2
	;;
esac
