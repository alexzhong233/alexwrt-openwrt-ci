#!/bin/sh
# Collect a non-destructive snapshot for NetBird, PassWall, DNS and routing issues.

set -u

OUT=${1:-/tmp/netbird-passwall-diagnose-$(date +%Y%m%d-%H%M%S)}
LAN_IP=${LAN_IP:-192.168.88.1}
WAN_GATEWAY=${WAN_GATEWAY:-192.168.1.1}
PEER_IP=${NETBIRD_PEER_IP:-100.111.117.82}
mkdir -p "$OUT"

run() {
	name=$1
	shift
	{
		echo "# $name"
		echo "+ $*"
		"$@"
	} > "$OUT/$name.txt" 2>&1 || true
}

run version uname -a
run release cat /etc/openwrt_release
run netbird-status netbird status -d
run netbird-cli-version netbird version
run links ip -brief link
run addresses ip -brief address
run routes ip -4 route show table all
run rules ip -4 rule show
run netbird-route ip -4 route get "$PEER_IP"
run resolv cat /etc/resolv.conf
run dnsmasq-config sh -c 'grep -nE "^(no-resolv|resolv-file|server|conf-dir|conf-file)" /var/etc/dnsmasq.conf.* 2>/dev/null'
run dnsmasq-status /etc/init.d/dnsmasq status
run passwall-status /etc/init.d/passwall status
run openclash-status /etc/init.d/openclash status
run firewall-status /etc/init.d/firewall status
run listeners sh -c 'if command -v ss >/dev/null 2>&1; then ss -lnptu; else netstat -lnptu; fi'
run dns-router nslookup www.baidu.com "$LAN_IP"
run dns-wan nslookup www.baidu.com "$WAN_GATEWAY"
run dns-public nslookup www.baidu.com 223.5.5.5
run netbird-dns nslookup www.baidu.com 127.0.0.153
run nft-rules sh -c 'nft -a list ruleset 2>/dev/null | grep -Ei "dns|dport 53|redirect|tproxy|mark"'
run log-dns sh -c 'logread 2>/dev/null | grep -Ei "dnsmasq|netbird|passwall|dns|nft" | tail -300'

if [ -d /sys/kernel/debug/ecm ]; then
	run ecm-ipv4 sh -c 'for f in accelerated_count tcp_accelerated_count udp_accelerated_count; do printf "%s: " "$f"; cat "/sys/kernel/debug/ecm/ecm_nss_ipv4/$f" 2>/dev/null; done'
	run ecm-ipv6 sh -c 'for f in accelerated_count tcp_accelerated_count udp_accelerated_count; do printf "%s: " "$f"; cat "/sys/kernel/debug/ecm/ecm_nss_ipv6/$f" 2>/dev/null; done'
fi

tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")" 2>/dev/null || true
echo "Diagnostic files: $OUT"
echo "Archive: $OUT.tar.gz"
