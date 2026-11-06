#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

#修改默认WIFI账号密码
# 说明：mac80211.uc 在新分支已改为 ucode 生成器（set ${si}.ssid='${defaults?.ssid || 'OWRT'}'），
# 旧的字面量 sed（ssid 'xxx'）匹配不到任何内容。默认无线改由 Files/RE-CS-02 的
# 首启脚本 99-niubialex-wireless 设置，这里只负责把入参替换进占位符。
WIRELESS_DEF="./files/etc/uci-defaults/99-niubialex-wireless"
if [ -f "$WIRELESS_DEF" ]; then
	SSID_ESC=$(printf '%s' "${WRT_SSID:-niubiAlex}" | sed 's/[\\&|]/\\&/g')
	WORD_ESC=$(printf '%s' "${WRT_WORD:-}" | sed 's/[\\&|]/\\&/g')
	if [ -n "${WRT_WORD:-}" ]; then
		sed -i "s|@WRT_SSID@|$SSID_ESC|g; s|@WRT_WORD@|$WORD_ESC|g" "$WIRELESS_DEF"
	else
		sed -i "s|@WRT_SSID@|$SSID_ESC|g; s/@WRT_WORD@//g; s/=psk2+ccmp/=none/g; /\.key=/d" "$WIRELESS_DEF"
	fi
else
	echo "Wireless default script not found, skip SSID injection: $WIRELESS_DEF" >&2
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "$WRT_WIFI" == "WIFI-NO" ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi
