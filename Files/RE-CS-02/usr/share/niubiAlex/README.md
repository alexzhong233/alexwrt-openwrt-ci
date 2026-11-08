# niubiAlex 雅典娜 RE-CS-02 固件

这是针对京东云雅典娜 `jdcloud_re-cs-02` 的个人构建。默认后台地址为 `192.168.88.1`，不预设 LuCI 的 root 密码，首次登录后自行设置。

## Wi-Fi 默认值

无线使用上游默认规则：首次启动时按硬件生成，SSID 为上游默认值，WPA2 密钥随机生成。用 `uci show wireless | grep -E 'ssid|key'` 查看，登录后建议在 LuCI 里自行修改；改过之后不会有任何脚本再覆盖。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。页面在 LuCI 的“服务 -> 应用过滤”。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速和 KMS 软件包。
- NSS 功能主体来自 `VIKINGYFY/immortalwrt`：构建配置显式选择 `nss-firmware`、`kmod-nss-wifi-drv` 和 `ATH11K_NSS_WIFI`，实际 ath11k/mac80211 NSS 补丁也来自该上游源码。
- 自建状态页 `luci-app-nss-status` 在“状态 -> NSS 卸载”，读 `nss-wifi-drv` 的 debugfs 显示加速状态、各接口收发计数和流转发表；它不包含 NSS 驱动，不负责打开无线 NSS。老旧上游的 `luci-app-nss` 读的是 qca-nss-drv 的目录，在本固件里永远显示未加载，已移除。
- NetBird、Dockerman、PassWall 和 OpenClash 默认进入固件；HomeProxy 和 PassWall2 只编译为可安装模块，不默认写入 rootfs。NetBird 是原生 CLI，`netbird up` 的行为由 LuCI 的 NetBird 页面决定，固件不做任何包装或参数注入。
- 1Panel LuCI 管理页 `luci-app-istorepanel` 默认进入固件，依赖 Docker；1Panel 容器本体按需部署。
- ZeroTier 和易有云文件管理器不进入固件。WorkBuddy2API 本体与 `luci-app-workbuddy2api` 已内置，页面在“服务 -> WorkBuddy2API”。

## NetBird 兼容守护

固件只带一个兼容守护：`netbird-passwall-compat-watch`，事件驱动。它用 `nft monitor` 订阅规则变更，NetBird 重建 `netbird-mangle-prerouting` 链后立即补回 PassWall 的 mark 豁免；另有 60 秒兜底全量检查，防止 monitor 丢事件。实际改规则的实现是 `/usr/bin/netbird-passwall-compat.sh`，它只作为前者的执行核心，不再单独注册服务。

它由 `/etc/config/niubialex` 控制：

```
config netbird 'compat'
	option mode 'off'        # off（默认）| watch
	option watchdog '60'     # 兜底检查间隔，0 关闭
```

默认 `off`，什么都不会跑。切换方式：

```sh
/usr/bin/niubialex-netbird mode watch   # 启用事件驱动守护
/usr/bin/niubialex-netbird mode off     # 关掉
/usr/bin/niubialex-netbird watchdog 60  # 兜底间隔
```

LuCI 里对应「服务 → NetBird 工具」，能在同一页看到 wt0 转发规则是否还在、守护进程有没有遗留、当前模式和兼容规则条数，也能手动补一次规则、重建 wt0 转发、看日志。

两点说明：

- 单次检查随时可以手动跑：`/usr/bin/netbird-passwall-compat.sh --once`，不需要开守护。
- `wt0` 的转发规则是 NetBird 运行时插进 `inet fw4` 的，`/etc/init.d/firewall restart` 会冲掉它们。之后执行 `/etc/init.d/netbird restart` 即可恢复；页面上的「重建 wt0 转发」就是这件事。

## 其他脚本

- `export-router-state.sh`：升级前导出软件包清单、UCI 配置、服务状态和脚本。
- `restore-package-list.sh`：根据导出的清单重新安装软件包，只恢复软件包名称，不恢复应用数据和配置。

`/usr/bin/` 下的脚本都是手动工具，不会因为刷入固件就自行执行或改动配置，只有明确运行后才会检查或修改。详细命令见同目录的 `scripts-README.md`。后续新增脚本也遵循本规则：只放入固件并在 README 说明使用条件，不默认做成常驻服务。

早期版本提供的 NetBird DNS 包装器、DNS 冲突修复、LAN 转发修复和诊断脚本已从固件移除，源码保留在仓库 `backup/netbird-legacy/`。
