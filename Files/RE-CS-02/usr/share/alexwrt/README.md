# alexwrt 雅典娜 RE-CS-02 固件

这是针对京东云雅典娜 `jdcloud_re-cs-02` 的 OpenWrt 构建。默认后台地址为 `192.168.88.1`，不预设 LuCI 的 root 密码，首次登录后自行设置。

## Wi-Fi 默认值

无线仍由上游规则在首次启动时按硬件生成，定制项只是兜底值：SSID、国家码、信道和频宽。

| 频段 | 硬件 | 默认 SSID | 信道 | 频宽 |
|---|---|---|---|---|
| 2.4 GHz | SoC 内置 | `alexwrt-jdcloud-2.4g` | 5 | HE40 |
| 5.2 GHz | PCIe 4×4 | `alexwrt-jdcloud-5.2g` | 36 | HE160 |
| 5.8 GHz | SoC 内置 2×2 | `alexwrt-jdcloud-5.8g` | 161 | HE80 |

国家码 `US`，加密 `psk2+ccmp`（WPA2-PSK），密码 `12345678`。用 `uci show wireless | grep -E 'ssid|key'` 查看，登录后建议在 LuCI 里自行修改；改过之后不会有任何脚本再覆盖。

5.2 GHz 的 160MHz 落在 DFS 频段，首次启动或换信道时需要等一次约 60 秒的 CAC，属正常现象。2.4 GHz 的 HE40 若因邻居干扰被降成 HE20，也属 802.11 共存规则的正常降级。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。页面在 LuCI 的“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速和 KMS 软件包。
- NSS 功能主体来自 `VIKINGYFY/immortalwrt`：构建配置显式选择 `nss-firmware`、`kmod-nss-wifi-drv` 和 `ATH11K_NSS_WIFI`，实际 ath11k/mac80211 NSS 补丁也来自该上游源码。
- 自建状态页 `luci-app-nss-status` 在“状态 -> NSS 卸载”，读 `nss-wifi-drv` 的 debugfs 显示加速状态、各接口收发计数和流转发表；它不包含 NSS 驱动，不负责打开无线 NSS。老旧上游的 `luci-app-nss` 读的是 qca-nss-drv 的目录，在本固件里永远显示未加载，已移除。
- NetBird、Dockerman、PassWall 和 OpenClash 默认进入固件；HomeProxy 和 PassWall2 只编译为可安装模块，不默认写入 rootfs。NetBird 是原生 CLI，`netbird up` 的行为由 LuCI 的 NetBird 页面决定，固件不做任何包装或参数注入。
- ZeroTier 和易有云文件管理器不进入固件。WorkBuddy2API 整个不参与构建（包骨架与应用源码的拉取脚本和 LuCI 界面都在仓库 `backup/` 下），需要时自行从上游 release 安装。设置向导 `luci-app-netwizard` 正常预装。

## NetBird 兼容守护

固件只带一个兼容守护：`netbird-passwall-compat-watch`，事件驱动。它用 `nft monitor` 订阅规则变更，NetBird 重建 `netbird-mangle-prerouting` 链后立即补回 PassWall 的 mark 豁免；另有 60 秒兜底全量检查，防止 monitor 丢事件。实际改规则的实现是 `/usr/bin/netbird-passwall-compat.sh`，它只作为前者的执行核心，不再单独注册服务。

它由 `/etc/config/netbird-passwall-compat` 控制：

```
config compat 'settings'
	option mode 'off'        # off（默认）| watch
	option watchdog '60'     # 兜底检查间隔，0 关闭
```

uci 路径是 `netbird-passwall-compat.settings.mode`。

默认 `off`，什么都不会跑。切换方式：

```sh
/usr/bin/netbird-compat-ctl mode watch   # 启用事件驱动守护
/usr/bin/netbird-compat-ctl mode off     # 关掉
/usr/bin/netbird-compat-ctl watchdog 60  # 兜底间隔
```

LuCI 里对应「服务 → NetBird 工具」，能在同一页看到 wt0 转发规则是否还在、守护进程有没有遗留、当前模式和兼容规则条数，也能手动补一次规则、重建 wt0 转发、看日志。

两点说明：

- 单次检查随时可以手动跑：`/usr/bin/netbird-passwall-compat.sh --once`，不需要开守护。
- `wt0` 的转发规则是 NetBird 运行时插进 `inet fw4` 的，`/etc/init.d/firewall restart` 会冲掉它们。之后执行 `/etc/init.d/netbird restart` 即可恢复；页面上的「重建 wt0 转发」就是这件事。

## 其他脚本

`/usr/bin/` 下的脚本都是手动工具，不会因为刷入固件就自行执行或改动配置，只有明确运行后才会检查或修改。详细命令见同目录的 `scripts-README.md`。

早期版本提供的 NetBird DNS 包装器、DNS 冲突修复、LAN 转发修复、诊断脚本和路由器状态导出/还原脚本已从固件移除，源码保留在仓库 `backup/`。
