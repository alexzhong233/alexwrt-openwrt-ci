#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 统一的仓库克隆入口。
# 任何一次 clone 失败都直接中止构建：以前失败后会继续往下跑，make defconfig
# 静默丢弃找不到源码的包，最后产出一个"构建成功"但少插件的固件。
# 分支传空字符串时不加 --single-branch，供 sparse checkout 之类场景使用。
#
# 同一个仓库在一次构建里经常要被取多次（linkease/istore 有 4 个包、
# openwrt-app-actions 2 个、athena-led 控制器 2 个）。第一次克隆后留一份
# 缓存，后续直接本地复制，省掉重复的网络往返。
CLONE_CACHE_ROOT=${CLONE_CACHE_ROOT:-${TMPDIR:-/tmp}/wrt-clone-cache}
mkdir -p "$CLONE_CACHE_ROOT"

clone_repo() {
	local REPO=$1
	local BRANCH=$2
	local DEST=$3
	shift 3

	# 带额外参数的调用（sparse checkout 等）不走缓存。
	local CACHED=""
	if [ $# -eq 0 ]; then
		CACHED="$CLONE_CACHE_ROOT/$(printf '%s@%s' "$REPO" "${BRANCH:-HEAD}" | tr '/:' '__')"
		if [ -d "$CACHED" ]; then
			rm -rf "$DEST"
			mkdir -p "$(dirname "$DEST")"
			cp -a "$CACHED" "$DEST"
			return 0
		fi
	fi

	local -a ARGS=(--depth=1)
	if [ -n "$BRANCH" ]; then
		ARGS+=(--single-branch --branch "$BRANCH")
	fi

	if ! git clone "${ARGS[@]}" "$@" "https://github.com/$REPO.git" "$DEST"; then
		echo "::error::Failed to clone $REPO (branch: ${BRANCH:-default}) into $DEST" >&2
		rm -rf "$DEST"
		exit 1
	fi

	if [ -n "$CACHED" ]; then
		rm -rf "$CACHED"
		cp -a "$DEST" "$CACHED"
	fi
}

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

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 这类仓库根目录不是包本身，只提取匹配的子目录。
		# 必须克隆到临时目录：当仓库名与包名相同时（例如
		# xiaodoudou/luci-app-uugamebooster），直接克隆到 package/<仓库名>
		# 会让 cp 把目录拷到自己内部，随后 rm -rf 连提取出来的包一起删掉，
		# 最终 make defconfig 静默丢弃该包，固件里就没有它。
		local PKG_TMP EXTRACTED
		PKG_TMP=$(mktemp -d)
		clone_repo "$PKG_REPO" "$PKG_BRANCH" "$PKG_TMP/$REPO_NAME"
		find "$PKG_TMP/$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf "$PKG_TMP"

		EXTRACTED=$(find ./package -maxdepth 3 -type d -iname "*$PKG_NAME*" 2>/dev/null | head -1)
		if [ -z "$EXTRACTED" ]; then
			echo "::error::pkg extraction produced nothing for $PKG_NAME from $PKG_REPO (目录结构可能已变更)" >&2
			exit 1
		fi
	else
		clone_repo "$PKG_REPO" "$PKG_BRANCH" "$REPO_PATH"
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
	clone_repo "$PKG_REPO" "$PKG_BRANCH" "$TMP_DIR/src"

	if [ ! -f "$TMP_DIR/src/Makefile" ]; then
		echo "::error::Top-level Makefile missing in $PKG_REPO" >&2
		rm -rf "$TMP_DIR"
		exit 1
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
	clone_repo "$PKG_REPO" "$PKG_BRANCH" "$TMP_DIR/src"

	if [ ! -f "$TMP_DIR/src/$PKG_SOURCE_DIR/Makefile" ]; then
		echo "::error::Nested package Makefile missing in $PKG_REPO/$PKG_SOURCE_DIR" >&2
		rm -rf "$TMP_DIR"
		exit 1
	fi

	rm -rf "./package/$PKG_DIR"
	mkdir -p "./package/$PKG_DIR"
	cp -a "$TMP_DIR/src/$PKG_SOURCE_DIR/." "./package/$PKG_DIR/"
	rm -rf "$TMP_DIR"
}

# 用法：UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件" "额外要清理的旧包名，可选"
# 第5个参数会连同包名一起从 feeds 里删掉同名目录，避免同一插件出现两份、coremark 报错。
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

