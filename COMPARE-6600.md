# niubiAlex 与 6600 项目对比

对比对象：

- 本项目：`alexzhong233/niubiAlex-openwrt-ci`，设备配置为 `jdcloud_re-cs-02`，基于 `VIKINGYFY/immortalwrt` 的 `owrt` 分支。
- 6600 项目：`guangyin53222/OpenWRT-CI`，其 QCA 配置基于 `guangyin53222/immortalwrt` 的 `owrt` 分支。

下表按两个项目当前仓库里的设备配置和 `Packages.sh` 判断。软件版本会随每日编译时的上游提交变化。

| 项目 | niubiAlex | 6600 项目 | 结果 |
|---|---|---|---|
| 目标设备 | 明确选择 `jdcloud_re-cs-02` | `IPQ60XX-WIFI-YES` 中也选择雅典娜设备 | 基础目标相同 |
| 基础源码 | `VIKINGYFY/immortalwrt` | `guangyin53222/immortalwrt` | 上游分支和补丁来源不同 |
| NSS 固件和 Wi-Fi NSS | 明确选择 `nss-firmware`、`kmod-nss-wifi-drv`、`ATH11K_NSS_WIFI` | 配置中没有对应明确选择 | niubiAlex 更完整 |
| NSS 监控页 | `luci-app-nss=y` | 没有 | niubiAlex 多一个状态页 |
| OpenAppFilter | `appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译进入固件 | 脚本会下载 OpenAppFilter 源码，但设备配置没有明确选入 | niubiAlex 默认安装 |
| Docker | `docker`、`dockerd`、`docker-compose`、`luci-app-dockerman` | 没有明确选入 | niubiAlex 默认安装 |
| 1Panel | `luci-app-istorepanel=y`，从 `linkease/openwrt-app-actions` 提取 | 没有 | niubiAlex 默认提供 1Panel LuCI 入口 |
| iStore | `luci-app-store`、`luci-lib-taskd`、`luci-lib-xterm`、`taskd` 进入固件 | 脚本会下载 iStore，但配置没有明确选入 | niubiAlex 默认安装 |
| 易有云文件管理 | 排除 `luci-app-linkease` | 脚本会下载 LinkEase 相关包 | 6600 更偏向易有云生态 |
| NetBird | `netbird`、LuCI 页面、中文翻译进入固件 | 没有明确选入 | niubiAlex 多 NetBird |
| PassWall | `luci-app-passwall=y` | 没有明确选入 | niubiAlex 多 PassWall |
| PassWall2 | `=m`，编译但不默认安装 | 没有明确选入 | niubiAlex 可从包管理器安装 |
| HomeProxy | `=m`，编译但不默认安装 | `=y`，默认安装 | 6600 默认多 HomeProxy |
| OpenClash | `=y` | 没有明确选入 | niubiAlex 多 OpenClash |
| Athena LED | 默认安装，源码来自 `NONGFAH/luci-app-athena-led` | 脚本从 `577090447/JDC-AX6600-Athena-LED-Controller` 提取 | 都有，来源不同 |
| Harbor File | `luci-app-harbor-file=y` | 没有明确选入 | niubiAlex 多 Harbor File |
| OpenList | `openlist`、LuCI 页面和中文翻译进入固件 | 没有明确选入 | niubiAlex 多 OpenList |
| qBittorrent | 主程序和 LuCI 页面进入固件 | 没有明确选入 | niubiAlex 多 qBittorrent |
| UU 游戏加速 | 进入固件 | 没有明确选入 | niubiAlex 多 UU |
| KMS | `vlmcsd` 和 LuCI 页面进入固件 | 没有明确选入 | niubiAlex 多 KMS |
| 磁盘管理 | 使用 `luci-app-diskman`，并明确关闭 `luci-app-mini-diskmanager` | `luci-app-mini-diskmanager=y` | 实现不同 |
| Natmap / 分区工具 / UPnP | 纳入 | 纳入 | 基本相同 |
| Wi-Fi 默认名 | `niubiAlex`、`niubiAlexGaming` | `OWRT` | niubiAlex 个性化 |
| Wi-Fi 密码 | `88888888` | `12345678` | niubiAlex 按当前设备配置 |
| 管理地址 | `192.168.88.1` | `192.168.10.1` | niubiAlex 按当前路由器配置 |
| NetBird DNS 默认行为 | 固件首次启动后，未显式指定时给 `netbird up` 加 `--disable-dns` | 没有这项定制 | niubiAlex 针对现有 DNS 冲突 |
| NetBird/PassWall 脚本 | 动态发现 mark 和 nftables 链，附带可选服务 | 没有这套脚本 | niubiAlex 多故障处理 |

当前最关键的实际差异是：6600 项目更接近“通用 IPQ60XX 构建”，保留 HomeProxy、mini-diskmanager 和易有云相关源码；niubiAlex 是针对你这台 RE-CS-02 的应用型固件，默认把 Docker、1Panel、NetBird、PassWall、OpenClash、OpenList、Harbor、qBittorrent、UU、KMS、NSS 和现有修复脚本放进去。
