#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"
TARGET_PATH="./target"

#包目录解析：自建包克隆在 ./package/<name>，改用官方 feeds 的包在
#./package/feeds/<feed>/<name>（feeds install 生成的软链）。同一个包只会在其中
#一处，按顺序找，找不到返回空串（调用方用 -f / -d 判断即可）。
PKG_DIR() {
	local NAME=$1 D
	for D in "$PACKAGE_PATH/$NAME" "$PACKAGE_PATH/feeds/luci/$NAME" "$PACKAGE_PATH/feeds/packages/$NAME"; do
		if [ -d "$D" ]; then
			printf '%s' "$D"
			return 0
		fi
	done
	return 1
}

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
	"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
	"$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
	"s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改vantage进度条标签字体（anothaDev/luci-theme-vantage#52）
FIX "theme-vantage" "$PACKAGE_PATH/luci-theme-vantage" sed -i \
	-e '/^\/\* progress bars: thin track/,$ { /^\.cbi-progressbar::before {/,/^}/ { s/^[[:space:]]*font: 500 var(--fs-micro)\/1\.2 var(--mono);/\tfont: inherit; line-height: normal;/; } }' \
	"$PACKAGE_PATH/luci-theme-vantage/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css"

#菜单归类
#
#顶层 admin/status(10) admin/system(20) admin/services(30) admin/nas(40)
#admin/vpn(50) admin/network(60) 都由 luci-base 的 menu.d 定义，只要有子项就
#会自动出现，所以这里只改各包的菜单键，不需要自己建分类节点。
#
#两类包的改法不同，不能混：
#  · JS 版（root/usr/share/luci/menu.d/*.json）：菜单是 JSON 的键，
#    形如 "admin/services/openlist2"，子项键是 "admin/services/openlist2/basic"，
#    父键是子键的前缀，所以替换不带结尾引号，一次覆盖父项和所有子项。
#  · Lua 版（luasrc/controller/*.lua）：这些包根本没有 menu.d，菜单完全来自
#    控制器里的 entry({"admin", "services", ...})，必须改 entry 的路径数组。
#    passwall 用变量 appname 拼接路径，openclash / uuplugin 是字面量。
#
#改错的表现是页面上出现两个同名菜单（旧路径没删干净），或者点进去 404。
RELOCATE_MENU() {
	local NAME=$1 ROOT=$2 OLD=$3 NEW=$4 CNT=0 F

	[ -d "$ROOT" ] || return 0

	#-L 不能省：改用官方 feeds 的包，ROOT 是 feeds install 建出来的符号链接
	#（./package/feeds/<feed>/<name> -> ../../feeds/<feed>/applications/<name>），
	#find 默认不下降「起始点本身是符号链接」的目录，会扫出 0 个文件并且一声不响
	#地跳过改写 —— 之前 openlist / qbittorrent 的菜单就因此一直留在「服务」里。
	for F in $(find -L "$ROOT" -type f -path '*/menu.d/*.json' 2>/dev/null); do
		sed -i "s#\"$OLD#\"$NEW#g" "$F" && CNT=$((CNT + 1))
	done
	if [ "$CNT" -eq 0 ]; then
		echo "menu: $NAME -> $NEW (0 files; no menu.d under $ROOT)"
	else
		echo "menu: $NAME -> $NEW ($CNT files)"
	fi
}

RELOCATE_MENU "netbird" "$PACKAGE_PATH/luci-app-netbird" \
	"admin/services/netbird" "admin/vpn/netbird"
#openlist 换成官方 feeds 版（原 sbwml 的 luci-app-openlist2），菜单键从
#admin/services/openlist 搬到「NAS」；父键是子键前缀，一次替换覆盖两页。
OPENLIST_DIR=$(PKG_DIR luci-app-openlist) || OPENLIST_DIR=""
RELOCATE_MENU "openlist" "$OPENLIST_DIR" \
	"admin/services/openlist" "admin/nas/openlist"
QBITTORRENT_DIR=$(PKG_DIR luci-app-qbittorrent) || QBITTORRENT_DIR=""
RELOCATE_MENU "qbittorrent" "$QBITTORRENT_DIR" \
	"admin/services/qbittorrent" "admin/nas/qbittorrent"
#Dockerman 用的是 lisaac 0.5.26（Lua 控制器），它自己就建了
#entry({"admin","docker"}, firstchild())，顶层「Docker」菜单不需要额外处理。
#雅典娜屏控：上游放在「服务」里，这台机器上它属于系统级调参
RELOCATE_MENU "athena-led" "$PACKAGE_PATH/luci-app-athena-led" \
	"admin/services/athena_led" "admin/system/athena_led"
