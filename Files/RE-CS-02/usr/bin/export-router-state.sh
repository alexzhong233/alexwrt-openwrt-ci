#!/bin/sh
# Export package lists, UCI state, service state and scripts before firmware upgrades.
# Set INCLUDE_SECRETS=1 only when the archive will stay private.

set -u

OUT=${1:-/tmp/router-export-$(date +%Y%m%d-%H%M%S)}
INCLUDE_SECRETS=${INCLUDE_SECRETS:-0}

mkdir -p "$OUT" "$OUT/packages" "$OUT/config-redacted" "$OUT/runtime" "$OUT/scripts"

echo "Export directory: $OUT"
echo "INCLUDE_SECRETS=$INCLUDE_SECRETS" > "$OUT/README.txt"
echo "This export may contain network topology and service configuration." >> "$OUT/README.txt"

if command -v apk >/dev/null 2>&1; then
	apk info -e 2>/dev/null | sort -u > "$OUT/packages/apk-installed.txt" || true
	apk list --installed 2>/dev/null | sort -u > "$OUT/packages/apk-installed-verbose.txt" || true
elif command -v opkg >/dev/null 2>&1; then
	opkg list-installed 2>/dev/null | awk '{print $1}' | sort -u > "$OUT/packages/opkg-installed.txt" || true
	opkg list-installed 2>/dev/null | sort -u > "$OUT/packages/opkg-installed-verbose.txt" || true
fi

uci show > "$OUT/runtime/uci-show.txt" 2>/dev/null || true
uci export network > "$OUT/runtime/network.uci" 2>/dev/null || true
uci export firewall > "$OUT/runtime/firewall.uci" 2>/dev/null || true
cat /etc/openwrt_release > "$OUT/runtime/openwrt_release" 2>/dev/null || true
uname -a > "$OUT/runtime/uname" 2>/dev/null || true
df -h > "$OUT/runtime/df-h" 2>/dev/null || true
mount > "$OUT/runtime/mount" 2>/dev/null || true
ip -brief link > "$OUT/runtime/ip-link" 2>/dev/null || true
ip -brief address > "$OUT/runtime/ip-address" 2>/dev/null || true
ip -4 route show table all > "$OUT/runtime/ip-route" 2>/dev/null || true
ip -4 rule show > "$OUT/runtime/ip-rule" 2>/dev/null || true

for service in docker dockerd passwall openclash netbird dnsmasq firewall; do
	if [ -x "/etc/init.d/$service" ]; then
		"/etc/init.d/$service" status > "$OUT/runtime/service-$service.txt" 2>&1 || true
	fi
done

if command -v docker >/dev/null 2>&1; then
	docker ps -a > "$OUT/runtime/docker-ps.txt" 2>&1 || true
	docker images > "$OUT/runtime/docker-images.txt" 2>&1 || true
	docker volume ls > "$OUT/runtime/docker-volumes.txt" 2>&1 || true
fi

if command -v netbird >/dev/null 2>&1; then
	netbird status -d > "$OUT/runtime/netbird-status.txt" 2>&1 || true
	if [ "$INCLUDE_SECRETS" = 1 ]; then
		cp -a /var/lib/netbird "$OUT/runtime/netbird-state" 2>/dev/null || true
	fi
fi

for path in /etc/init.d /etc/hotplug.d /usr/bin /usr/sbin /usr/local/bin /root; do
	if [ -d "$path" ]; then
		find "$path" -maxdepth 2 -type f -name '*.sh' -exec cp -f {} "$OUT/scripts/" \; 2>/dev/null || true
	fi
done

if [ -d /etc/config ]; then
	for file in /etc/config/*; do
		[ -f "$file" ] || continue
		base=$(basename "$file")
		if [ "$INCLUDE_SECRETS" = 1 ]; then
			cp -f "$file" "$OUT/config-redacted/$base" 2>/dev/null || true
		else
			sed -E 's/((password|passwd|secret|token|private_key|access_token|cookie|credential)[^=]*=).*/\1<redacted>/Ig' "$file" > "$OUT/config-redacted/$base" 2>/dev/null || cp -f "$file" "$OUT/config-redacted/$base"
		fi
	done
fi

tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "Archive: $OUT.tar.gz"