# Dockerman 和 1Panel 面板都依赖 luci-lib-docker，而现在的 luci feed 只留下
# luci-app-dockerman / luci-app-docker，早就不带这个库了。缺了它，.config 里
# 两个面板照样选中，等到打包 rootfs 时 apk 才会报 "luci-lib-docker (no such
# package)"。只能从 lisaac 的原仓库取。
UPDATE_NESTED_PACKAGE "luci-lib-docker" "lisaac/luci-lib-docker" "master" "collections/luci-lib-docker"
# 与 Dockerman 同样的 APK 版本号问题：上游写的是 v0.3.4。
DOCKER_LIB_MAKEFILE="./package/luci-lib-docker/Makefile"
if [ -f "$DOCKER_LIB_MAKEFILE" ]; then
	sed -i 's/^PKG_VERSION:=v/PKG_VERSION:=/' "$DOCKER_LIB_MAKEFILE"
fi

# 雅典娜 RE-CS-02 LED：使用控制器仓库根目录下的两个 OpenWrt 软件包。
# 该仓库没有 pkg/ 父目录，因此分别提取 athena-led 和 luci-app-athena-led。
#
# 先把上游 package/emortal 自带的同名包删掉。它是 1.0 版（Lua CBI 界面，
# conffiles 里声明 /etc/config/athena_led，还自带 etc/init.d/athena_led），
# 和下面拷入的 2.5.0 版同名；scan.mk 扫到 package/emortal/luci-app-athena-led
# 时会覆盖 package/luci-app-athena-led，于是固件里装的一直是这个老包。
# 它和 athena-led 2.5.0 本体抢同样的两个文件，apk 直接拒绝安装整个 rootfs：
#   ERROR: luci-app-athena-led-1.0-r20260610: trying to overwrite
#     etc/config/athena_led owned by athena-led-2.5.0-r1
# 删掉上游那份，让配套的 2.5.0 界面生效（它只装界面，不碰 config/init）。
rm -rf ./package/emortal/luci-app-athena-led

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
	clone_repo "openwrt/packages" "" "$NETBIRD_TMP/openwrt-packages" --filter=blob:none --sparse
	if ! git -C "$NETBIRD_TMP/openwrt-packages" sparse-checkout set net/netbird; then
		echo "::error::Failed to sparse-checkout net/netbird from openwrt/packages" >&2
		exit 1
	fi
	mkdir -p ./package/netbird
	cp -a "$NETBIRD_TMP/openwrt-packages/net/netbird/." ./package/netbird/
	if [ ! -f ./package/netbird/Makefile ]; then
		echo "::error::netbird Makefile missing after sparse checkout" >&2
		exit 1
	fi
fi

# OpenAppFilter is a three-package stack (appfilter / kmod-oaf / luci-app-oaf).
# Copy the package directories explicitly because the upstream repository has no
# top-level Makefile.
#
# Two things taken from 577090447/ax6600.emmc's UPDATE_PACKAGE:
#
# 1. Drop the feeds copies of the same packages first. The luci feed still ships
#    the retired luci-app-appfilter (6.1.4), which targets the pre-7.0 daemon and
#    pulls "+appfilter" along. A stale tree next to our packages is how a build
#    ends up with a daemon registering the old "appfilter" ubus object while the
#    UI calls "fwx": status fields stay blank and the online feature list cannot
#    be refreshed. Removing it keeps a single source of truth.
# 2. Refuse anything older than 7.0. The 7.0 rewrite is what renamed the ubus
#    service to fwx (open-app-filter/src/fwx_ubus.c); a checkout without that
#    file cannot satisfy luci-app-oaf and would silently ship a broken pair.
if [[ "${WRT_APPFILTER,,}" == "true" ]]; then
	for OAF_FEED in ./feeds/luci ./feeds/packages; do
		[ -d "$OAF_FEED" ] || continue
		while IFS= read -r OAF_STALE; do
			[ -n "$OAF_STALE" ] || continue
			echo "Dropping stale feed package: $OAF_STALE"
			rm -rf "$OAF_STALE"
		done < <(find "$OAF_FEED" -maxdepth 3 -type d \( -iname '*appfilter*' -o -iname '*oaf*' -o -iname '*open-app-filter*' \) 2>/dev/null)
	done
	# feeds install left symlinks behind; clear the ones whose target just went away.
	find ./package/feeds -maxdepth 2 -xtype l -delete 2>/dev/null || true

	OAF_TMP=$(mktemp -d)
	clone_repo "destan19/OpenAppFilter" "master" "$OAF_TMP/OpenAppFilter"
	if [ ! -f "$OAF_TMP/OpenAppFilter/open-app-filter/src/fwx_ubus.c" ]; then
		echo "::error::OpenAppFilter checkout predates 7.0 (open-app-filter/src/fwx_ubus.c missing); refusing to build a daemon that cannot talk to luci-app-oaf" >&2
		exit 1
	fi
	OAF_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$OAF_TMP/OpenAppFilter/open-app-filter/Makefile" | head -1)
	OAF_LUCI_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$OAF_TMP/OpenAppFilter/luci-app-oaf/Makefile" | head -1)
	echo "OpenAppFilter: daemon ${OAF_VERSION:-unknown}, luci ${OAF_LUCI_VERSION:-unknown} (ubus service fwx)"
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

