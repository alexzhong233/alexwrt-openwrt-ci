#!/bin/sh
# Keep NetBird from replacing the router DNS path used by dnsmasq/PassWall.
# Default action is check. Use apply or restore explicitly.

set -u

ACTION=${1:-check}
BACKUP_ROOT=${BACKUP_ROOT:-/root/netbird-dns-backups}
LAN_IP=${LAN_IP:-192.168.88.1}

usage() {
	cat <<'EOF'
Usage:
  netbird-dns-guard.sh check
  netbird-dns-guard.sh apply
  netbird-dns-guard.sh restore

apply:   run 'netbird up --disable-dns' and restart dnsmasq.
restore: run 'netbird up --disable-dns=false' and restart dnsmasq.
EOF
}

show_dns() {
	echo "== /etc/resolv.conf =="
	cat /etc/resolv.conf 2>/dev/null || true

	echo "== dnsmasq listeners =="
	if command -v ss >/dev/null 2>&1; then
		ss -lnptu 2>/dev/null | grep -E '(:53|dnsmasq)' || true
	else
		netstat -lnptu 2>/dev/null | grep -E '(:53|dnsmasq)' || true
	fi

	echo "== dnsmasq upstream files =="
	cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null || true
	grep -nE '^(no-resolv|resolv-file|server|conf-dir|conf-file)' /var/etc/dnsmasq.conf.* 2>/dev/null || true

	echo "== NetBird DNS state =="
	netbird status -d 2>/dev/null | sed -n '/Nameservers:/,/Peers count:/p' || true

	echo "== Tests =="
	for server in 127.0.0.1 127.0.0.153 "$LAN_IP"; do
		echo "-- $server --"
		nslookup www.baidu.com "$server" 2>&1 | sed -n '1,12p'
	done
}

backup() {
	stamp=$(date +%Y%m%d-%H%M%S)
	dir="$BACKUP_ROOT/$stamp"
	mkdir -p "$dir"
	cp -f /etc/resolv.conf "$dir/resolv.conf" 2>/dev/null || true
	cp -f /etc/config/dhcp "$dir/dhcp.config" 2>/dev/null || true
	cat /tmp/resolv.conf.d/resolv.conf.auto > "$dir/resolv.conf.auto" 2>/dev/null || true
	echo "$dir"
}

set_dns_mode() {
	mode=$1
	backup_dir=$(backup)
	echo "Backup written to: $backup_dir"

	if [ "$mode" = disabled ]; then
		netbird up --disable-dns
	else
		netbird up --disable-dns=false
	fi

	/etc/init.d/dnsmasq restart
	sleep 1
	show_dns
}

command -v netbird >/dev/null 2>&1 || { echo "netbird command not found" >&2; exit 1; }

case "$ACTION" in
	check) show_dns ;;
	apply) set_dns_mode disabled ;;
	restore) set_dns_mode enabled ;;
	-h|--help|help) usage ;;
	*) usage; exit 2 ;;
esac
