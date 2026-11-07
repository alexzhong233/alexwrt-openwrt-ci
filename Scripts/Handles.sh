#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"
TARGET_PATH="./target"

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

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
	"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"

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
