# 雅典娜软件清单核对

核对来源：`router-export-20261105-135612/packages/apk-installed-verbose.txt`。

版本号不做完全匹配。构建时优先使用 VIKINGYFY/immortalwrt 当前 feed 和脚本拉取的上游版本，目标是保留相同的功能和 LuCI 入口。

## 已纳入构建

| 当前软件 | 构建处理 |
| --- | --- |
| `appfilter`、`kmod-oaf`、`luci-app-oaf` | OpenAppFilter 三件套，已纳入 |
| `athena-led`、`luci-app-athena-led` | 雅典娜 LED，构建时从 `577090447/JDC-AX6600-Athena-LED-Controller` 根目录提取 |
| `docker`、`dockerd`、`docker-compose`、`luci-app-dockerman` | 显式选中 |
| `netbird`、`luci-app-netbird`、中文翻译 | 主程序来自 packages feed，LuCI 页面从 `looong-cat/luci-app-netbird` 提取 |
| `openlist`、`luci-app-openlist`、中文翻译 | 使用当前 feed 的包名，已移除旧的 `openlist2` 配置 |
| `luci-app-harbor-file` | 已纳入 |
| `qbittorrent`、`luci-app-qbittorrent` | 已纳入 |
| `uugamebooster`、`luci-app-uugamebooster` | 已纳入 |
| `vlmcsd`、`luci-app-vlmcsd` | 已纳入 |
| `fullconenat-sonic`、`luci-app-fullconenat-sonic` | VIKING 上游自带，已显式选中 |
| `rtp2httpd`、`luci-app-rtp2httpd` | 已显式选中 |
| `luci-app-package-manager` | 已显式选中，使用当前 LuCI feed |
| `luci-app-store`、`luci-lib-taskd`、`luci-lib-xterm`、`taskd` | 从 `linkease/istore` 提取，满足 iStore 商店页及其任务依赖 |
| `luci-app-systools` | 从 `linkease/openwrt-app-actions` 提取 |
| `luci-app-istorepanel` | 从 `linkease/openwrt-app-actions/applications/luci-app-istorepanel` 提取，默认进入固件；它提供 1Panel 的 LuCI 管理入口 |
| `luci-app-autoreboot`、`luci-app-gecoosac`、`luci-app-samba4`、`luci-app-upnp`、`luci-app-ttyd` | 已由通用配置或雅典娜配置纳入 |
| NSS 固件、Wi-Fi NSS 驱动、`luci-app-nss` | 功能主体跟随 VIKING 上游，监控页面单独拉取 |
| PassWall、OpenClash | 默认安装 |

## 编译但不默认安装

`luci-app-homeproxy` 和 `luci-app-passwall2` 设置为 `m`。它们会进入可生成的软件包集合，但不会写入默认 rootfs。

## 按约定排除

- ZeroTier：不纳入。
- 易有云文件管理相关的 `luci-app-linkease`：不纳入。
- WorkBuddy2API：不编译进固件，按需通过 Docker 部署。
- 1Panel：`luci-app-istorepanel` 默认纳入；它是 LuCI 管理包，实际 1Panel 容器由页面按需部署。

## 说明

`luci-app-store` 的源码已从 `linkease/istore` 的公开嵌套目录提取；它在编译时还会下载对应版本的 iStore UI 前端资源。`luci-app-package-manager` 和 `luci-app-systools` 也已纳入，提供软件包管理和系统维护能力。

NetBird 的 DNS、PassWall 标记和 dnsmasq `wt0` 冲突脚本会随固件安装，但不会自动启动；使用方法见 `README-SCRIPTS.md`。本机访问外网需要时可临时设置 `127.0.0.1:7897`，该地址不会写入固件或 GitHub Actions 配置。
