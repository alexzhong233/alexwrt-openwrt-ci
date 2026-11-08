# niubiAlex 雅典娜 RE-CS-02 固件

京东云雅典娜 `jdcloud_re-cs-02` 的个人 OpenWrt 构建，源码取自 `VIKINGYFY/immortalwrt` 的 `owrt` 分支。每天北京时间 06:00 自动编译，也可以在 Actions 页面手动运行。

- 后台地址：`192.168.88.1`
- root 密码：不预设，首次登录后自行设置
- 固件信息里的时间是编译开始时间，方便核对上游源码提交时间

## 构建入口

| 项目 | 位置 |
|---|---|
| 工作流 | `.github/workflows/NIUBIALEX.yml`（调度入口）、`WRT-CORE.yml`（实际编译，被调用） |
| 设备配置 | `Config/IPQ60XX-NIUBIALEX-WIFI-YES.txt`（在 `GENERAL.txt` 之后写入，同名项以它为准） |
| 软件包处理 | `Scripts/Packages.sh` |
| 构建期设置 | `Scripts/Settings.sh`（后台地址、主机名）、`Scripts/Handles.sh`（主题与插件修补） |
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

无线不做任何定制，完全走上游规则：首次启动时 `/sbin/wifi config` 按硬件生成 `/etc/config/wireless`，三个 radio（2.4G / 5.2G / 5.8G）各自一套，SSID 取上游默认值（`<主机名>-Jdcloud-2.4g` 之类由 mac80211 生成），WPA2 密钥随机生成。第一次登录后可以在 LuCI 里自行修改，之后不会被任何脚本覆盖；密码可以在路由器上 `uci show wireless | grep key` 查。

原先有一个首启脚本 `Files/RE-CS-02/etc/uci-defaults/99-niubialex-wireless` 会改 SSID 和密码，已删除：它在「无线还没就绪」时返回 1，而 `uci_apply_defaults` 只删除返回 0 的脚本，于是脚本被留下来每次启动重试；重试一旦成功，就会把用户改过的无线设置覆盖回默认值。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译，页面在“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速、KMS。
- Docker、Docker Compose、1Panel 管理页 `luci-app-istorepanel`（容器本体由页面按需安装）、NetBird LuCI、FullConeNAT、RTP2HTTPD、软件包管理器、SysTools。
- NSS：`nss-firmware`、`kmod-nss-wifi-drv`、`ATH11K_NSS_WIFI` 与 ath11k/mac80211 NSS 补丁都来自上游源码；自建状态页 `luci-app-nss-status` 在“状态 -> NSS 卸载”，直接读 `nss-wifi-drv` 的 debugfs 显示加速状态、各 vdev 收发计数和流表，不含驱动，不负责开启 NSS。
- 默认进 rootfs：NetBird、PassWall、OpenClash、Dockerman。HomeProxy 和 PassWall2 只编译为可安装模块。
- 不进固件：ZeroTier、易有云文件管理器。WorkBuddy2API 已整个移出构建，界面和拉取脚本都留在 `backup/`。
- NetBird 使用原生 CLI，`netbird up` 不做任何参数包装，行为由 LuCI 的 NetBird 页面决定。

软件包在 CI 里由 `Scripts/Packages.sh` 下载进编译树，仓库不保存编译好的 `.ipk`。脚本装到 `/usr/bin/`，说明文档装到 `/usr/share/niubiAlex/`，都不注册为常驻服务。逐包核对见 [docs/SOFTWARE-AUDIT.md](docs/SOFTWARE-AUDIT.md)。

## 软件源与固件文件

- 软件源保留上游默认：`/etc/apk/repositories.d/distfeeds.list` 由 base-files 在编译时按 `feeds.conf.default` 自动生成（指向 downloads.immortalwrt.org），仓库不覆盖它。
- 国内下载再追加一份南京大学镜像，写在 `Files/RE-CS-02/etc/apk/repositories.d/customfeeds.list`（官方指定的自定义位置，sysupgrade 后保留，且在 `distfeeds.list` 之前加载）。两份源版本一致，不会冲突；镜像滞后导致装不上时删掉对应几行即可。iStore 的源由 `luci-app-store` 自带的 `compat.list` 提供，这里不用重复写。
- 每次编译产出两个镜像：`...-squashfs-factory.bin`（首次刷机/救砖，走 U-Boot 或原厂 web 后台）和 `...-squashfs-sysupgrade.bin`（系统内升级）。两者内容一致，只是封装不同。

## 脚本

固件里的脚本都在 `/usr/bin/`，默认不启动。NetBird 兼容守护由 `/etc/config/niubialex` 的 `mode` 显式开关（默认 `off`），其他脚本只在明确执行命令后才检查或修改配置。

