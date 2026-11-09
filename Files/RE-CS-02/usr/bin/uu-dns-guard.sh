#!/bin/sh
# uu-dns-guard — 收拾网易 UU 加速器对 DNS 的两处干扰。
#
# 背景（2026-11 实测，UU OEM 插件 /opt/uu-oem/uuplugin）：
#   UU 开始加速某台设备时，会动两类规则：
#
#   1) IPv4 —— nat PREROUTING 最前面插一条 DNAT，把该设备的 DNS 查询改到 8.8.8.8：
#        -A PREROUTING -s <设备IP> -i br-lan -p udp --dport 53 -j DNAT --to-destination 8.8.8.8
#      而 8.8.8.8 又被 UU 的策略路由(table 179)指进 tun163 游戏隧道，隧道只转发
#      游戏流量，DNS 查询要么被丢、要么拿到 GFW 投毒结果。
#
#   2) IPv6 —— ip6tables filter 的 INPUT/FORWARD 各插一条按 MAC 匹配的 DROP：
#        -A INPUT -i br-lan -p udp -m mac --mac-source <设备MAC> -m udp --dport 53 -j DROP
#      UU 不支持 IPv6，就把被加速设备的 IPv6 DNS 直接封死，逼它退回 IPv4。
#
#   **关键**：UU 停止加速时会清理 ip rule / tun163 / nat 规则，但
#   **不会清理 ip6tables filter 里这两条 DROP**。于是「用 UU 加速过一次」
#   就导致该设备的 IPv6 解析一直失败，直到重启。实测计数器在停止加速后
#   仍持续增长（948 → 974），可证。
#
# 本守护每 POLL 秒做两件事，幂等、只在有变化时写日志：
#   a) 把发往路由器自己的 UDP/53 RETURN 顶到 nat PREROUTING 第 1 位
#      （只拦「目的地是路由器」的查询，不影响 UU 处理其余流量）；
#   b) 删掉 ip6tables filter 里针对 UDP/53 的 DROP（INPUT 和 FORWARD）。
#
# 与 netbird-passwall-compat-watch 互不干扰：那个处理 netbird 的 mark 豁免，
# 这个处理 UU 的 DNS 干扰，触发条件完全不同，刻意分成两个脚本。

POLL="${UU_DNS_GUARD_POLL:-3}"
TAG="uu-dns-guard"

LAN_IP="$(uci -q get network.lan.ipaddr)"
[ -n "$LAN_IP" ] || LAN_IP="192.168.88.1"

RULE="-i br-lan -p udp -m udp --dport 53 -d $LAN_IP -j RETURN"

log() {
	logger -t "$TAG" "$*"
}

# ---- IPv4：DNS 豁免规则必须在 nat PREROUTING 第一位 ----------------------
rule_is_first() {
	iptables -t nat -S PREROUTING 2>/dev/null |
		sed -n '2p' |
		grep -q -- "--dport 53 -d $LAN_IP/32 -j RETURN"
}

rule_exists() {
	iptables -t nat -C PREROUTING $RULE 2>/dev/null
}

purge_v4() {
	while rule_exists; do
		iptables -t nat -D PREROUTING $RULE 2>/dev/null || break
	done
}

ensure_v4() {
	rule_is_first && return 0
	purge_v4
	iptables -t nat -I PREROUTING 1 $RULE 2>/dev/null || return 1
	log "IPv4 DNS 豁免已顶回 nat PREROUTING 第 1 位 (LAN=$LAN_IP)"
	return 0
}

# ---- IPv6：删掉 UU 留下的 UDP/53 DROP -----------------------------------
#
# 规则由 iptables-nft 写成，参数顺序不固定，所以不按固定写法去 -D，
# 而是把 -S 的输出逐条改写成 -D 再用。只用 --dport 53 + DROP 两个特征定位，
# 避免误删别的规则。
purge_v6_drop() {
	local chain="$1" rule

	ip6tables -t filter -S "$chain" 2>/dev/null |
		grep -- "--dport 53" |
		grep -- "-j DROP" |
		while read -r rule; do
			# "-A INPUT -i br-lan ..." -> "-D INPUT -i br-lan ..."
			ip6tables -t filter $(echo "$rule" | sed "s/^-A $chain /-D $chain /") 2>/dev/null
		done

	return 0
}

sync_v6() {
	local n

	n=$(ip6tables -t filter -S 2>/dev/null | grep -- "--dport 53" | grep -c -- "-j DROP")
	[ "${n:-0}" -eq 0 ] && return 0

	purge_v6_drop INPUT
	purge_v6_drop FORWARD

	n=$(ip6tables -t filter -S 2>/dev/null | grep -- "--dport 53" | grep -c -- "-j DROP")
	if [ "${n:-0}" -eq 0 ]; then
		log "已清除 UU 残留的 IPv6 UDP/53 DROP"
	else
		log "警告：仍有 $n 条 IPv6 UDP/53 DROP 无法删除"
	fi
}

main() {
	log "启动：兜底 ${POLL}s，保护 $LAN_IP 的 DNS（IPv4 nat + IPv6 filter）"

	while :; do
		ensure_v4
		sync_v6
		sleep "$POLL"
	done
}

main