# NSS 走上游的 nss-wifi-drv：它自己 boot NSS 固件，用 wifili 把无线帧直接送进
# NSS 硬件（日志里的 "wifili: radio 0 rxdma"），是真正生效的无线加速。
# 这里只做存在性检查，装不装由 Config 决定。
#
# 以前还会 clone yduke/luci-app-nss 装上监控页，但那个页面读的是
# /sys/kernel/debug/qca-nss-drv/stats 和 /sys/kernel/debug/ecm/，只有
# qca-nss-drv + ecm 那套数据平面才会创建这两个目录。本上游用 nss-wifi-drv，
# 目录永远不存在，页面就会一直显示「未加载」，让人误以为加速没工作。
# 真实状态在 /sys/bus/platform/devices/39000000.nss/state（ready=1 / peers=N /
# wlan=3）和 logread -e nss-wifi，所以不再装那个页面。
if [ -d ./package/qca-nss/nss-wifi-drv ]; then
	echo "NSS Wi-Fi offload driver present (nss-wifi-drv)."
	echo "  live state: /sys/bus/platform/devices/39000000.nss/state"
elif [ -d ./package/qca-nss/qca-nss-drv ]; then
	echo "::warning::Base tree carries the qca-nss-drv data plane instead of nss-wifi-drv; Wi-Fi frames would fall back to the host path." >&2
else
	echo "::warning::No NSS packages in the base tree; Wi-Fi will run on the host path." >&2
fi

UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "uugamebooster" "xiaodoudou/luci-app-uugamebooster" "master" "pkg"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"

# 当前路由器使用的 SysTools 来自 LinkEase 应用扩展仓库。
UPDATE_PACKAGE "systools" "linkease/openwrt-app-actions" "main" "pkg"

# luci.mk 只认 LUCI_LANG.zh_Hans，再经 LUCI_LC_ALIAS.zh_Hans 映射成 -zh-cn
# 的包名。openwrt-app-actions 里这个包还用旧式 po/zh-cn 目录名，对不上就会
# 跳过 i18n 包，配置里的 CONFIG_PACKAGE_luci-i18n-systools-zh-cn 被 make
# defconfig 静默丢弃。改名后中文翻译才真的进固件。
SYSTOOLS_PO="./package/luci-app-systools/po"
if [ -d "$SYSTOOLS_PO/zh-cn" ] && [ ! -d "$SYSTOOLS_PO/zh_Hans" ]; then
	mv "$SYSTOOLS_PO/zh-cn" "$SYSTOOLS_PO/zh_Hans"
	echo "Renamed systools po/zh-cn -> po/zh_Hans so luci.mk emits the i18n package"
fi

# SysTools 的两个依赖任何 feed 都没有，缺了会在打包 rootfs 时挂掉：
#   speedtestcli  —— 同仓 applications/speedtestcli，装的是预编译二进制
#   luci-lib-iform —— LinkEase 的 NAS LuCI 仓库，systools 要求 >=1.1
UPDATE_PACKAGE "speedtestcli" "linkease/openwrt-app-actions" "main" "pkg"
UPDATE_NESTED_PACKAGE "luci-lib-iform" "linkease/nas-packages-luci" "main" "luci/luci-lib-iform"


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

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
