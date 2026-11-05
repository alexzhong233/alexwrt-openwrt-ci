#!/bin/sh

# Keep PassWall's mark from being overwritten by NetBird's prerouting chain.
# NetBird may recreate this chain, so check periodically and restore the rule
# only when it is missing.

CHAIN="ip netbird netbird-mangle-prerouting"
RULE_TEXT="meta mark 0x50535731 return"

while true; do
	if nft list chain $CHAIN >/dev/null 2>&1; then
		if ! nft -a list chain $CHAIN 2>/dev/null | grep -Fq "$RULE_TEXT"; then
			nft insert rule $CHAIN meta mark 0x50535731 return 2>/dev/null
		fi
	fi

	sleep 30
done
