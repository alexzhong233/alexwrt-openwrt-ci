# 雅典娜 RE-CS-02 脚本说明

这些脚本用于 `jdcloud_re-cs-02` 的 ImmortalWrt/VIKING 环境。固件安装后脚本位于 `/usr/bin/`，默认不会自动启动或加入开机启动。`netbird-passwall-compat` 提供可选的 procd 服务文件。

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

只处理 NetBird 原生 nftables 链和 PassWall 标记规则的冲突。脚本会动态查找 PassWall 当前的 `meta mark set` 值和 NetBird 的 prerouting 链，不把 `0x50535731` 写死。自动发现失败时，可以临时用 `PASSWALL_MARK=0x...` 指定 mark。

适用条件：NetBird 重建 prerouting 链后，下面这种规则消失：

```text
meta mark <PassWall 当前 mark> return
```

单次检查并在缺失时补规则：

```sh
/usr/bin/netbird-passwall-compat.sh --once
```

确认输出中的 mark 和链就是当前 PassWall/NetBird 规则后，可以注册为 procd 服务：

```sh
/etc/init.d/netbird-passwall-compat enable
/etc/init.d/netbird-passwall-compat start
/etc/init.d/netbird-passwall-compat status
```

服务默认每 30 秒检查一次，只在规则缺失或 mark 变化时补回，不重复插入，也不会重启 NetBird、PassWall 或路由器。判断依据是**规则位置**而不只是"存在"：这条 `return` 必须排在会改写 mark 的规则之前，被挤到后面就删掉重插到第一位，并写一条日志。临时需要更快检查时，可用 `INTERVAL=5 /usr/bin/netbird-passwall-compat.sh --once` 做单次检查；已注册服务可这样临时改为 10 秒：

```sh
INTERVAL=10 /etc/init.d/netbird-passwall-compat restart
```

停止并取消开机启动：

```sh
/etc/init.d/netbird-passwall-compat disable
/etc/init.d/netbird-passwall-compat stop
```

如果之前手动用 `nohup` 启动过旧进程，先执行一次 `pkill -f '[n]etbird-passwall-compat.sh'`，再启用服务，避免手动进程和 procd 同时运行。

### `netbird-passwall-compat-watch.sh`

和上一个脚本处理同一件事，区别是补规则的时机：用 `nft monitor` 订阅 nftables 规则变更，NetBird 一重建 prerouting 链就立即补回，不再按固定周期检查。规则发现和插入直接复用 `netbird-passwall-compat.sh --once`，只有一份实现。

**两个服务二选一。** 轮询服务在整个生命周期内持有同一把补丁锁，同时开着会让事件补回变成空操作。

```sh
/etc/init.d/netbird-passwall-compat disable
/etc/init.d/netbird-passwall-compat stop
/etc/init.d/netbird-passwall-compat-watch enable
/etc/init.d/netbird-passwall-compat-watch start
```

`enable` 只需要执行一次：它生成 `/etc/rc.d` 下的开机软链，之后每次开机 procd 自动拉起，`sysupgrade` 升级也保留。只 `enable` 不 `start` 的话本次开机不生效、下次重启才生效；不 `enable` 就永远不会自动运行。

netlink 事件在接收缓冲溢出（ENOBUFS）时会被静默丢弃，所以默认保留 60 秒兜底检查。关掉用 `WATCHDOG=0`，放宽用 `WATCHDOG=120 /etc/init.d/netbird-passwall-compat-watch restart`。

启用前先测事件延迟：

```sh
/usr/bin/netbird-passwall-compat-watch.sh --test
```

另开窗口增删一条规则，对比打印时间戳与实际操作时间。事件明显滞后说明 `nft monitor` 的 stdout 在管道里是全缓冲，安装 `coreutils-stdbuf` 后脚本会自动启用行缓冲。

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
- `export-router-state.sh`：导出已安装软件包、UCI 配置、网络状态、服务状态和脚本。默认按键名和值特征做启发式脱敏（密码、密钥、令牌、私钥段、代理 URI、带 token 的订阅链接等），单个文件脱敏失败时会跳过而不是退回明文；脱敏不能覆盖所有写法，导出包一律当敏感文件处理，只有私密保存时才用 `INCLUDE_SECRETS=1` 原样导出。
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

涉及配置修改的命令都必须显式使用 `apply`、`restore` 或 `rollback`。后续新增脚本默认只作为手动工具加入；确需常驻时，单独提供服务文件和启用说明，不在固件中自动启用。
