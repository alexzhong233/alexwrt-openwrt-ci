#!/bin/sh
# Export package lists, UCI state, service state and scripts before firmware upgrades.
# Set INCLUDE_SECRETS=1 only when the archive will stay private.
#
# 默认脱敏是启发式的（键名 + 值特征），能挡住常见写法，但挡不住所有写法。
# INCLUDE_SECRETS=0 不等于"可以随便发"，导出包一律按敏感文件对待。

set -u

OUT=${1:-/tmp/router-export-$(date +%Y%m%d-%H%M%S)}
INCLUDE_SECRETS=${INCLUDE_SECRETS:-0}
CONFIG_DIR=${CONFIG_DIR:-/etc/config}

mkdir -p "$OUT" "$OUT/packages" "$OUT/config-redacted" "$OUT/runtime" "$OUT/scripts"

echo "Export directory: $OUT"
echo "INCLUDE_SECRETS=$INCLUDE_SECRETS" > "$OUT/README.txt"
echo "This export may contain network topology and service configuration." >> "$OUT/README.txt"
echo "Redaction is heuristic (key names plus value patterns), not a security guarantee." >> "$OUT/README.txt"
echo "Treat this archive as sensitive even when INCLUDE_SECRETS=0." >> "$OUT/README.txt"

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

# 脱敏 /etc/config/* 再落盘。之前用一条 sed 只认 password=/token= 这类键名，
# 换个别名（pass、key、psk）或把凭据塞进 JSON 值里就直接漏出来。这里改成
# 三层判断：键名命中敏感词 / 值本身像凭据 / 值里嵌着凭据键，任一命中就打码。
# 宁可多打码——这份导出是给"人看和对照"的，不是给机器还原用的。
redact_config() {
	awk '
	function sensitive(k,   l) {
		l = tolower(k)
		gsub(/-/, "_", l)
		if (l ~ /(^|_)(pass|passwd|password|pwd|secret|token|key|psk|uuid|credential|cookie|auth|private|licen[cs]e|apikey|api_key|subscription|sub_url|url|endpoint|user|username|email|identity|account|sid|sn)($|_)/)
			return 1
		return 0
	}

	function secret_value(v,   t, l) {
		t = v
		l = tolower(v)
		if (t ~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/)
			return 1
		if (t ~ /^[0-9a-fA-F]{32,}$/)
			return 1
		if (t ~ /^[A-Za-z0-9+\/=_-]{40,}$/)
			return 1
		if (l ~ /^(ss|ssr|ssd|vmess|vless|trojan|hysteria2?|hy2|tuic|wireguard|wg):\/\//)
			return 1
		if (t ~ /:\/\/[^\/]*:[^\/@]*@/)
			return 1
		if (l ~ /[?&](token|key|password|passwd|secret|auth|apikey|api_key)=/)
			return 1
		if (l ~ /"[^"]*(pass|passwd|password|psk|secret|token|uuid|auth|key)[^"]*"[[:space:]]*:/)
			return 1
		return 0
	}

	/-----BEGIN [A-Z ]*PRIVATE KEY-----/ {
		inkey = 1
		print "-----BEGIN PRIVATE KEY-----<redacted>"
		next
	}
	inkey && /-----END [A-Z ]*PRIVATE KEY-----/ {
		inkey = 0
		print "-----END PRIVATE KEY-----"
		next
	}
	inkey { next }

	$1 == "option" || $1 == "list" {
		key = $2
		indent = $0
		sub(/[^[:space:]].*$/, "", indent)
		val = substr($0, index($0, key) + length(key))
		sub(/^[[:space:]]+/, "", val)
		inner = val
		sub(/^\047/, "", inner)
		sub(/\047[[:space:]]*$/, "", inner)
		if (sensitive(key) || secret_value(inner)) {
			print indent $1 " " key " \047<redacted>\047"
			next
		}
		print
		next
	}

	/^[[:space:]]*[A-Za-z0-9_.-]+=/ {
		eq = index($0, "=")
		key = substr($0, 1, eq - 1)
		indent = key
		sub(/[^[:space:]].*$/, "", indent)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
		if (sensitive(key) || secret_value(substr($0, eq + 1))) {
			print indent key "=<redacted>"
			next
		}
		print
		next
	}

	{ print }
	' "$1"
}

if [ -d "$CONFIG_DIR" ]; then
	for file in "$CONFIG_DIR"/*; do
		[ -f "$file" ] || continue
		base=$(basename "$file")
		if [ "$INCLUDE_SECRETS" = 1 ]; then
			cp -f "$file" "$OUT/config-redacted/$base" 2>/dev/null || true
		else
			# 脱敏失败时不能退回明文拷贝——那等于静默泄露全部凭据。
			if ! redact_config "$file" > "$OUT/config-redacted/$base" 2>/dev/null; then
				rm -f "$OUT/config-redacted/$base"
				printf '! redaction failed, file skipped to avoid leaking secrets\n' \
					> "$OUT/config-redacted/$base.FAILED"
			fi
		fi
	done
fi

tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "Archive: $OUT.tar.gz"
