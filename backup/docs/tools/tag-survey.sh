#!/bin/bash
# SPDX-License-Identifier: MIT
#
# 第三方仓库 tag 普查工具（只读，不参与构建；故意放在 docs/ 而不是 Scripts/，
# 因为 Scripts/*.sh 会在 Custom Packages 阶段被构建流程逐个执行）。
#
# 用途：对 Scripts/Packages.sh 里引用的每个仓库，比对「配置分支的 HEAD SHA」
# 与「最新 tag 的 SHA」，输出 SAME / DIFF / NO-TAGS。
#
# 用法：
#   bash docs/tools/tag-survey.sh            # 输出到 stdout
#   bash docs/tools/tag-survey.sh > out.txt
#
# 说明：
#   - 每个仓库只发一次 git ls-remote，同时拿到 heads 和 tags，比 GitHub API 省
#     得多（未认证 API 每小时 60 次，几十个仓库一轮就打满）。
#   - 最新 tag 用 sort -V 取，不能按字典序（v5.3.4-r9 > v5.3.4-r15 是错的）。
#   - 脚本自身不带代理参数：本机若需要代理，请在环境里配 http_proxy。

set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PACKAGES="$REPO_ROOT/Scripts/Packages.sh"

[ -f "$PACKAGES" ] || { echo "找不到 $PACKAGES" >&2; exit 1; }

# 从 UPDATE_*PACKAGE "名字" "owner/repo" "分支" ... 里取出 (repo, branch) 对
pairs() {
	sed -n 's/^UPDATE_[A-Z_]*PACKAGE[[:space:]]\{1,\}"[^"]*"[[:space:]]\{1,\}"\([^"]*\)"[[:space:]]\{1,\}"\([^"]*\)".*/\1 \2/p' "$PACKAGES" |
		awk 'NF==2 && $1 ~ /\//' |
		awk '!seen[$0]++'
}

probe() {
	local repo=$1 br=$2 raw tags cnt lt ltsha brsha rel
	raw=$(git ls-remote --refs "https://github.com/$repo" 2>/dev/null | tr -d '\r')
	[ -n "$raw" ] || { echo "$repo|$br|ERROR||||"; return; }

	tags=$(printf '%s\n' "$raw" | awk '$2 ~ /^refs\/tags\// {sub("refs/tags/","",$2); print $1" "$2}')
	[ -n "$tags" ] || { echo "$repo|$br|NO-TAGS||||"; return; }

	cnt=$(printf '%s\n' "$tags" | wc -l | tr -d ' ')
	lt=$(printf '%s\n' "$tags" | awk '{print $2}' | sort -V | tail -1)
	ltsha=$(printf '%s\n' "$tags" | awk -v t="$lt" '$2==t {print $1}' | head -1)
	brsha=$(printf '%s\n' "$raw" | awk -v b="refs/heads/$br" '$2==b {print $1}' | head -1)

	if [ -z "$brsha" ]; then
		rel="NO-BRANCH"
	elif [ "$brsha" = "$ltsha" ]; then
		rel="SAME"
	else
		rel="DIFF"
	fi
	echo "$repo|$br|$rel|$cnt|$lt|${brsha:0:7}|${ltsha:0:7}"
}

# 自身可被 xargs 回调：不用 export -f，Git Bash 的 xargs 在函数导出场景会
# 触发 "bc_ctl.arg_max >= LINE_MAX" 断言崩溃。
if [ "${1:-}" = "--probe" ]; then
	probe "$2" "$3"
	exit 0
fi

# 并发 8 路，几十个仓库一两分钟跑完
pairs | xargs -P 8 -n 2 bash "$0" --probe
