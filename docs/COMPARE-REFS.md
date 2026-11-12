# alexwrt 与三个参考仓库的对比

对比对象：

| 仓库 | 角色 |
|---|---|
| `VIKINGYFY/OpenWRT-CI` | 本仓库 fork 的**基线**。整套 CI 框架（WRT-CORE、Scripts、Config）来自这里 |
| `577090447/IPQ60XX-WIFI-YES` | 别人的**精简版**同款框架，只编 IPQ60XX 单机型 |
| `577090447/ax6600.emmc` | 上一项的**加料版**，多了 `files/` 目录把整机配置烤进固件 |
| `alexzhong233/alexwrt-openwrt-ci` | 本仓库的**应用型**固件，针对京东云雅典娜 RE-CS-02 |

一句话结论：四者是**同一套框架的三个分支**——上游是"一次编一整排机型"的平台包，577090447 是"只编我这台"，本仓库是"只编这一台 + 塞满应用 + 注入定制脚本"。

---

## 1. 仓库结构对比

| 维度 | VIKINGYFY 上游 | 577090447/IPQ60XX | 577090447/ax6600.emmc | alexwrt |
|---|---|---|---|---|
| 工作流数量 | 10 个（AIROHA/MTK/OWRT/QCA/QCB/WRT-CORE/WRT-TEST/Auto-Clean/Cache-Clean） | 6 个 | 3 个（QCA-ALL/WRT-CORE/WRT-TEST） | 10 个 + 自建 `ALEXWRT.yml` |
| Config 数量 | 15 个（覆盖全平台） | 3 个（GENERAL/IPQ60XX-WIFI-YES/TEST） | 8 个 | 15 个（上游全部 + `IPQ60XX-OWRT-WIFI-YES`；原 `-OVERRIDES` 已并入该文件） |
| `files/` 注入目录 | 无 | 无 | **有**（5 个文件） | **有**（`Files/RE-CS-02`，12 个文件） |
| WRT-CORE 版本 | 最新（含 cache-rollover 缓存滚动） | 最新 | **较旧**（去掉了 cache-rollover，`WRT_TEST` 还是 string） | 最新 + 3 个新输入 |
| 上游源码 | 自己提供 | `577090447/immortalwrt` `main` | 同左 | `VIKINGYFY/immortalwrt` `owrt` |
| 自动触发 | 每天（Auto-Clean → QCA-ALL 链式） | 同左 | 同左 | 自建的 `cron: 0 22 * * *` + 手动 |

本仓库相对上游 `VIKINGYFY/OpenWRT-CI` 的真实改动（已逐文件 diff 核对）：

| 文件 | 改动量 | 内容 |
|---|---|---|
| `.github/workflows/ALEXWRT.yml` | 新增 | 雅典娜专用入口 |
| `.github/workflows/WRT-CORE.yml` | +29 行 | 新增 `WRT_EXTRA_CONFIG`/`WRT_FILES`/`WRT_APPFILTER` 三个输入，新增 `Install Custom Files` 步骤，支持追加覆盖配置 |
| `Scripts/Packages.sh` | +166 行 | 新增 `UPDATE_TOPLEVEL_PACKAGE`/`UPDATE_NESTED_PACKAGE` 两个函数 + 大量自建包 |
| `Scripts/Settings.sh` | 9 行 | `WRT_WORD` 为空时改成开放 WiFi（上游无条件写密码） |
| `Config/IPQ60XX-OWRT-WIFI-YES.txt` | 新增 | 只选 RE-CS-02 + 应用清单 + 板级覆盖（homeproxy/passwall2 =m、diskman、NSS）；原独立的 `-OVERRIDES.txt` 已于 11-08 并入 |
| `Files/RE-CS-02/**` | 新增 12 个 | uci-defaults 无线初始化 + NetBird 系列脚本 |
| `Config/GENERAL.txt`、`Config/IPQ60XX-WIFI-YES.txt`、`QCA-ALL.yml`、`WRT-TEST.yml`、`Handles.sh` | **0 改动** | 与上游完全一致 |

---

## 2. 编译出来的固件差在哪

### 2.1 机型覆盖

| 项目 | 固件里包含的机型 |
|---|---|
| 上游 QCA-ALL（`IPQ60XX-WIFI-YES`） | **18 个** IPQ60XX 机型全选（360v6、AX18、AX5、AX1800、AX9000 系列……），一个平台包里塞一整排设备 |
| 577090447 两个仓库 | 只启用 `jdcloud_re-cs-02`，其余 17 个全部 `=n` |
| ALEXWRT | 只启用 `jdcloud_re-cs-02` |