### NetBird 兼容守护

`netbird-passwall-compat-watch` 是固件里唯一的常驻守护：用 `nft monitor` 订阅 nftables 规则变更，NetBird 重建 prerouting 链后立即补回 PassWall 的 mark 豁免；另有 60 秒兜底检查，因为 netlink 缓冲溢出（ENOBUFS）会静默丢事件。

改规则的实现放在 `/usr/bin/netbird-passwall-compat.sh`，由守护以 `--once` 调用，也可以手动单次执行；它不再单独注册 procd 服务——早先的轮询服务与事件守护共用同一把补丁锁，同时开等于互相抵消，已移除。

```sh
/usr/bin/netbird-compat-ctl status        # 当前模式、进程数、wt0 规则数
/usr/bin/netbird-compat-ctl mode watch    # 启用事件守护
/usr/bin/netbird-compat-ctl mode off      # 关闭（默认）
/usr/bin/netbird-compat-ctl watchdog 60   # 兜底间隔，0 关闭
```

LuCI 里是「服务 → NetBird 工具」，能看状态、切模式、立即补一次规则、重建 wt0 转发、查日志。

`wt0` 的两条转发规则由 NetBird 运行时插进 `inet fw4`，执行 `/etc/init.d/firewall restart` 会被冲掉，之后 `/etc/init.d/netbird restart` 即可恢复。

### UU 游戏加速器的「正在注册」

`luci-app-uugamebooster` 的状态页要三个条件同时成立才显示 Ready：进程存在、与网易控制服务器有 ESTABLISHED 连接、注册记录 `/tmp/uu/activate_status` 非空。前两个重启后能自行恢复，第三个不能——文件在 tmpfs，重启即清空；而注册事实存在网易云端，服务端认为设备已注册就不会让插件重写它。

结果是：**重启后 LuCI 一直显示「正在注册」，但加速本身是正常的**。别用页面判断，看这两条：

```sh
/usr/libexec/uuplugin/uu-detect          # boosted= 后面有设备 IP 就是在加速
cat /proc/net/dev | grep tun             # 隔 10 秒看两次，tun163 的 RX/TX 在涨就是流量真的走了隧道
```

这个显示问题没有修。原因是它只影响展示：`ip rule` 的 `from <设备IP> lookup <表>`、`table 179` 里的 `dev tun163` 路由、`/proc/net/dev` 的字节增长全都不依赖那个文件，手机 App 侧也能正常绑定。代价是失去了一个真实的状态指示——首次注册确实没完成时，页面同样显示「正在注册」，此时以 App 为准。

两个容易误判的地方：`nft list tables | grep XU_ACC` 为空是正常的（OEM 构建只建策略路由，不建这些表）；两次 `uu-detect` 的 `cloud=` 地址不同也正常（有多个控制节点，取第一条 ESTABLISHED）。

### 升级辅助

| 脚本 | 作用 |
|---|---|
| `export-router-state.sh` | 升级前导出软件包清单、UCI 配置、服务状态和脚本；默认按键名和值特征启发式脱敏，`INCLUDE_SECRETS=1` 才原样导出 |
| `restore-package-list.sh` | 按清单重装软件包，不恢复配置、Docker 卷、证书和令牌 |

```sh
/usr/bin/export-router-state.sh /tmp/router-export-before-upgrade
```

早期版本提供的 `netbird up --disable-dns` 包装器、`netbird-dns-guard.sh`、`netbird-dnsmasq-wt0-fix.sh`、`netbird-passwall-diagnose.sh` 和 `netbird-passwall-lan-fix.sh` 已移出固件，源码保留在 [backup/netbird-legacy/](backup/netbird-legacy/)。


## 目录

| 目录 | 内容 |
|---|---|
| `.github/workflows/` | 编译入口、复用工作流、旧 Release 与缓存清理 |
| `Scripts/` | 构建期脚本（软件包下载、设置注入、上游修补） |
| `Config/` | 设备与软件包配置 |
| `Files/RE-CS-02/` | 直接注入固件 rootfs 的文件 |
| `docs/` | 基线对比、仓库对比、软件清单等分析文档；`config-snapshot-ec73307.txt` 是另一项目（带 PON feeds）的 `.config` 快照，仅作参考 |

## 上游与刷机

- 源码：<https://github.com/VIKINGYFY/immortalwrt.git>（`owrt` 分支）
- 高通 U-Boot（沉心）：<https://github.com/chenxin527/uboot-qsdk12.5-build.git>
- 高通 U-Boot（小猪）：<https://github.com/1980490718/u-boot-2016.git>
