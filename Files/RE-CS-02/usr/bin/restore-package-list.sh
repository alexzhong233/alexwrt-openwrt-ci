#!/bin/sh
# Restore package names from an export created by export-router-state.sh.
# This only installs packages; it does not restore configuration or data.

set -u

MANIFEST=${1:-}
[ -n "$MANIFEST" ] || {
	echo "Usage: restore-package-list.sh /path/to/apk-installed.txt" >&2
	exit 2
}
[ -f "$MANIFEST" ] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

if command -v apk >/dev/null 2>&1; then
	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		case "$pkg" in \#*) continue ;; esac
		echo "Installing $pkg"
		apk add "$pkg" || echo "Failed: $pkg" >&2
	done < "$MANIFEST"
elif command -v opkg >/dev/null 2>&1; then
	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		case "$pkg" in \#*) continue ;; esac
		echo "Installing $pkg"
		opkg install "$pkg" || echo "Failed: $pkg" >&2
	done < "$MANIFEST"
else
	echo "Neither apk nor opkg was found" >&2
	exit 1
fi
