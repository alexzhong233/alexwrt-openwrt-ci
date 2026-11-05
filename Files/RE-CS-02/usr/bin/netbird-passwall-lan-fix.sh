#!/bin/sh
# Configure a NetBird interface as a routed firewall zone.
# This makes NetBird clients eligible for LAN/WAN forwarding and WAN NAT.
# It does not rewrite PassWall rules; verify PassWall scope after applying.

set -u

ACTION=${1:-check}
NETBIRD_IF=${NETBIRD_IF:-wt0}
NETBIRD_NET=${NETBIRD_NET:-netbird}
NETBIRD_ZONE=${NETBIRD_ZONE:-netbird}
BACKUP_ROOT=${BACKUP_ROOT:-/root/netbird-passwall-backups}

usage() {
	cat <<'EOF'
Usage:
  netbird-passwall-lan-fix.sh check
  netbird-passwall-lan-fix.sh apply
  netbird-passwall-lan-fix.sh rollback BACKUP_DIR

Environment overrides:
  NETBIRD_IF=wt0
  NETBIRD_NET=netbird
  NETBIRD_ZONE=netbird
  BACKUP_ROOT=/root/netbird-passwall-backups
EOF
}

need() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "Missing command: $1" >&2
		exit 1
	}
}

show_state() {
	echo "== NetBird interface =="
	ip -brief link show "$NETBIRD_IF" 2>/dev/null || ip link show "$NETBIRD_IF" 2>/dev/null || true
	ip -4 addr show dev "$NETBIRD_IF" 2>/dev/null || true

	echo "== NetBird route =="
	ip -4 route show dev "$NETBIRD_IF" 2>/dev/null || true

	echo "== Network UCI =="
	uci -q show "network.$NETBIRD_NET" 2>/dev/null || echo "network.$NETBIRD_NET is not defined"

	echo "== Firewall zone and forwarding =="
	uci -q show "firewall.$NETBIRD_ZONE" 2>/dev/null || echo "firewall.$NETBIRD_ZONE is not defined"
	uci show firewall 2>/dev/null | grep -E "src='${NETBIRD_ZONE}'|dest='${NETBIRD_ZONE}'" || true

	echo "== WAN masquerading =="
	uci show firewall 2>/dev/null | grep -E "masq='1'|name='wan'" || true

	echo "== PassWall processes =="
	/etc/init.d/passwall status 2>/dev/null || true
	pgrep -af 'passwall|xray|sing-box|chinadns|hysteria|tuic' 2>/dev/null || true
}

backup() {
	stamp=$(date +%Y%m%d-%H%M%S)
	dir="$BACKUP_ROOT/$stamp"
	mkdir -p "$dir"
	uci export network > "$dir/network.uci" 2>/dev/null || true
	uci export firewall > "$dir/firewall.uci" 2>/dev/null || true
	cp -f /etc/config/network "$dir/network.config" 2>/dev/null || true
	cp -f /etc/config/firewall "$dir/firewall.config" 2>/dev/null || true
	echo "$dir"
}

add_forwarding() {
	src=$1
	dest=$2
	if uci show firewall 2>/dev/null | grep -q "src='$src'.*dest='$dest'"; then
		return 0
	fi
	section=$(uci add firewall forwarding)
	uci set "firewall.$section.src=$src"
	uci set "firewall.$section.dest=$dest"
}

apply_config() {
	backup_dir=$(backup)
	echo "Backup written to: $backup_dir"

	if ! uci -q get "network.$NETBIRD_NET.proto" >/dev/null 2>&1; then
		uci set "network.$NETBIRD_NET=interface"
		uci set "network.$NETBIRD_NET.proto=none"
		uci set "network.$NETBIRD_NET.device=$NETBIRD_IF"
	else
		echo "Keeping existing network.$NETBIRD_NET definition"
	fi

	if ! uci -q get "firewall.$NETBIRD_ZONE.name" >/dev/null 2>&1; then
		uci set "firewall.$NETBIRD_ZONE=zone"
		uci set "firewall.$NETBIRD_ZONE.name=$NETBIRD_ZONE"
		uci set "firewall.$NETBIRD_ZONE.input=ACCEPT"
		uci set "firewall.$NETBIRD_ZONE.output=ACCEPT"
		uci set "firewall.$NETBIRD_ZONE.forward=ACCEPT"
	else
		echo "Keeping existing firewall.$NETBIRD_ZONE zone definition"
	fi

	if ! uci show firewall 2>/dev/null | grep -q "firewall.$NETBIRD_ZONE.network='$NETBIRD_NET'"; then
		uci add_list "firewall.$NETBIRD_ZONE.network=$NETBIRD_NET"
	fi

	add_forwarding "$NETBIRD_ZONE" wan
	add_forwarding "$NETBIRD_ZONE" lan

	uci commit network
	uci commit firewall
	/etc/init.d/network reload
	/etc/init.d/firewall reload

	echo "Applied. Check that the WAN zone already has masq='1'."
	echo "Then add the NetBird interface or subnet to PassWall's proxy scope/ACL if it is still bypassing PassWall."
	show_state
}

rollback() {
	dir=${2:-}
	[ -n "$dir" ] || { usage; exit 2; }
	[ -f "$dir/network.config" ] || { echo "Missing $dir/network.config" >&2; exit 1; }
	[ -f "$dir/firewall.config" ] || { echo "Missing $dir/firewall.config" >&2; exit 1; }
	cp -f "$dir/network.config" /etc/config/network
	cp -f "$dir/firewall.config" /etc/config/firewall
	/etc/init.d/network reload
	/etc/init.d/firewall reload
	echo "Rolled back from $dir"
}

need ip
need uci

case "$ACTION" in
	check) show_state ;;
	apply) apply_config ;;
	rollback) rollback "$@" ;;
	-h|--help|help) usage ;;
	*) usage; exit 2 ;;
esac