这就是为什么上游 Release 正文写着"这是个平台固件包，内含多个设备"，而本仓库只出一个 `.bin`。

### 2.2 出厂默认值

| 项目 | 上游 | 577090447/IPQ60XX | ax6600.emmc | alexwrt |
|---|---|---|---|---|
| 主题 | 按各 workflow 传参 | vantage | vantage | **aurora** |
| 主机名 | 按传参 | OpenWRT | OpenWRT | **alexwrt** |
| 管理 IP | 按传参 | 192.168.100.1 | 192.168.100.1 | **192.168.88.1** |
| WiFi 名 | 按传参 | OpenWRT | `OpenWRT-2.4G` / `OpenWRT-5G`（静态文件写死） | **`alexwrt-jdcloud-2.4g` / `-5.2g` / `-5.8g`** |
| WiFi 密码 | 按传参 | 1234567890 | 1234567890 | **12345678** |
| WiFi 信道 / HT | 按传参 | 自动 | 静态写死 | **2.4G 5/HE40、5.2G(PCIe) 36/HE160、5.8G(SoC) 161/HE80，国家码 US** |
| WiFi 设置方式 | sed 改 `mac80211.uc` | 同左 | **整份 `/etc/config/wireless` 覆盖** | **构建期补丁改 `mac80211.uc` 的 SSID / 国家码 / 信道 / htmode 兜底值** |
| 软件源 | 上游默认 | 上游默认 | **换成 NJU 镜像 + iStore 源**（`files/etc/apk/repositories.d/distfeeds.list`） | 上游默认 + NJU 追加（`customfeeds.list`） |

WiFi 这一行的实现差异值得注意：ax6600.emmc 是"静态覆盖"，好处是绝对可控，坏处是上游改了无线默认值就跟不上了；当前方案是"构建期改生成器兜底值"，既能钉住 SSID / 国家码 / 信道 / htmode，又不会在开机后覆盖用户配置（`radio_exists()` 会跳过已存在的 radio）。

### 2.3 应用清单

| 应用 | 上游 GENERAL | 577090447/IPQ60XX | alexwrt |
|---|---|---|---|
| HomeProxy | `=y` | `=n` | `=m`（可装不预装） |
| OpenClash | 无 | `=y` | `=y` |
| PassWall / PassWall2 | 无 | 无 | `=y` / `=m` |
| Dockerman + Docker | 无 | `=y`（dockerd、compose 全套） | `=y`（dockerd、compose 全套） |
| 1Panel（istorepanel） | 无 | `luci-app-store` iStore | `=y` |
| NetBird | 无 | 无 | `=y` |
| OpenList / qBittorrent / Harbor File | 无 | 无 | `=y` |
| UU 加速 / vlmcsd(KMS) | 无 | 无 | `=y` |
| OpenAppFilter（oaf） | 无 | 无 | `=y` |
| NSS 固件 + WiFi 驱动 | 由源码提供 | 未显式选 | `=y` 显式选 + `luci-app-nss` 监控页 |
| rtp2httpd | 无 | `=y` | `=y` |
| athena-led | 无 | **显式 `=n` 关掉** | `=y`（从 577090447 的 LED 控制器仓库提取） |
| mini-diskmanager | `=y` | `=n`（改用 diskman） | `=n`（改用 diskman） |

本固件本质上是一台**小型 NAS + 旁路由**：Docker、1Panel、OpenList、qBittorrent、Harbor 全在里面，再叠 PassWall/OpenClash/NetBird 三套网络方案。上游和 577090447 的固件都是"干净路由"（577090447 带 Docker 但除此之外没有 NAS 应用栈），安装包体积会小很多，开机内存占用也低不少。

### 2.4 额外注入的内容

`Files/RE-CS-02` 里的 7 个文件是另外三个仓库都没有的：

- `etc/apk/repositories.d/customfeeds.list` —— 追加 NJU 镜像源（`distfeeds.list` 仍由 base-files 生成官方源）
- `etc/init.d/netbird-passwall-compat-watch` —— 兼容守护服务（`watch` 模式才启用）
- `usr/bin/netbird-compat-ctl` —— 守护的开关/状态/日志入口，LuCI「服务 → NetBird 工具」调它
- `usr/bin/netbird-passwall-compat.sh` —— 规则实现本体（守护以 `--once` 调它）
- `usr/bin/netbird-passwall-compat-watch.sh` —— 守护主循环
- `usr/share/alexwrt/*.md` —— 脚本说明

