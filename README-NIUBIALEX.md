# niubiAlex 雅典娜 RE-CS-02 固件

这是针对京东云雅典娜 `jdcloud_re-cs-02` 的个人构建。默认后台地址为 `192.168.88.1`，不预设 LuCI 的 root 密码，首次登录后自行设置。

## Wi-Fi 默认值

- 板载 2.4 GHz：SSID `niubiAlex`，保留生成的信道，优先使用 40 MHz。
- 板载 5 GHz：SSID `niubiAlex`，保留生成的信道。
- PCIe/5.2 GHz：SSID `niubiAlexGaming`，保留生成的信道。
- 默认无线密码：`88888888`，首次启动后建议修改。

## 固件内置内容

- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。页面在 LuCI 的“服务 -> 应用过滤”。
- `luci-app-nss`：页面在“状态 -> NPU (NSS) Status”，用于读取 NSS/ECM 统计，不会自动打开无线 NSS，也不会改变转发配置。
- NetBird、PassWall、HomeProxy 等软件包按构建配置打包；具体版本取决于编译时的上游仓库状态。

## 脚本使用原则

所有脚本都只是手动工具，放在 `/usr/bin/`，不会自动注册为 `/etc/init.d` 服务，不会自动 `enable`，也不会因为安装固件而自行执行。只有明确运行命令后才会检查或修改配置。

遇到问题时，先运行诊断脚本，再根据诊断结果选择对应的修复脚本。不要为了“预防”而把所有脚本都运行一遍。

## 两个 NetBird 新脚本

### NetBird 与 PassWall 的标记冲突

出现以下情况时使用 `netbird-passwall-compat.sh`：

- NetBird 已创建 `netbird-mangle-prerouting` 链；
- NetBird 重连或重启后，PassWall 的规则 `meta mark 0x50535731 return` 消失；
- 结果是 NetBird 流量绕过 PassWall，或 PassWall 的分流行为异常。

先检查：

```sh
nft -a list chain ip netbird netbird-mangle-prerouting
```

确认保护规则缺失后，手动启动检查脚本：

```sh
nohup /usr/bin/netbird-passwall-compat.sh >/tmp/netbird-passwall-compat.log 2>&1 &
```

脚本每 30 秒检查一次，只在规则缺失时补回，不重复插入，也不会重启 NetBird、PassWall 或路由器。冲突处理完后停止它：

```sh
pkill -f '/usr/bin/netbird-passwall-compat.sh'
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
