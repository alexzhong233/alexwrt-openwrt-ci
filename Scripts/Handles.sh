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

#无线默认 SSID
#
#首次启动由 /sbin/wifi config 调 ucode /lib/wifi/mac80211.uc 生成
#/etc/config/wireless，SSID / 加密 / 密码是写死的兜底：
#  set ${si}.ssid='${defaults?.ssid || 'OWRT'}'
#  set ${si}.encryption='${defaults?.encryption || 'psk2+ccmp'}'
#  set ${si}.key='${defaults?.key || '12345678'}'
#这里替换 SSID 兜底值、国家码、信道和 HT 模式，加密与密码保持上游默认。
#
#取值来自实机调试结果：
#  radio1 2.4G  channel 5   HE40   （默认 20MHz 是被上游 width=20 写死的）
#  radio0 5G    channel 161 HE80   SoC 内置 2x2
#  radio2 5G    channel 36  HE160  PCIe 外挂 4x4
#国家码三个 radio 都是 US，不是上游兜底的 CN。
#
#频段后缀跟着信道走：36 属 U-NII-1（5.2G），161 属 U-NII-3（5.8G）。PCIe 那块
#接在 DTS 的 &pcie0（pci17cb,1104），path 里带 pci，跑的是 36 所以叫 5.2g；
#SoC 内置 phy 同时供 2.4G 和 5.8G 两个 band。判据放在 band_name 转小写之后，
#此时它已是 2g / 5g。
#
#铁律：这只改「默认值」，只在生成配置文件时生效。radio_exists() 会跳过已存在
#的 radio，所以保留配置升级时用户自己改过的 SSID 不会被覆盖。当初删掉
#uci-defaults 版 99-alexwrt-wireless 就是因为运行时脚本会反复覆盖用户配置，
#不要再退回那套写法。
WIFI_UC="$PACKAGE_PATH/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	echo " "
	if python3 - "$WIFI_UC" <<'PY'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

if "band_suffix" in src:
    sys.exit(0)

anchor = "\t\tband_name = lc(band_name);\n"
if anchor not in src:
    sys.exit("mac80211.uc: band_name anchor not found")

inject = (
    "\n\t\tlet pci = (match(phy.path, /pci/) != null);\n"
    "\t\tlet band_suffix = band_name;\n"
    "\t\tif (band_name == '2g') {\n"
    "\t\t\tband_suffix = '2.4g';\n"
    "\t\t\tchannel = 5;\n"
    "\t\t\thtmode = 'HE40';\n"
    "\t\t} else if (band_name == '5g') {\n"
    "\t\t\tif (pci) {\n"
    "\t\t\t\tband_suffix = '5.2g';\n"
    "\t\t\t\tchannel = 36;\n"
    "\t\t\t\thtmode = 'HE160';\n"
    "\t\t\t} else {\n"
    "\t\t\t\tband_suffix = '5.8g';\n"
    "\t\t\t\tchannel = 161;\n"
    "\t\t\t\thtmode = 'HE80';\n"
    "\t\t\t}\n"
    "\t\t}\n"
)
src = src.replace(anchor, anchor + inject, 1)

# 兜底值不能按字面串匹配：各家上游这两行写法不一样。
#   · 引号：VIKINGYFY 写 'OWRT'（单引号），LibWrt 写 "LibWrt"（双引号）；
#   · 默认值：VIKINGYFY 是 OWRT，LibWrt 直接换成自己的名字。
# 所以按「标识符 + 引号 + 任意值」匹配，替换时沿用原来的引号字符，
# 这样换上游不用改脚本，也不会因为一个引号让整个构建挂掉。
pat = re.compile(r"(\$\{defaults\?\.ssid \|\| )(['\"])([^'\"]*)\2")
if not pat.search(src):
    sys.exit("mac80211.uc: ssid fallback not found")

src = pat.sub(
    lambda m: m.group(1) + m.group(2) + "alexwrt-jdcloud-" + m.group(2) + " + band_suffix",
    src, count=1)

pat = re.compile(r"(\$\{country \|\| )(['\"])([^'\"]*)\2")
if not pat.search(src):
    sys.exit("mac80211.uc: country fallback not found")

src = pat.sub(lambda m: m.group(1) + m.group(2) + "US" + m.group(2), src, count=1)

io.open(path, "w", encoding="utf-8", newline="\n").write(src)
PY
	then
		echo "wireless-ssid has been fixed!"
	else
		#这里不能只告警：补丁没打上时 SSID 会退回 OWRT，而 ucode 语法错会让
		#/sbin/wifi config 直接失败、设备起来没有无线。宁可构建失败。
		echo "wireless-ssid fix failed!"
		exit 1
	fi
