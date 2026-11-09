#!/bin/sh
# 把 luci-app-1panel 的四个文件从 GitHub 拉到路由器上，不重刷固件就能用。
#
# 用法（两条任选，哪条通走哪条）：
#   curl -fsSL https://raw.githubusercontent.com/alexzhong233/alexwrt-openwrt-ci/main/backup/tools/deploy-1panel-luci.sh | sh
#   curl -fsSL https://cdn.jsdelivr.net/gh/alexzhong233/alexwrt-openwrt-ci@main/backup/tools/deploy-1panel-luci.sh | sh
#
# 不下载脚本、直接跑也可以：
#   sh /tmp/deploy-1panel-luci.sh
#
# 幂等：重复执行就是覆盖同一批文件。刷机后 overlay 被清空，重跑一次即可。

REPO="alexzhong233/alexwrt-openwrt-ci"
BRANCH="main"

RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
CDN="https://cdn.jsdelivr.net/gh/$REPO@$BRANCH"

TMP="/tmp/1panel-luci-deploy.$$"
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP"' EXIT

log() { echo "== $*"; }
die() { echo "!! $*" >&2; exit 1; }

fetch() {
	# $1 = 仓库内路径，$2 = 本地临时文件名
	local rel="$1" out="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 10 --max-time 60 -o "$out" "$RAW/$rel" && return 0
		log "raw.githubusercontent.com 拉取失败，换 jsDelivr"
		curl -fsSL --connect-timeout 10 --max-time 60 -o "$out" "$CDN/$rel" && return 0
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -O "$out" "$RAW/$rel" && return 0
		log "raw.githubusercontent.com 拉取失败，换 jsDelivr"
		uclient-fetch -q -O "$out" "$CDN/$rel" && return 0
	else
		die "没有 curl 或 uclient-fetch，装一个：apk add curl"
	fi

	return 1
}

install_file() {
	# $1 = 仓库内路径，$2 = 目标路径，$3 = 权限
	local rel="$1" dst="$2" mode="$3" base

	base=$(basename "$rel")
	log "下载 $base"
	fetch "$rel" "$TMP/$base" || die "$rel 下载失败（两条线路都不通）"

	# 拉回来的东西一定得是个真文件：404 页面、被 .gitignore 吞掉的占位都可能
	# 只有几十字节，直接铺上去会留下一个坏脚本。
	[ -s "$TMP/$base" ] || die "$rel 内容为空"
	[ "$(wc -c <"$TMP/$base")" -gt 100 ] || die "$rel 只有 $(wc -c <"$TMP/$base") 字节，不像正常内容"

	mkdir -p "$(dirname "$dst")" || die "无法创建 $(dirname "$dst")"
	cp -f "$TMP/$base" "$dst" || die "写入 $dst 失败"
	chmod "$mode" "$dst"
	echo "   -> $dst ($(wc -c <"$dst") 字节)"
}

install_file "Files/RE-CS-02/usr/libexec/1panel-ctl" \
	"/usr/libexec/1panel-ctl" 0755
install_file "LuCI/luci-app-1panel/root/usr/share/luci/menu.d/luci-app-1panel.json" \
	"/usr/share/luci/menu.d/luci-app-1panel.json" 0644
install_file "LuCI/luci-app-1panel/root/usr/share/rpcd/acl.d/luci-app-1panel.json" \
	"/usr/share/rpcd/acl.d/luci-app-1panel.json" 0644
install_file "LuCI/luci-app-1panel/htdocs/luci-static/resources/view/1panel/status.js" \
	"/www/luci-static/resources/view/1panel/status.js" 0644

log "重启 rpcd 并清 LuCI 缓存"
/etc/init.d/rpcd restart >/dev/null 2>&1
rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null

log "自检"
/usr/libexec/1panel-ctl status 2>/dev/null | head -n 12 || true

cat <<'EOF'

装好了。浏览器 Ctrl+Shift+R（Mac 是 Cmd+Shift+R）强刷，左侧菜单：
  NAS → 1Panel

命令行也能直接用（ctl 在 /usr/libexec，没做软链接）：
  /usr/libexec/1panel-ctl status
  /usr/libexec/1panel-ctl install 10086 1panel '你的密码' '你的入口' /mnt/sda1/Configs/1Panel

装之前先看 df -h / ：1Panel 的两个二进制约 152MB 要写进 overlay。
EOF
