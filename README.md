# niubiAlex 雅典娜 RE-CS-02 固件

京东云雅典娜 `jdcloud_re-cs-02` 的个人 OpenWrt 构建，源码取自 `VIKINGYFY/immortalwrt` 的 `owrt` 分支。每天北京时间 06:00 自动编译，也可以在 Actions 页面手动运行。

- 后台地址：`192.168.88.1`
- root 密码：不预设，首次登录后自行设置
- 固件信息里的时间是编译开始时间，方便核对上游源码提交时间

## 构建入口

| 项目 | 位置 |
|---|---|
| 工作流 | `.github/workflows/NIUBIALEX.yml`（调度入口）、`WRT-CORE.yml`（实际编译，被调用） |
| 设备配置 | `Config/IPQ60XX-NIUBIALEX-WIFI-YES.txt` |
| 追加配置 | `Config/IPQ60XX-NIUBIALEX-OVERRIDES.txt` |
| 软件包处理 | `Scripts/Packages.sh` |
| 构建期设置 | `Scripts/Settings.sh`（SSID/密码/后台地址）、`Scripts/Handles.sh`（主题与插件修补） |
| 固件文件注入 | `Files/RE-CS-02/` |

手动运行有两个入参：`PACKAGE`（每行一个额外 `CONFIG_PACKAGE_*`）和 `TEST`（只生成配置、不编译固件）。

配置名结尾的 `-WIFI-YES` 不能省。`WRT-CORE` 从配置名末尾取 WIFI 标记写进固件文件名，不带后缀会变成 `...-none-<日期>.bin`。

### 编译期断言

`Scripts/Packages.sh` 里每次 `git clone` 都走统一的 `clone_repo`，任何一个仓库拉不到就直接中断构建，不再带着缺失的包往下编。`UPDATE_PACKAGE` 的 `pkg` 提取模式还会检查提取结果是否为空。

`WRT-CORE` 在 `make defconfig` 之后有一步 `Verify Package Selection`，把配置里要求 `=y` 的包和最终 `.config` 逐条比对：

- **自建包整行消失**（`Scripts/Packages.sh` 里 clone 的那些）→ 直接失败，因为这说明克隆或目录提取没成功。
- **依赖不满足 / 被降级成 `=m` / 平台本来就没有**（例如 `kmod-*`）→ 只打 `::warning::`，不阻断构建，日志里能看到完整清单。

确属正常、不想每次告警的包，写进 `Config/verify-ignore.txt`（一行一个包名，文件不存在也没关系）。

## Wi-Fi 默认值

| 频段 | SSID | 信道 | htmode |
|---|---|---|---|
| 板载 2.4 GHz | `niubiAlex` | 5 | HE40 |
| 板载 5 GHz | `niubiAlex` | 161 | HE80 |
| PCIe / 5.2 GHz | `niubiAlexGaming` | 36 | HE160 |

默认密码 `88888888`，首次启动后建议修改。

SSID 和密码来自 `NIUBIALEX.yml` 的 `WRT_SSID` / `WRT_WORD`：编译时 `Scripts/Settings.sh` 把值写进首启脚本 `Files/RE-CS-02/etc/uci-defaults/99-niubialex-wireless` 的占位符，PCIe 频段自动加 `Gaming` 后缀，密码留空则生成开放网络。信道和 `htmode` 固定在这个首启脚本里。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译，页面在“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速、KMS。
- Docker、Docker Compose、1Panel 管理页 `luci-app-istorepanel`（容器本体由页面按需安装）、NetBird LuCI、FullConeNAT、RTP2HTTPD、软件包管理器、SysTools。
- NSS：`nss-firmware`、`kmod-nss-wifi-drv`、`ATH11K_NSS_WIFI` 与 ath11k/mac80211 NSS 补丁都来自上游源码；`luci-app-nss` 只是“状态 -> NPU (NSS) Status”监控页，不含驱动，不负责开启 NSS。
- 默认进 rootfs：NetBird、PassWall、OpenClash、Dockerman。HomeProxy 和 PassWall2 只编译为可安装模块。
- 不进固件：ZeroTier、易有云文件管理器、WorkBuddy2API（后者按需用 Docker 部署）。
- 首次启动会为 `netbird up` 安装默认禁用 DNS 的包装器，`netbird up --disable-dns=false` 可恢复。

软件包在 CI 里由 `Scripts/Packages.sh` 下载进编译树，仓库不保存编译好的 `.ipk`。脚本装到 `/usr/bin/`，说明文档装到 `/usr/share/niubiAlex/`，都不注册为常驻服务。逐包核对见 [docs/SOFTWARE-AUDIT.md](docs/SOFTWARE-AUDIT.md)。

## 软件源与固件文件

