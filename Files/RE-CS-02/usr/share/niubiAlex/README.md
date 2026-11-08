# niubiAlex 雅典娜 RE-CS-02 固件

这是针对京东云雅典娜 `jdcloud_re-cs-02` 的个人构建。默认后台地址为 `192.168.88.1`，不预设 LuCI 的 root 密码，首次登录后自行设置。

## Wi-Fi 默认值

- 板载 2.4 GHz：SSID `niubiAlex`，信道 `5`，`HE40`。
- 板载 5 GHz：SSID `niubiAlex`，信道 `161`，`HE80`。
- PCIe/5.2 GHz：SSID `niubiAlexGaming`，信道 `36`，`HE160`。
- 无线使用上游默认规则：首次启动时按硬件生成，SSID 为上游默认值，WPA2 密钥随机生成。用 `uci show wireless | grep -E 'ssid|key'` 查看，登录后建议在 LuCI 里自行修改；改过之后不会有任何脚本再覆盖。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。页面在 LuCI 的“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速和 KMS 软件包。
- NSS 功能主体来自 `VIKINGYFY/immortalwrt`：构建配置显式选择 `nss-firmware`、`kmod-nss-wifi-drv` 和 `ATH11K_NSS_WIFI`，实际 ath11k/mac80211 NSS 补丁也来自该上游源码。
- 自建状态页 `luci-app-nss-status` 在“状态 -> NSS 卸载”，读 `nss-wifi-drv` 的 debugfs 显示加速状态、各接口收发计数和流转发表；它不包含 NSS 驱动，不负责打开无线 NSS。老旧上游的 `luci-app-nss` 读的是 qca-nss-drv 的目录，在本固件里永远显示未加载，已移除。
- 首次启动时会为 `netbird up` 安装默认禁用 DNS 的包装器；显式使用 `--disable-dns=false` 仍可恢复 NetBird DNS。
- NetBird、Dockerman、PassWall 和 OpenClash 默认进入固件；HomeProxy 和 PassWall2 只编译为可安装模块，不默认写入 rootfs。
- 1Panel LuCI 管理页 `luci-app-istorepanel` 默认进入固件，依赖 Docker；1Panel 容器本体按需部署。
- ZeroTier 和易有云文件管理器不进入固件。WorkBuddy2API 本体与 `luci-app-workbuddy2api` 已内置，页面在“服务 -> WorkBuddy2API”。

## 脚本使用原则

`/usr/bin/` 下的脚本都是手动工具，不会因为刷入固件就自行执行或改动配置，只有明确运行后才会检查或修改。NetBird 兼容规则的两个守护（事件式 `netbird-passwall-compat-watch`、轮询式 `netbird-passwall-compat`）由 `/etc/config/niubialex` 统一开关：`option mode` 取 `off`（默认）/ `watch` / `poll`，**两个 init 脚本只有模式匹配时才启动**，所以即使手滑 `enable` 过也不会常驻，也不会两个同时跑。开关可以在 LuCI「服务 → NetBird 工具」里切，也可以命令行改。

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

确认输出的 PassWall mark 和 NetBird 链正确后，如果要让它在后台持续补规则，用模式开关启用（**不要**直接 `enable` 服务）：

```sh
# 事件驱动版，推荐
/usr/bin/niubialex-netbird mode watch

# 或者老的 30 秒轮询版
/usr/bin/niubialex-netbird mode poll

# 关掉（默认状态）
/usr/bin/niubialex-netbird mode off
```

切换模式会自动停掉另一个服务、只保留一个开机自启项。兜底检查间隔和轮询间隔也可以调：

```sh
/usr/bin/niubialex-netbird watchdog 60     # 事件版的兜底全量检查间隔，0 关闭
/usr/bin/niubialex-netbird interval 30     # 轮询版的检查间隔
```

这些值存在 `/etc/config/niubialex`，已加入 sysupgrade 保留列表。LuCI 里对应「服务 → NetBird 工具」，能在同一页看到 wt0 转发规则是否还在、守护进程有没有遗留、当前模式和兼容规则条数。

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
