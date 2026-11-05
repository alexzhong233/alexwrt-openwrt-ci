# niubiAlex 雅典娜 RE-CS-02 固件

这是针对京东云雅典娜 `jdcloud_re-cs-02` 的个人构建。默认后台地址为 `192.168.88.1`，不预设 LuCI 的 root 密码，首次登录后自行设置。

## Wi-Fi 默认值

- 板载 2.4 GHz：SSID `niubiAlex`，信道 `5`，`HE40`。
- 板载 5 GHz：SSID `niubiAlex`，信道 `161`，`HE80`。
- PCIe/5.2 GHz：SSID `niubiAlexGaming`，信道 `36`，`HE160`。
- 默认无线密码：`88888888`，首次启动后建议修改。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。页面在 LuCI 的“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速和 KMS 软件包。
- Docker、Docker Compose、NetBird LuCI、FullConeNAT、RTP2HTTPD、软件包管理器和 SysTools；OpenList 使用 `openlist`/`luci-app-openlist` 包名。
- NSS 功能主体来自 `VIKINGYFY/immortalwrt`：构建配置显式选择 `nss-firmware`、`kmod-nss-wifi-drv` 和 `ATH11K_NSS_WIFI`，实际 ath11k/mac80211 NSS 补丁也来自该上游源码。
- `luci-app-nss` 只保留为状态监控页，页面在“状态 -> NPU (NSS) Status”；它不包含 NSS 驱动，不负责打开无线 NSS。
- 首次启动时会为 `netbird up` 安装默认禁用 DNS 的包装器；显式使用 `--disable-dns=false` 仍可恢复 NetBird DNS。
- NetBird、Dockerman、PassWall 和 OpenClash 默认进入固件；HomeProxy 和 PassWall2 只编译为可安装模块，不默认写入 rootfs。
- 1Panel LuCI 管理页 `luci-app-istorepanel` 默认进入固件，依赖 Docker；1Panel 容器本体仍由页面按需安装和管理。
- ZeroTier、易有云文件管理器和 WorkBuddy2API 不进入固件。
- 详细软件清单核对见 [SOFTWARE-AUDIT.md](SOFTWARE-AUDIT.md)。

## 脚本使用原则

除特别说明外，所有脚本都只是手动工具，放在 `/usr/bin/`，不会自动注册为服务。`netbird-passwall-compat` 提供可选的 procd 服务文件，但不会自动 `enable`；只有明确运行命令后才会检查或修改配置。

遇到问题时，先运行诊断脚本，再根据诊断结果选择对应的修复脚本。不要为了“预防”而把所有脚本都运行一遍。

## NetBird `up` 默认禁用 DNS

固件首次启动时会把原始客户端保存为 `/usr/libexec/netbird-real`，并在 `/usr/bin/netbird` 放置包装器。执行 `netbird up ...` 时，如果命令行没有写 DNS 参数，包装器会自动追加 `--disable-dns`；其他 NetBird 命令原样转发。

需要临时恢复 NetBird DNS 时显式执行：

```sh
netbird up --disable-dns=false
```

这项设置不会自动执行 `netbird up`，也不会自动登录或启动 NetBird。

## 两个 NetBird 新脚本

### NetBird 与 PassWall 的标记冲突

出现以下情况时使用 `netbird-passwall-compat.sh`：

- NetBird 已创建 `netbird-mangle-prerouting` 链；
- NetBird 重连或重启后，PassWall 的 mark 豁免规则消失；
- 结果是 NetBird 流量绕过 PassWall，或 PassWall 的分流行为异常。

单次检查并在缺失时补规则：

```sh
/usr/bin/netbird-passwall-compat.sh --once
```

确认输出的 PassWall mark 和 NetBird 链正确后，可以注册为开机服务：

```sh
/etc/init.d/netbird-passwall-compat enable
/etc/init.d/netbird-passwall-compat start
```

服务默认每 30 秒检查一次，只在规则缺失或 PassWall mark 变化时补回，不重复插入，也不会重启 NetBird、PassWall 或路由器。临时需要更快检查时，可用 `INTERVAL=5 /usr/bin/netbird-passwall-compat.sh --once` 做单次检查；已注册服务可这样临时改为 10 秒：

```sh
INTERVAL=10 /etc/init.d/netbird-passwall-compat restart
```

停止服务：

```sh
/etc/init.d/netbird-passwall-compat disable
/etc/init.d/netbird-passwall-compat stop
```

### NetBird 与 dnsmasq 的 53 端口冲突

出现以下情况时使用 `netbird-dnsmasq-wt0-fix.sh`：

- `/etc/init.d/dnsmasq status` 显示没有运行；
- `192.168.88.1:53` 没有监听，局域网设备无法解析域名；
- 日志或前台启动 dnsmasq 时明确显示 `100.111.128.51:53` 被占用；
- 占用者是 NetBird 的 `wt0` 地址。

先检查：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh check
```

确认是上述冲突后再应用：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh apply
```

脚本会备份 `/etc/dnsmasq.conf`，加入 `except-interface=wt0`，然后重启 dnsmasq，使 dnsmasq 跳过 NetBird 接口并继续为 LAN 提供 DNS。dnsmasq 本来正常时不要运行这个修复。

回滚时使用脚本输出的备份文件：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh rollback /root/dnsmasq-netbird-backups/备份文件
```

## 其他脚本

- `netbird-passwall-diagnose.sh`：收集 NetBird、PassWall、DNS、路由、防火墙和 NSS 状态，不主动修改配置。
- `netbird-dns-guard.sh`：检查或手动切换 NetBird DNS；`apply` 会使用 `netbird up --disable-dns` 并重启 dnsmasq。
- `netbird-passwall-lan-fix.sh`：检查或手动创建 NetBird 的网络/防火墙转发配置；执行 `apply` 前先看 `check` 输出并确认备份。
- `export-router-state.sh`：升级前导出软件包清单、UCI 配置、服务状态和脚本。
- `restore-package-list.sh`：根据导出的清单重新安装软件包，只恢复软件包名称，不恢复应用数据和配置。

详细命令见同目录的 `scripts-README.md`。后续新增脚本也遵循本规则：只放入固件并在 README 说明使用条件，不默认做成常驻服务。
