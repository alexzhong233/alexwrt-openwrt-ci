#!/bin/sh

# Keep dnsmasq off the NetBird interface so NetBird can own its DNS listener
# while dnsmasq continues serving the LAN address.

set -u

ACTION=${1:-check}
CONF=${DNSMASQ_CONF:-/etc/dnsmasq.conf}
IFACE=${NETBIRD_IF:-wt0}
BACKUP_ROOT=${BACKUP_ROOT:-/root/dnsmasq-netbird-backups}

usage() {
	cat <<'EOF'
Usage:
  netbird-dnsmasq-wt0-fix.sh check
  netbird-dnsmasq-wt0-fix.sh apply
  netbird-dnsmasq-wt0-fix.sh rollback BACKUP_FILE

Environment overrides:
  DNSMASQ_CONF=/etc/dnsmasq.conf
  NETBIRD_IF=wt0
  BACKUP_ROOT=/root/dnsmasq-netbird-backups
EOF
}

show_state() {
	echo "== dnsmasq config =="
	echo "$CONF"
	if [ -f "$CONF" ]; then
		grep -nE '^[[:space:]]*(except-interface|interface|notinterface)' "$CONF" || true
	else
		echo "missing: $CONF"
	fi

	echo "== listeners on port 53 =="
	if command -v netstat >/dev/null 2>&1; then
		netstat -lnptu 2>/dev/null | grep -E ':53[[:space:]]' || true
	else
		ss -lnptu 2>/dev/null | grep -E ':53[[:space:]]' || true
	fi

	echo "== dnsmasq service =="
	/etc/init.d/dnsmasq status 2>&1 || true
}

apply_fix() {
	[ -f "$CONF" ] || {
		echo "Config not found: $CONF" >&2
		exit 1
	}

	mkdir -p "$BACKUP_ROOT"
	backup="$BACKUP_ROOT/dnsmasq.conf.$(date +%Y%m%d-%H%M%S)"
	cp -p "$CONF" "$backup"
	echo "Backup: $backup"

	if grep -qxF "except-interface=$IFACE" "$CONF"; then
		echo "Already configured: except-interface=$IFACE"
	else
		printf '\nexcept-interface=%s\n' "$IFACE" >> "$CONF"
		echo "Added: except-interface=$IFACE"
	fi

	/etc/init.d/dnsmasq restart
	echo "dnsmasq restarted"
}

rollback_fix() {
	backup=${2:-}
	[ -n "$backup" ] || {
		echo "Usage: $0 rollback /path/to/backup" >&2
		exit 2
	}
	[ -f "$backup" ] || {
		echo "Backup not found: $backup" >&2
		exit 1
	}

	cp -p "$backup" "$CONF"
	/etc/init.d/dnsmasq restart
	echo "Restored: $CONF"
}

case "$ACTION" in
	check)
		show_state
		;;
	apply)
		apply_fix
		show_state
		;;
	rollback)
		rollback_fix "$@"
		show_state
		;;
	-h|--help|help)
		usage
		;;
	*)
		usage >&2
		exit 2
		;;
esac