fi

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
	#地跳过改写 —— 之前 openlist2 / qbittorrent 的菜单就因此一直留在「服务」里。
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
#openlist2 / qbittorrent 不再预装（qB 与 OpenList 由 luci-app-hub 的页面按需
#装），所以这里也不再迁它们的菜单 —— 构建树里根本没有这两个包。
#Dockerman 用的是 lisaac 0.5.26（Lua 控制器），它自己就建了
#entry({"admin","docker"}, firstchild())，顶层「Docker」菜单不需要额外处理。
#雅典娜屏控刻意留在上游的「服务」下，不做菜单迁移：
#它的页面里有 fs.exec('/etc/init.d/athena_led') 和写配置的操作，菜单键一动
#就得连控制器一起兜，收益只是少一次点击。
#NATMap 上游本来就在「网络」，之前这里有个 s/network/services/g 把它搬进了
#「服务」，现在搬回去。写成显式反向替换，上游哪天又改回 services 也能纠正。
RELOCATE_MENU "natmapt" "$PACKAGE_PATH/luci-app-natmapt" \
	"admin/services/natmap" "admin/network/natmap"

#VPN 三个 Lua 界面：passwall / openclash / uu 加速器
#
#这三个刻意留在「服务」里，不做迁移。原因是它们不只是菜单路径写在控制器里，
#还把 admin/services/<自己> 硬编码进页面内的链接和 AJAX：
#  · passwall 的 api.url() 是状态轮询、日志窗口、节点跳转、备份恢复共用的
#    URL 生成器（luasrc/passwall/api.lua 里 string.format("admin/services/%s",
#    appname)），只搬菜单的话整页 AJAX 全 404；
#  · openclash 有 90 处引用散在 36 个文件，含保存后的 DISP.build_url 跳转和
#    <script src> 里的 translate_js；
#  · uu 加速器状态页模板用 url([[admin]], [[services]], [[uuplugin]], [[status]])。
#改别人的代码容易在上游更新时静默失效，所以统一按上游位置放，不折腾。

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


#放行 git 源的 PKG_MIRROR_HASH（目前只有 firewall4）
#
#firewall4 是 git 源：tarball 由 `git clone --filter=blob:none` + `git archive`
#+ 把 .git 塞进 tar 现场生成，而 .git 的内容（pack 布局、refs）随 git 版本而变。
#上游每次 bump 版本时会顺手写一个在该环境算出来的 PKG_MIRROR_HASH，我们这种
#"手上没有现成 tarball、只能现场重打包"的构建机算出来必然对不上：
#
#	Hash of the local file firewall4-2026.11.08~3722eadc.tar.zst does not match
#	  (file: a95c6cfe..., requested: 70cbaec5...)
#	    ERROR: package/network/config/firewall4 failed to build.
#
#上游自己的构建机 dl/ 里早有那个文件，永远走不到重打包这条路径，所以这个问题
#他们通常不会遇到。sources.openwrt.org 上也没有对应文件（404），download.pl
#拿不到镜像版，只能 clone。
#
#PKG_SOURCE_VERSION 是完整 SHA，checkout 出来的源码仍然是确定的，所以这里放行
#（download.mk 生成的脚本本身就认 "skip"）。第一次构建会把生成好的 tarball 落进
#dl/，被 dl 缓存收走，之后就不用再重打包了。
ALLOW_MIRROR_HASH() {
	local NAME=$1 MK=""
	# firewall4 在 package/network/config/ 下面，不在 package/ 顶层，
	# 所以先按「相对 package/ 的路径」试，再退回按包名在 feeds 里找。
	if [ -f "$PACKAGE_PATH/$NAME/Makefile" ]; then
		MK="$PACKAGE_PATH/$NAME/Makefile"
	else
		MK="$(PKG_DIR "$NAME")/Makefile"
	fi
	if [ ! -f "$MK" ]; then
		echo "mirror-hash: $NAME 未找到，跳过"
		return 0
	fi
	if ! grep -q '^PKG_MIRROR_HASH:=' "$MK"; then
		echo "mirror-hash: $NAME 没有 PKG_MIRROR_HASH，跳过"
		return 0
	fi
	if grep -q '^PKG_MIRROR_HASH:=skip$' "$MK"; then
		echo "mirror-hash: $NAME 已是 skip"
		return 0
	fi
	sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/' "$MK"
	echo "mirror-hash: $NAME -> skip（源码仍由 PKG_SOURCE_VERSION 的完整 SHA 固定）"
}

ALLOW_MIRROR_HASH "network/config/firewall4"