- 软件源走国内镜像：`Files/RE-CS-02/etc/apk/repositories.d/distfeeds.list` 整体覆盖 `/etc/apk/repositories.d/distfeeds.list`，指向南京大学镜像（NJU）加 iStore。它在 base-files 生成默认源之后注入，所以优先于官方源生效。
- 要加自己的源请写 `/etc/apk/repositories.d/customfeeds.list`，直接改 `distfeeds.list` 会在固件升级后被覆盖。
- 每次编译产出两个镜像：`...-squashfs-factory.bin`（首次刷机/救砖，走 U-Boot 或原厂 web 后台）和 `...-squashfs-sysupgrade.bin`（系统内升级）。两者内容一致，只是封装不同。

## 脚本

固件里的脚本都在 `/usr/bin/`，**默认不启动、不 enable**，只在明确执行命令后才检查或修改配置。遇到问题时先跑诊断，再按结果选修复脚本，不要为了“预防”把它们全部跑一遍。

推荐顺序：`netbird-passwall-diagnose.sh` → `netbird-dns-guard.sh check` → 确认需要才 `apply` → `netbird-passwall-lan-fix.sh check` → 看过备份再做 `apply` → 升级前 `export-router-state.sh`。

### netbird-passwall-compat.sh

处理 NetBird 原生 nftables 链与 PassWall 标记规则的冲突。动态查找 PassWall 当前的 `meta mark set` 值和 NetBird 的 prerouting 链，不写死 mark；自动发现失败时可以用 `PASSWALL_MARK=0x...` 指定。

单次检查并在缺失时补规则：

```sh
/usr/bin/netbird-passwall-compat.sh --once
```

确认输出的 mark 和链就是当前规则后，可以注册为 procd 服务。默认 30 秒检查一次，只在规则缺失或 mark 变化时补回，不重复插入，也不会重启 NetBird、PassWall 或路由器：

```sh
/etc/init.d/netbird-passwall-compat enable
/etc/init.d/netbird-passwall-compat start
/etc/init.d/netbird-passwall-compat status
```

临时提高频率：`INTERVAL=10 /etc/init.d/netbird-passwall-compat restart`；单次检查也可以用 `INTERVAL=5 /usr/bin/netbird-passwall-compat.sh --once`。停止用 `disable` + `stop`。之前用 `nohup` 起过旧进程的话，先执行一次 `pkill -f '[n]etbird-passwall-compat.sh'`，避免手动进程和 procd 同时运行。

### netbird-dnsmasq-wt0-fix.sh

处理 NetBird `wt0` 抢占 53 端口、导致 dnsmasq 起不来的问题。只在 `dnsmasq` 未运行、`192.168.88.1:53` 无监听、且确认 `100.111.128.51:53` 被 NetBird 占用时使用。dnsmasq 本来正常时不要运行。

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh check
/usr/bin/netbird-dnsmasq-wt0-fix.sh apply
```

`apply` 会备份 `/etc/dnsmasq.conf`、加入 `except-interface=wt0` 再重启 dnsmasq。回滚：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh rollback /root/dnsmasq-netbird-backups/<备份文件>
```

### 其他脚本

| 脚本 | 作用 |
|---|---|
| `netbird-passwall-diagnose.sh` | 收集 NetBird、PassWall、DNS、路由、防火墙和 NSS 状态，不改配置 |
| `netbird-dns-guard.sh` | `check` 查 DNS 状态；`apply` 禁用 NetBird DNS 并重启 dnsmasq；`restore` 恢复 |
| `netbird-passwall-lan-fix.sh` | `check` / `apply` / `rollback`，管理 NetBird 网络与防火墙区域、转发规则 |
| `export-router-state.sh` | 升级前导出软件包清单、UCI 配置、服务状态和脚本；`INCLUDE_SECRETS=1` 才包含敏感字段 |
| `restore-package-list.sh` | 按清单重装软件包，不恢复配置、Docker 卷、证书和令牌 |

常用命令：

```sh
/usr/bin/netbird-passwall-diagnose.sh /tmp/netbird-check
/usr/bin/netbird-dns-guard.sh check
/usr/bin/netbird-passwall-lan-fix.sh check
/usr/bin/export-router-state.sh /tmp/router-export-before-upgrade
```

修改配置类操作都必须显式使用 `apply`、`restore` 或 `rollback`。

## 目录

| 目录 | 内容 |
|---|---|
| `.github/workflows/` | 编译入口、复用工作流、旧 Release 与缓存清理 |
| `Scripts/` | 构建期脚本（软件包下载、设置注入、上游修补） |
| `Config/` | 设备与软件包配置 |
| `Files/RE-CS-02/` | 直接注入固件 rootfs 的文件 |
| `docs/` | 基线对比、仓库对比、软件清单等分析文档 |

## 上游与刷机

- 源码：<https://github.com/VIKINGYFY/immortalwrt.git>（`owrt` 分支）
- 高通 U-Boot（沉心）：<https://github.com/chenxin527/uboot-qsdk12.5-build.git>
- 高通 U-Boot（小猪）：<https://github.com/1980490718/u-boot-2016.git>