#NATMap 上游本来就在「网络」，之前这里有个 s/network/services/g 把它搬进了
#「服务」，现在搬回去。写成显式反向替换，上游哪天又改回 services 也能纠正。
RELOCATE_MENU "natmapt" "$PACKAGE_PATH/luci-app-natmapt" \
	"admin/services/natmap" "admin/network/natmap"

#VPN 三个 Lua 界面：passwall / openclash / uu 加速器
#passwall 和 openclash 现在来自官方 luci feed，路径经 PKG_DIR 解析；官方版的
#controller 里仍是 entry({"admin", "services", ...})，替换规则和以前一样。
PASSWALL_DIR=$(PKG_DIR luci-app-passwall) || PASSWALL_DIR=""
PASSWALL_CTRL="$PASSWALL_DIR/luasrc/controller/passwall.lua"
if [ -f "$PASSWALL_CTRL" ]; then
	echo " "
	if sed -i 's#"admin", "services", appname#"admin", "vpn", appname#g' "$PASSWALL_CTRL"; then
		echo "menu: passwall -> admin/vpn (lua)"
	fi
fi

OPENCLASH_DIR=$(PKG_DIR luci-app-openclash) || OPENCLASH_DIR=""
OPENCLASH_CTRL="$OPENCLASH_DIR/luasrc/controller/openclash.lua"
if [ -f "$OPENCLASH_CTRL" ]; then
	echo " "
	if sed -i 's#"admin", "services", "openclash"#"admin", "vpn", "openclash"#g' "$OPENCLASH_CTRL"; then
		echo "menu: openclash -> admin/vpn (lua)"
	fi
fi

UUGAME_CTRL=$(find "$PACKAGE_PATH" -maxdepth 6 -type f \
	-path '*luci-app-uugamebooster*/luasrc/controller/uuplugin.lua' 2>/dev/null | head -1)
if [ -n "$UUGAME_CTRL" ]; then
	echo " "
	if sed -i 's#"admin", "services", "uuplugin"#"admin", "vpn", "uuplugin"#g' "$UUGAME_CTRL"; then
		echo "menu: uugamebooster -> admin/vpn (lua)"
	fi
fi

#修复 luci-app-uugamebooster 打包期 postinst 失败
#
#上游 postinst 用绝对路径 chmod：
#	chmod +x /etc/init.d/uuplugin
#	chmod +x /usr/libexec/uuplugin/*
#打包阶段（package/install）这段脚本会被直接在宿主机上执行，此时
#/etc/init.d/uuplugin 并不存在，而该仓库的 root/usr/libexec 本身是空目录，
#于是三条 chmod 全部返回 1，post-install 以 exit code 1 结束，整个构建挂在：
#	package/Makefile:164: package/install] Error 1
#	include/toplevel.mk:268: world] Error 2
#处理方式：chmod 加 2>/dev/null 容错，末尾补 exit 0 收尾，再用 IPKG_INSTROOT
#守卫让脚本只在设备上真正执行。注意 Makefile 里必须写成 $$IPKG_INSTROOT，
#单写 $ 会被 make 当成变量展开，守卫条件会永久成立。
#
#另外把 DEPENDS 里的 +libstdcpp6 换成 +libstdcpp：新版 OpenWrt 已经把 C++ 标准库
#包改名（package/libs/toolchain 里只有 define Package/libstdcpp）。保留旧名会打出
#	WARNING: ... luci-app-uugamebooster/Makefile has a dependency on
#	'libstdcpp6', which does not exist
#依赖不满足时 defconfig 会把这个包降成 is not set，固件里就没有 UU 页面了。
UUGAME_MAKEFILE=$(find "$PACKAGE_PATH" -maxdepth 3 -type f \
	-path "*luci-app-uugamebooster*/Makefile" 2>/dev/null | head -1)

if [ -n "$UUGAME_MAKEFILE" ]; then
	echo " "
	if sed -i \
		-e 's/+libstdcpp6/+libstdcpp/g' \
		-e '/^#!\/bin\/sh$/a [ -n "$$IPKG_INSTROOT" ] \&\& exit 0' \
		-e 's|^chmod +x \(.*\)$|chmod +x \1 2>/dev/null|' \
		-e 's/^endef$/exit 0\nendef/' \
		"$UUGAME_MAKEFILE"; then
		echo "uugamebooster has been fixed!"
	else
		echo "uugamebooster fix failed; continuing!"
	fi