早期那套 WiFi 首启脚本（`99-alexwrt-wireless`）和 `--disable-dns` 包装（`98-netbird-default-nodns`）已在 2026-11-08 全部删除。现在无线仍由上游 `/sbin/wifi config` 生成，只在构建期改 `mac80211.uc` 的兜底值：SSID 换成 `alexwrt-jdcloud-<频段>`，国家码 `US`，2.4G `5/HE40`、PCIe `36/HE160`、SoC 5G `161/HE80`，运行时不碰用户配置。

---

## 3. 为什么坑都集中在自建包这边

上游固件里**没有 Docker、没有 vlmcsd、没有 OpenAppFilter、没有 NetBird**（577090447 两个仓库的 `Config/GENERAL.txt` 都显式选了 `docker`/`dockerd`/`luci-app-dockerman`，`ax6600.emmc` 还带 `docker-compose`，所以它有 Docker；但它除 Docker 之外没有 NAS 应用栈）。多引入的每一个自建包，都要自己保证它能过 `apk` 这一关：

| 已踩过的坑 | 现象 | 根因 |
|---|---|---|
| Dockerman | APK 版本校验失败 | 上游写 `PKG_VERSION:=v0.5.26`，`v` 前缀非法 |
| vlmcsd | `apk mkpkg` 报 `package version is invalid` | 上游写 `PKG_VERSION=svn1112`，`svn` 前缀非法 |
| vlmcsd | 多文件传给同一个 `gcc -c -o` | 旧版 GNUmakefile 和 ccache 包装器不兼容 |

> 2026-11-08 补：vlmcsd 那两个坑已经不用再踩了 —— vlmcsd（连同 diskman、
> qbittorrent、sing-box、passwall、openclash、openlist）改回官方 feeds 的版本，
> vlmcsd 的 `Build/Compile` 替换和它自己的 `PKG_VERSION` 剥离补丁都已删除。
> Dockerman 仍是 lisaac 0.5.26（要容器内文件管理），所以第一行那个 `v0.5.26`
> 前缀剥离补丁还在。仍然第三方的有 dockerman、oaf（destan19）和
> luci-lib-docker（lisaac，dockerman 和 istorepanel 都要）。

共同规律：**新 APK 打包器要求版本号必须以数字开头**，而很多老包还停留在 opkg 时代（opkg 不校验）。以后再加自建包，先看一眼它的 `PKG_VERSION` 是不是字母开头。

---

## 4. 两个可选优化（均已落地）

1. **[已完成] 固件文件名带 `-none-`**。`WRT-CORE` 用配置名末尾的 `WIFI-YES`/`WIFI-NO` 决定文件名里的无线标识，原来的 `IPQ60XX-ALEXWRT` 不匹配，于是 `WRT_WIFI=none`。现已把配置改名为 `IPQ60XX-OWRT-WIFI-YES`，固件文件名会变成 `...-jdcloud_re-cs-02-squashfs-sysupgrade-VIKINGYFY-owrt-WIFI-YES-<日期>.bin`。
2. **[已调整] 国内镜像源**。曾参考 ax6600.emmc 用 `Files/RE-CS-02/etc/apk/repositories.d/distfeeds.list` 整份覆盖官方源（NJU + iStore）。2026-11-06 改成官方推荐做法：`distfeeds.list` 交回 base-files 自动生成（官方源），NJU 镜像写在 `customfeeds.list` 里**追加**，两份并存；iStore 的源由 `luci-app-store` 自带的 `compat.list` 提供，不再重复。

## 5. 工作流精简

参考仓库把「所有平台」都挂在同一份 CI 里，会一次性列出 10 个工作流。本仓库只编 `jdcloud_re-cs-02`，因此删除了与其它平台相关的工作流：

- 删除：`AIROHA-ALL.yml`、`MTK-ALL.yml`、`OWRT-ALL.yml`、`QCA-ALL.yml`、`QCB-ALL.yml`、`WRT-TEST.yml`
- 保留：`ALEXWRT.yml`（唯一编译入口）、`WRT-CORE.yml`（被调用的核心，自身无触发器）、`Auto-Clean.yml`（每天清理旧 Release 与旧运行记录）、`Cache-Clean.yml`（每周清理 ccache）

`Config/` 下其它平台的配置文件暂时保留（不参与编译，不影响任何流程），需要时可以随时恢复对应工作流。

