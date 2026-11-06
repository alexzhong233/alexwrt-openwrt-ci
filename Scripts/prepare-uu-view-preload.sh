#!/bin/bash
# SPDX-License-Identifier: MIT
#
# 为 luci-app-uugamebooster 补齐 uu-view 的 LD_PRELOAD shim。
#
# 上游的“设备列表”功能只在选中的设备对 UU 插件可见，它靠两种手段伪造视图：
# bind mount 覆盖 dhcp.leases 和 nmp_client_list，以及 LD_PRELOAD 劫持插件
# 对 /proc/net/arp 和 "ip -6 neigh show" 的读取。后两条挂载改不了，必须有
# uu-view-preload-<arch>.so 注入插件进程才拦得住。
#
# 这个 .so 由 tools/build-preload.sh 用 zig 交叉编译产出。它不在 OpenWrt 的
# 构建流程里，SDK 也做不出来（缺交叉工具链），所以直接 make 出来的包一定没有
# 这些 shim，结果是 ARP 表和 IPv6 邻居表仍然暴露全屋设备，过滤等于没做。
#
# 这里补上这一步：取上游源码 → 下 zig → 编出五个架构的 shim → 塞进包的 root。
#
# 任何一环失败都只 warning 不中断构建：shim 是增强功能，不该让三小时的编译作废。

set -e

PKG_NAME="luci-app-uugamebooster"
PKG_DIR="$(pwd)/package/$PKG_NAME"
REPO_URL="https://github.com/xiaodoudou/luci-app-uugamebooster"
REPO_BRANCH="master"
ZIG_VERSION="0.13.0"
PRELOAD_DIR="$PKG_DIR/root/usr/lib/uuplugin"
EXPECTED_SHIMS=5

warn() { echo "::warning::$*"; }

# 包没被选中时整个步骤无事可做
if [ ! -d "$PKG_DIR" ]; then
	echo "$PKG_NAME 未启用，跳过 uu-view shim"
	exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 包的 Makefile 在子目录里，tools/ 和 src/ 不在提取范围内，需要单独取一次
if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP/src" >/dev/null 2>&1; then
	warn "拉取 $REPO_URL 失败，uu-view shim 未生成：设备列表只能过滤 bind mount 覆盖的两个数据源"
	exit 0
fi

# zig 自带全架构 musl 工具链，是上游指定的编译方式；系统源里没有它。
# 47 MB，GitHub runner 上通常几十秒；超时给足 10 分钟，别在慢节点上误判失败。
if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 600 \
	"https://ziglang.org/download/$ZIG_VERSION/zig-linux-x86_64-$ZIG_VERSION.tar.xz" \
	-o "$TMP/zig.tar.xz"; then
	warn "zig 下载失败，uu-view shim 未生成：设备列表只能过滤 bind mount 覆盖的两个数据源"
	exit 0
fi

mkdir -p "$TMP/zig"
if ! tar xf "$TMP/zig.tar.xz" -C "$TMP/zig" --strip-components=1; then
	warn "zig 解压失败，uu-view shim 未生成"
	exit 0
fi

# build-preload.sh 通过 command -v 找 zig，把解压目录挂到 PATH 前面即可
export PATH="$TMP/zig:$PATH"
if ! command -v zig >/dev/null 2>&1; then
	warn "zig 不可执行，uu-view shim 未生成"
	exit 0
fi

mkdir -p "$PRELOAD_DIR"
echo "编译 uu-view shim 到 $PRELOAD_DIR"
if ! sh "$TMP/src/tools/build-preload.sh" "$PRELOAD_DIR"; then
	warn "build-preload.sh 执行失败，uu-view shim 未生成"
	exit 0
fi

# 产物数量对不上说明有架构没编出来（或上游改了命名），让日志显眼一点
BUILT=$(find "$PRELOAD_DIR" -maxdepth 1 -type f -name 'uu-view-preload-*.so' | wc -l)
ls -l "$PRELOAD_DIR"
if [ "$BUILT" -ne "$EXPECTED_SHIMS" ]; then
	warn "uu-view shim 只生成 $BUILT/$EXPECTED_SHIMS 个，缺失架构的设备列表过滤会降级"
else
	echo "uu-view shim 就绪：$BUILT 个架构"
fi