fi

#sing-box 用官方 feeds 版，但要去掉 naive_outbound 依赖
#
#feeds 的 sing-box full 变体把 with_naive_outbound 写成定值（def_bool y），
#并且 DEPENDS 到 libcronet —— 那是 Chromium 的 net 栈，构建要下载一份
#700 MB 的 clang、PGO 剖面和 gn/ninja，还要几十 GB 磁盘，GitHub Runner 直接
#撑不下去。我们根本不需要它：passwall 只用 sing-box 跑 hysteria2/tuic 这类
#出站，NaiveProxy 自己有独立客户端（INCLUDE_NaiveProxy 也是关的）。
#
#两处必须一起改：
#  · DEPENDS 里的 +SING_BOX_BUILD_NAIVE_OUTBOUND:libcronet
#  · Kconfig 里的 config SING_BOX_BUILD_NAIVE_OUTBOUND / def_bool y
#    （无 prompt 的符号在 .config 里改不动，只能从 Kconfig 删除）
#删完之后 GO_PKG_TAGS 里 $(if $(CONFIG_SING_BOX_BUILD_NAIVE_OUTBOUND),...) 自然
#变空，sing-box 回到纯 Go 编译。改完用 grep 兜底：上游哪天换了写法就直接失败，
#而不是悄悄把 Chromium 拖回构建。
#
#顺手把 full 变体里四个路由器上用不到的 tag 也摘掉：cloudflared（Cloudflare
#隧道客户端）、openconnect、openvpn、usbip —— 它们在官方版里是硬编码常开的，
#光 cloudflared 就是十几 MiB 的 Go 代码。viking 那份本来就没带这些，体积才对得上。
SINGBOX_MK="$FEEDS_PATH/packages/net/sing-box/Makefile"
if [ -f "$SINGBOX_MK" ]; then
	echo " "
	sed -i \
		-e 's/ +SING_BOX_BUILD_NAIVE_OUTBOUND:libcronet//' \
		-e '/^[[:space:]]*config SING_BOX_BUILD_NAIVE_OUTBOUND$/,/^[[:space:]]*depends on /d' \
		-e '/^[[:space:]]*with_cloudflared[[:space:]]*\\$/d' \
		-e '/^[[:space:]]*with_openconnect[[:space:]]*\\$/d' \
		-e '/^[[:space:]]*with_openvpn[[:space:]]*\\$/d' \
		-e '/^[[:space:]]*with_usbip[[:space:]]*\\$/d' \
		"$SINGBOX_MK"
	if grep -q 'SING_BOX_BUILD_NAIVE_OUTBOUND:libcronet' "$SINGBOX_MK" ||
		grep -qE '^[[:space:]]*config SING_BOX_BUILD_NAIVE_OUTBOUND$' "$SINGBOX_MK"; then
		echo "::error::feeds sing-box still pulls libcronet; the Makefile layout changed" >&2
		exit 1
	fi
	echo "sing-box: naive_outbound (libcronet) + cloudflared/openconnect/openvpn/usbip tags removed"
fi

#从设备默认包列表里去掉 luci-i18n-athena-led-zh-cn
#
#上游 target/linux/qualcommax/image/ipq60xx.mk 里 jdcloud_re-cs-02 的
#DEVICE_PACKAGES 写死了 luci-app-athena-led 和 luci-i18n-athena-led-zh-cn。
#后者是上游 1.0 界面包用 luci.mk 拆出来的 i18n 包；我们把界面换成
#577090447 的 2.5.0 版（用 package.mk 打包，中文 lmo 由 install 段直接装，
#不拆独立 i18n 包），这个包就不存在了。DEVICE_PACKAGES 会经 defconfig 写进
#.config，于是在打 target-dir 时 apk 报：
#	ERROR: unable to select packages:
#	  luci-i18n-athena-led-zh-cn (no such package)
#只能从设备定义这一层去掉，光改 Config 是没用的。
ATHENA_IMAGE_MK="$TARGET_PATH/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$ATHENA_IMAGE_MK" ]; then
	echo " "
	if sed -i 's/ *luci-i18n-athena-led-zh-cn//g' "$ATHENA_IMAGE_MK"; then
		echo "athena-led i18n package dropped from DEVICE_PACKAGES"
	fi
fi
