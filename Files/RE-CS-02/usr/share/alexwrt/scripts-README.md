# 雅典娜 RE-CS-02 脚本说明

这些脚本用于 `jdcloud_re-cs-02` 的 ImmortalWrt/VIKING 环境。固件安装后脚本位于 `/usr/bin/`，默认不会自动启动或加入开机启动。

## NetBird 兼容守护

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

这个脚本本身不再注册 procd 服务，只作为下面事件守护的执行核心。想让它常驻，用模式开关（见下）。

判断依据是**规则位置**而不只是"存在"：这条 `return` 必须排在会改写 mark 的规则之前，被挤到后面就删掉重插到第一位，并写一条日志。

如果之前手动用 `nohup` 启动过旧进程，先执行一次 `pkill -f '[n]etbird-passwall-compat.sh'`，避免手动进程和守护同时运行。

### `netbird-passwall-compat-watch.sh`

用 `nft monitor` 订阅 nftables 规则变更，NetBird 一重建 prerouting 链就立即补回，不按固定周期轮询。规则发现和插入复用 `netbird-passwall-compat.sh --once`，只有一份实现。

固件里唯一的常驻方式，由 `/etc/config/alexwrt` 控制，默认关闭：

```sh
/usr/bin/netbird-compat-ctl mode watch   # 启用
/usr/bin/netbird-compat-ctl mode off     # 关闭
```

也可以直接在 LuCI「服务 → NetBird 工具」切换。**不要**用 `/etc/init.d/netbird-passwall-compat-watch enable` 绕过开关——服务启动时会检查 `mode`，不匹配就直接返回，等于白配一个开机项。

netlink 事件在接收缓冲溢出（ENOBUFS）时会被静默丢弃，所以默认保留 60 秒兜底检查。调整用 `watchdog`：

```sh
/usr/bin/netbird-compat-ctl watchdog 120   # 放宽
/usr/bin/netbird-compat-ctl watchdog 0     # 关闭兜底
```

启用前先测事件延迟：

```sh
/usr/bin/netbird-passwall-compat-watch.sh --test
```

另开窗口增删一条规则，对比打印时间戳与实际操作时间。事件明显滞后说明 `nft monitor` 的 stdout 在管道里是全缓冲，安装 `coreutils-stdbuf` 后脚本会自动启用行缓冲。

## 其他脚本说明

- `export-router-state.sh`：导出已安装软件包、UCI 配置、网络状态、服务状态和脚本。默认按键名和值特征做启发式脱敏（密码、密钥、令牌、私钥段、代理 URI、带 token 的订阅链接等），单个文件脱敏失败时会跳过而不是退回明文；脱敏不能覆盖所有写法，导出包一律当敏感文件处理，只有私密保存时才用 `INCLUDE_SECRETS=1` 原样导出。
- `restore-package-list.sh`：按照清单重新安装软件包，不恢复 UCI 配置、Docker 卷、证书、令牌或应用数据。

## 常用命令

```sh
/usr/bin/netbird-compat-ctl status
/usr/bin/netbird-compat-ctl mode watch
/usr/bin/netbird-passwall-compat.sh --once
/usr/bin/export-router-state.sh /tmp/router-export-before-upgrade
```

涉及配置修改的命令都必须显式执行。后续新增脚本默认只作为手动工具加入；确需常驻时，单独提供服务文件和启用说明，不在固件中自动启用。

早期的 `netbird-dns-guard.sh`、`netbird-dnsmasq-wt0-fix.sh`、`netbird-passwall-diagnose.sh`、`netbird-passwall-lan-fix.sh` 和 `netbird up` 的 `--disable-dns` 包装器已从固件移除，源码保留在仓库 `backup/netbird-legacy/`。
