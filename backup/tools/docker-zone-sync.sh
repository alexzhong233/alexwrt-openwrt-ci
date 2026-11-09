#!/bin/sh
# docker-zone-sync — 让 fw4 的 docker 区自动跟上 Docker / 1Panel 新建的网桥。
#
# 问题：OpenWrt 的 fw4 按「入接口」分派 forward 链，而一个包最终能不能出去，
# 还要求出接口属于某个已知的 zone；否则即使 DNAT 已经把包改到容器的地址，
# 仍然会在 forward_lan 里被 handle_reject 丢掉。表现就是：路由器上能访问容器，
# 局域网里的电脑一律超时。
#
# 1Panel 建网络时不会去改 /etc/config/network，所以 zone 里
# network='docker' 这种绑定只覆盖 docker0；它之后建的 br-<网络ID> 全部不可达。
#
# 做法：把每个 docker bridge 网络的实际网桥名作为额外 device 挂到 docker 区
# （device 与 network 是两条独立通道，可以并存），并确保存在 lan -> docker 的
# forwarding。全程幂等：没有变化就不 commit、不 reload。
#
# 用法：
#   docker-zone-sync.sh               # 应用
#   docker-zone-sync.sh --dry-run     # 只打印会做什么
#   ZONE_NAME=docker docker-zone-sync.sh
#
# 建议挂在开机后执行（docker 起来之后）。它不做任何 nat/masquerade 的事，
# 容器访问外网由 docker 自己的 iptables 规则负责，与本脚本无关。

set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

ZONE_NAME=${ZONE_NAME:-docker}
CHANGED=0

log() {
	logger -t docker-zone-sync "$*" 2>/dev/null
	echo "$*"
}

command -v docker >/dev/null 2>&1 || { echo "docker 未安装"; exit 0; }
docker info >/dev/null 2>&1 || { echo "docker 守护进程未运行"; exit 0; }

# ---------------------------------------------------------------- zone lookup
# 命名 section（firewall.docker）优先；否则按索引遍历，匿名区也能找到。
find_zone() {
	if [ "$(uci -q get "firewall.$ZONE_NAME.name")" = "$ZONE_NAME" ]; then
		echo "firewall.$ZONE_NAME"
		return 0
	fi

	i=0
	while :; do
		name=$(uci -q get "firewall.@zone[$i].name") || return 1
		if [ "$name" = "$ZONE_NAME" ]; then
			echo "firewall.@zone[$i]"
			return 0
		fi
		i=$((i + 1))
	done
}

ZONE=$(find_zone) || {
	log "找不到名为 $ZONE_NAME 的 firewall 区；先在 LuCI 或 uci 里建一个再跑本脚本"
	exit 1
}
log "zone = $ZONE"

fwd=$(uci -q get "$ZONE.forward")
[ "$fwd" = "ACCEPT" ] || log "注意：$ZONE 的 forward='${fwd:-未设置}'，区内的转发可能仍被拒"

# ------------------------------------------------------------ device handling
has_device() {
	uci -q show "$ZONE.device" 2>/dev/null | grep -Fqx "$ZONE.device='$1'"
}

add_device() {
	if [ "$DRY" = "1" ]; then
		log "would add device $1"
		return 0
	fi
	uci add_list "$ZONE.device=$1" || return 1
	CHANGED=1
	log "added device $1"
}

del_device() {
	if [ "$DRY" = "1" ]; then
		log "would drop stale device $1"
		return 0
	fi
	uci del_list "$ZONE.device=$1" 2>/dev/null || return 0
	CHANGED=1
	log "dropped stale device $1"
}

# ------------------------------------------------------- forwarding lan->zone
has_forwarding() {
	i=0
	while :; do
		src=$(uci -q get "firewall.@forwarding[$i].src") || return 1
		dest=$(uci -q get "firewall.@forwarding[$i].dest")
		if [ "$src" = "lan" ] && [ "$dest" = "$ZONE_NAME" ]; then
			return 0
		fi
		i=$((i + 1))
	done
}

if has_forwarding; then
	log "lan -> $ZONE_NAME forwarding 已存在"
elif [ "$DRY" = "1" ]; then
	log "would add forwarding lan -> $ZONE_NAME"
else
	sec=$(uci add firewall forwarding) || exit 1
	uci set "$sec.src=lan"
	uci set "$sec.dest=$ZONE_NAME"
	CHANGED=1
	log "added forwarding lan -> $ZONE_NAME ($sec)"
fi

# ------------------------------------------------------------ bridge networks
# 一次列全，再逐条处理：while read 放在管道里会进子 shell，CHANGED 传不出来。
LIST=$(mktemp) || exit 1
docker network ls --filter driver=bridge --format '{{.ID}} {{.Name}}' > "$LIST" 2>/dev/null

while read -r id name; do
	[ -n "${id:-}" ] || continue

	# 默认 bridge 的接口叫 docker0，由 zone 的 network='docker' 覆盖，跳过。
	[ "$name" = "bridge" ] && continue

	# 网络可以在 options 里自定义网桥名，先看这个，比猜 br-<id> 可靠。
	iface=$(docker network inspect -f '{{index .Options "com.docker.network.bridge.name"}}' "$id" 2>/dev/null)
	case "$iface" in
		"" | "<no value>") iface="br-$(printf %s "$id" | cut -c1-12)" ;;
	esac

	if ! ip link show "$iface" >/dev/null 2>&1; then
		log "skip $name: 网桥 $iface 不存在"
		continue
	fi

	if has_device "$iface"; then
		log "ok   $name -> $iface (已在 zone 里)"
	else
		log "add  $name -> $iface"
		add_device "$iface"
	fi
done < "$LIST"
rm -f "$LIST"

# 清掉已经删掉的网络留下的 br-xxxxxxxxxxxx（十六进制 12 位），避免 zone 越攒越长。
# docker0 以及自定义网桥名不匹配这个形状，不会被误删。
STALE=$(mktemp) || exit 1
uci -q show "$ZONE.device" 2>/dev/null |
	sed -n "s/^.*='\(br-[0-9a-f]\{12\}\)'$/\1/p" > "$STALE"
while read -r dev; do
	[ -n "${dev:-}" ] || continue
	ip link show "$dev" >/dev/null 2>&1 || del_device "$dev"
done < "$STALE"
rm -f "$STALE"

# -------------------------------------------------------------------- commit
if [ "$CHANGED" = "1" ]; then
	if [ "$DRY" = "1" ]; then
		log "dry-run: 不写 uci、不 reload"
	else
		uci commit firewall || exit 1
		# 用 fw4 reload，不要用 /etc/init.d/firewall restart：
		# 后者会重刷整套规则，冲掉 NetBird 在 fw4 里补的 wt0 转发。
		fw4 reload
		log "已提交并 reload"
	fi
else
	log "无变化，跳过 commit/reload"
fi

# -------------------------------------------------------------------- verify
if [ "$DRY" = "0" ]; then
	echo "--- 生效检查 ---"
	nft list chain inet fw4 forward 2>/dev/null | grep "$ZONE_NAME" | sed 's/^[ \t]*/  /'
fi

exit 0
