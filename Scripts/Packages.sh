#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find $REPO_PATH/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf $REPO_PATH
	fi
}

# 拉取仓库根目录就是一个 OpenWrt 软件包的项目。
# 这类仓库没有上层 package 目录，不能走 UPDATE_PACKAGE 的 pkg 提取逻辑。
UPDATE_TOPLEVEL_PACKAGE() {
	local PKG_DIR=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local TMP_DIR

	echo " "
	echo "Update top-level package: $PKG_DIR from $PKG_REPO"
	for ROOT in ./feeds/luci ./feeds/packages; do
		find "$ROOT" -maxdepth 3 -type d -iname "*$PKG_DIR*" -exec rm -rf {} + 2>/dev/null || true
	done
	TMP_DIR=$(mktemp -d)
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" "$TMP_DIR/src"

	if [ ! -f "$TMP_DIR/src/Makefile" ]; then
		echo "Top-level Makefile missing in $PKG_REPO" >&2
		rm -rf "$TMP_DIR"
		return 1
	fi

	rm -rf "./package/$PKG_DIR"
	mkdir -p "./package/$PKG_DIR"
	cp -a "$TMP_DIR/src/." "./package/$PKG_DIR/"
	rm -rf "$TMP_DIR"
}

# 从仓库的指定子目录提取一个 OpenWrt 软件包。
# 适用于仓库根目录包含 README、feed 和测试文件，但真正的包位于子目录的项目。
UPDATE_NESTED_PACKAGE() {
	local PKG_DIR=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SOURCE_DIR=$4
	local TMP_DIR

	echo " "
	echo "Update nested package: $PKG_DIR from $PKG_REPO/$PKG_SOURCE_DIR"
	for ROOT in ./feeds/luci ./feeds/packages; do
		find "$ROOT" -maxdepth 3 -type d -iname "*$PKG_DIR*" -exec rm -rf {} + 2>/dev/null || true
	done
	TMP_DIR=$(mktemp -d)
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" "$TMP_DIR/src"

	if [ ! -f "$TMP_DIR/src/$PKG_SOURCE_DIR/Makefile" ]; then
		echo "Nested package Makefile missing in $PKG_REPO/$PKG_SOURCE_DIR" >&2
		rm -rf "$TMP_DIR"
		return 1
	fi

	rm -rf "./package/$PKG_DIR"
	mkdir -p "./package/$PKG_DIR"
	cp -a "$TMP_DIR/src/$PKG_SOURCE_DIR/." "./package/$PKG_DIR/"
	rm -rf "$TMP_DIR"
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"
UPDATE_PACKAGE "dockerman" "lisaac/luci-app-dockerman" "master"
# firewall4/APK 对版本字段按 SemVer 校验，不接受 Dockerman Makefile 当前的
# "v0.5.26" 写法；去掉前缀后不改变软件版本，只修正打包元数据。
DOCKERMAN_MAKEFILE="./package/luci-app-dockerman/applications/luci-app-dockerman/Makefile"
if [ -f "$DOCKERMAN_MAKEFILE" ]; then
	sed -i 's/^PKG_VERSION:=v/PKG_VERSION:=/' "$DOCKERMAN_MAKEFILE"
fi
# 雅典娜 RE-CS-02 LED：使用控制器仓库根目录下的两个 OpenWrt 软件包。
# 该仓库没有 pkg/ 父目录，因此分别提取 athena-led 和 luci-app-athena-led。
UPDATE_NESTED_PACKAGE "athena-led" \
	"577090447/JDC-AX6600-Athena-LED-Controller" \
	"main" \
	"athena-led"
UPDATE_NESTED_PACKAGE "luci-app-athena-led" \
	"577090447/JDC-AX6600-Athena-LED-Controller" \
	"main" \
	"luci-app-athena-led"
UPDATE_TOPLEVEL_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "main"
UPDATE_TOPLEVEL_PACKAGE "vlmcsd" "mchome/openwrt-vlmcsd" "master"
# vlmcsd 的旧版 GNUmakefile 与 OpenWrt 的 ccache 包装器不兼容：它会把多个
# C 文件错误地传给同一个 gcc -c -o 命令。使用真实交叉编译器并串行构建。
VLMCSD_MAKEFILE="./package/vlmcsd/Makefile"
if [ -f "$VLMCSD_MAKEFILE" ]; then
	# 上游写的是 PKG_VERSION=svn1112。新 APK 打包器要求版本号必须以数字
	# 开头，否则 apk mkpkg 直接报 "package version is invalid" 并中断编译。
	# 去掉 svn 前缀不改变软件版本，只修正打包元数据（与 Dockerman 的 v 前缀同理）。
	sed -i -E 's/^PKG_VERSION[[:space:]]*[:+]?=[[:space:]]*svn/PKG_VERSION:=/' "$VLMCSD_MAKEFILE"
	python3 - "$VLMCSD_MAKEFILE" <<'PYEOF'
import re
import sys

path = sys.argv[1]
content = open(path, encoding="utf-8").read()

content = re.sub(r"\ndefine Build/Compile\n.*?endef\n", "\n", content, flags=re.S)
compile_block = r'''
define Build/Compile
	$(MAKE) -j1 -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC_NOCACHE)" \
		CXX="$(TARGET_CXX_NOCACHE)" \
		AR="$(TARGET_AR)" \
		RANLIB="$(TARGET_RANLIB)" \
		STRIP="$(STRIP)" \
		AS="$(TARGET_CROSS)as" \
		LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		CROSS="$(TARGET_CROSS)" \
		ARCH="$(ARCH)" \
		MAX_THREADS=1
endef
'''

marker = "$(eval $(call BuildPackage,vlmcsd))"
if marker not in content:
    raise SystemExit("vlmcsd BuildPackage marker not found")
if "TARGET_CC_NOCACHE" not in content:
    content = content.replace(marker, compile_block + "\n" + marker, 1)

open(path, "w", encoding="utf-8", newline="").write(content)
PYEOF
fi
UPDATE_TOPLEVEL_PACKAGE "luci-app-vlmcsd" "mchome/luci-app-vlmcsd" "master"
UPDATE_NESTED_PACKAGE "luci-app-netbird" "looong-cat/luci-app-netbird" "main" "luci-app-netbird"

# NetBird is a Go package in the OpenWrt packages feed. Reuse the feed copy
# when available; otherwise fetch only net/netbird into the build tree.
if ! find ./feeds/packages ./package -type d -path '*/netbird' 2>/dev/null | grep -q .; then
	NETBIRD_TMP=$(mktemp -d)
	git clone --depth=1 --filter=blob:none --sparse https://github.com/openwrt/packages.git "$NETBIRD_TMP/openwrt-packages"
	git -C "$NETBIRD_TMP/openwrt-packages" sparse-checkout set net/netbird
	mkdir -p ./package/netbird
	cp -a "$NETBIRD_TMP/openwrt-packages/net/netbird/." ./package/netbird/
fi

# OpenAppFilter is a three-package stack. Copy the package directories
# explicitly because the upstream repository has no top-level Makefile.
if [[ "${WRT_APPFILTER,,}" == "true" ]]; then
	OAF_TMP=$(mktemp -d)
	git clone --depth=1 --single-branch --branch master \
		"https://github.com/destan19/OpenAppFilter.git" "$OAF_TMP/OpenAppFilter"
	for OAF_PACKAGE in open-app-filter oaf luci-app-oaf; do
		if [ ! -d "$OAF_TMP/OpenAppFilter/$OAF_PACKAGE" ]; then
			echo "OpenAppFilter package directory missing: $OAF_PACKAGE" >&2
			exit 1
		fi
		rm -rf "./package/$OAF_PACKAGE"
		cp -a "$OAF_TMP/OpenAppFilter/$OAF_PACKAGE" ./package/
	done
	rm -rf "$OAF_TMP"
fi

# NSS status LuCI page. It only reads available NSS/ECM debugfs counters.
# The actual NSS firmware, host driver and ath11k/mac80211 NSS patches are
# supplied by the VIKINGYFY/immortalwrt base selected by the device workflow.
if [ -d ./package/qca-nss/nss-firmware ] && [ -d ./package/qca-nss/nss-wifi-drv ]; then
	echo "VIKING NSS firmware and host driver found in the base source tree."
else
	echo "VIKING NSS base packages are not present; luci-app-nss will remain monitor-only."
fi
NSS_TMP=$(mktemp -d)
git clone --depth=1 --single-branch --branch master \
	"https://github.com/yduke/luci-app-nss.git" "$NSS_TMP/luci-app-nss"
rm -rf ./package/luci-app-nss
mkdir -p ./package/luci-app-nss
cp -a "$NSS_TMP/luci-app-nss/Makefile" ./package/luci-app-nss/
cp -a "$NSS_TMP/luci-app-nss/htdocs" ./package/luci-app-nss/
cp -a "$NSS_TMP/luci-app-nss/root" ./package/luci-app-nss/
rm -rf "$NSS_TMP"

UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "uugamebooster" "xiaodoudou/luci-app-uugamebooster" "master" "pkg"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"

# 当前路由器使用的 SysTools 来自 LinkEase 应用扩展仓库。
UPDATE_PACKAGE "systools" "linkease/openwrt-app-actions" "main" "pkg"

# 1Panel LuCI 管理页。当前公开包位于 openwrt-app-actions 的嵌套目录，
# 直接提取 luci-app-istorepanel；找不到目录时让 CI 明确失败，避免生成
# 一个看似成功但缺少 1Panel 的固件。
UPDATE_NESTED_PACKAGE "luci-app-istorepanel" "linkease/openwrt-app-actions" "main" "applications/luci-app-istorepanel"

# iStore 商店及其任务组件来自同一仓库的嵌套软件包目录。
UPDATE_NESTED_PACKAGE "luci-app-store" "linkease/istore" "main" "luci/luci-app-store"
UPDATE_NESTED_PACKAGE "luci-lib-taskd" "linkease/istore" "main" "luci/luci-lib-taskd"
UPDATE_NESTED_PACKAGE "luci-lib-xterm" "linkease/istore" "main" "luci/luci-lib-xterm"
UPDATE_NESTED_PACKAGE "taskd" "linkease/istore" "main" "luci/taskd"

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"

UPDATE_PACKAGE "natmapt" "muink/openwrt-natmapt" "master"
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
