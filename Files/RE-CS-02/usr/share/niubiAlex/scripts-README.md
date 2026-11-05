# 雅典娜 RE-CS-02 脚本说明

这些脚本用于 `jdcloud_re-cs-02` 的 ImmortalWrt/VIKING 环境。固件安装后脚本位于 `/usr/bin/`，全部由用户手动运行：不会自动启动、不会自动注册 procd 服务、不会自动加入开机启动。

## 推荐处理顺序

1. 问题正在发生时，先运行 `netbird-passwall-diagnose.sh`。
2. DNS 异常时运行 `netbird-dns-guard.sh check`。
3. 确认 NetBird 改写了 DNS 后，才运行 `netbird-dns-guard.sh apply`。
4. NetBird 客户端无法访问 LAN 或 WAN 时，先运行 `netbird-passwall-lan-fix.sh check`。
5. 查看备份和当前防火墙结构后，再决定是否运行 `netbird-passwall-lan-fix.sh apply`。
6. 升级固件前运行 `export-router-state.sh`，保存软件包清单和配置状态。

固件还会在首次启动时为 `netbird up` 安装默认禁用 DNS 的包装器。它只改变没有明确 DNS 参数的 `up` 命令，不会自动执行 NetBird 登录或连接。

## 两个新脚本怎么选

### `netbird-passwall-compat.sh`

只处理 NetBird nftables 链和 PassWall 标记规则的冲突。

适用条件：NetBird 重建 `netbird-mangle-prerouting` 后，下面的规则消失：

```text
meta mark 0x50535731 return
```

使用：

```sh
nft -a list chain ip netbird netbird-mangle-prerouting
nohup /usr/bin/netbird-passwall-compat.sh >/tmp/netbird-passwall-compat.log 2>&1 &
```

它每 30 秒检查一次，只在规则缺失时插入。问题处理完后停止：

```sh
pkill -f '/usr/bin/netbird-passwall-compat.sh'
```

### `netbird-dnsmasq-wt0-fix.sh`

只处理 NetBird `wt0` 接口和 dnsmasq 抢占 53 端口的冲突。

适用条件：dnsmasq 没有运行，`192.168.88.1:53` 没有监听，并且确认 `100.111.128.51:53` 被 NetBird 占用。

使用：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh check
/usr/bin/netbird-dnsmasq-wt0-fix.sh apply
```

`apply` 会备份 `/etc/dnsmasq.conf`，加入 `except-interface=wt0`，再重启 dnsmasq。dnsmasq 本来正常时不要运行。回滚：

```sh
/usr/bin/netbird-dnsmasq-wt0-fix.sh rollback /root/dnsmasq-netbird-backups/备份文件
```

## 其他脚本说明

- `netbird-passwall-diagnose.sh`：只收集状态和日志，适合先运行。
- `netbird-dns-guard.sh check`：检查 DNS 状态；`apply` 禁用 NetBird DNS 并重启 dnsmasq；`restore` 恢复 NetBird DNS 集成。
- `netbird-passwall-lan-fix.sh check`：只检查网络和防火墙；`apply` 会备份并创建 NetBird 网络/防火墙区域及转发规则；`rollback` 恢复备份。
- `export-router-state.sh`：导出已安装软件包、UCI 配置、网络状态、服务状态和脚本。默认隐藏常见敏感字段，只有私密保存时才使用 `INCLUDE_SECRETS=1`。
- `restore-package-list.sh`：按照清单重新安装软件包，不恢复 UCI 配置、Docker 卷、证书、令牌或应用数据。

## 常用命令

```sh
/usr/bin/netbird-passwall-diagnose.sh /tmp/netbird-check
/usr/bin/netbird-dns-guard.sh check
/usr/bin/netbird-passwall-lan-fix.sh check
/usr/bin/export-router-state.sh /tmp/router-export-before-upgrade

# 临时恢复 NetBird DNS
netbird up --disable-dns=false
```

涉及配置修改的命令都必须显式使用 `apply`、`restore` 或 `rollback`。后续新增脚本也只作为手动工具加入，并在这里补充触发条件和使用命令，不制作成内置常驻服务。
