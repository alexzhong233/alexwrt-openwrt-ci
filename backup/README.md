# 备份：已从固件移除的东西

这里的文件曾经被编进固件，现在全部移出。目录结构保持原样，方便对照路径或整段恢复。

`Files/RE-CS-02/` 是构建时唯一被拷进固件的目录。放在仓库根 `backup/` 下的内容不会被编进固件。

- `netbird-legacy/` —— NetBird 的旧辅助脚本，见下文。
- `luci-app-workbuddy2api/` —— 自建的 WorkBuddy2API 管理页面，见文末。
- `prepare-workbuddy2api.sh` + `uci-defaults/99-workbuddy2api` —— WorkBuddy2API 的构建期准备脚本（拉上游源码、补应用文件、挂首启初始化）。它里面“拷 `LuCI/` 页面”那一段已拆到 `Scripts/prepare-luci-packages.sh` 保留，见文末最后一节。

## 为什么移除

1. **`netbird up` 的 `--disable-dns` 包装器**是早期为了绕开 PassWall 抢 DNS 加的。它把真身挪到 `/usr/libexec/netbird-real`，再在 `/usr/bin/netbird` 放一个 shell 包装。副作用是 LuCI 的 NetBird 页面所有 `up` 操作都被迫带 `--disable-dns`，不再是上游行为。现在改回原生 CLI，DNS 交给 NetBird 自己按配置处理。

2. **轮询服务**（`netbird-passwall-compat` + 对应的 init）和事件版长期并存，两者共用同一把补丁锁，同时开等于互相抵消。现在只保留事件驱动的 `netbird-passwall-compat-watch`。注意：**`netbird-passwall-compat.sh` 本身没有移除**，它是 watch 的执行核心，仍在 `Files/RE-CS-02/usr/bin/` 里。

3. **DNS / LAN / 诊断三个修复脚本**是针对当时特定故障的一次性工具，问题定位清楚后不再需要。

## 文件清单

| 文件 | 用途 |
|---|---|
| `etc/uci-defaults/98-netbird-default-nodns` | 首次启动把 `/usr/bin/netbird` 换成自动追加 `--disable-dns` 的包装器 |
| `etc/init.d/netbird-passwall-compat` | 轮询版兼容服务的 procd 文件 |
| `usr/bin/netbird-dns-guard.sh` | 检查 / 切换 NetBird DNS（`apply` 会用 `netbird up --disable-dns`） |
| `usr/bin/netbird-dnsmasq-wt0-fix.sh` | 解决 dnsmasq 与 `wt0` 抢 53 端口（加 `except-interface=wt0`） |
| `usr/bin/netbird-passwall-diagnose.sh` | 一次性收集 NetBird / PassWall / DNS / 路由 / 防火墙状态 |
| `usr/bin/netbird-passwall-lan-fix.sh` | 检查 / 创建 NetBird 的防火墙 zone 与转发规则 |

`netbird-passwall-compat.sh` 曾被短暂移到这里，现已放回 `Files/RE-CS-02/usr/bin/`，不在本目录。

## 怎么恢复

想让某个脚本回到固件，移回去再编译即可：

```sh
git mv backup/netbird-legacy/usr/bin/netbird-dns-guard.sh \
       Files/RE-CS-02/usr/bin/netbird-dns-guard.sh
```

恢复轮询服务还要同时把 `etc/init.d/netbird-passwall-compat` 放回，并在 `/etc/config/niubialex` 里补一个对应模式——当前的 `mode` 只认 `off` / `watch`。

## 设备侧注意

已经刷过含 `98-netbird-default-nodns` 的固件，`/usr/bin/netbird` 是包装脚本、真身在 `/usr/libexec/netbird-real`。新固件的 `99-niubialex-legacy-cleanup` 会把它反向恢复（真身覆盖回 `/usr/bin/netbird`，然后删掉中间文件），同时清理上表里除 `98-*` 之外的残留副本和 `/etc/rc.d` 开机软链接。配置初始化在 `90-niubialex-compat`。

如果不想等新固件，可以手动执行：

```sh
cp -f /usr/libexec/netbird-real /usr/bin/netbird && chmod 755 /usr/bin/netbird
rm -f /usr/libexec/netbird-real
netbird status
```

## luci-app-workbuddy2api（2026-11-08 移入）

自建的 WorkBuddy2API 管理页（“服务 -> WorkBuddy2API”，JS 版 LuCI：`htdocs/luci-static/resources/view/` + `menu.d` + `acl.d`）。2026-11-08 起 WorkBuddy2API 改为**只编译不预装**（`CONFIG_PACKAGE_workbuddy2api=m`），界面随之移出构建树。

注意两点：

1. `Scripts/prepare-luci-packages.sh` 会遍历 `LuCI/*/` 全部拷进构建树，这个目录一旦放回去就会自动被编进去，**不需要改脚本**；但必须同时在 `Config/IPQ60XX-NIUBIALEX-WIFI-YES.txt` 里加回：

   ```sh
   CONFIG_PACKAGE_luci-app-workbuddy2api=y
   ```

2. 界面依赖 `/etc/config/workbuddy2api` 和 `/etc/init.d/workbuddy2api`，这两个都随 `workbuddy2api` 本体包走。只装界面不装本体，页面上的操作会全部失败。

恢复命令：

```sh
git mv backup/luci-app-workbuddy2api LuCI/luci-app-workbuddy2api
```

## prepare-workbuddy2api.sh（2026-11-08 移入）

`Scripts/prepare-workbuddy2api.sh` 在 2026-11-08 整个移到这里，同时带走了只有它引用的 `Scripts/uci-defaults/99-workbuddy2api`（现在在 `backup/uci-defaults/`）。`.github/workflows/WRT-CORE.yml` 里对应的调用行已删除。

这个脚本原本做四件事，其中**第一件被拆出来单独保留**了：

| 原职责 | 现状 |
|---|---|
| 遍历 `LuCI/*/` 拷进构建树 | **已拆到 `Scripts/prepare-luci-packages.sh`**，工作流在同一位置调用。`luci-app-nss-status`、`luci-app-netbird-tools` 照常进固件 |
| 克隆 `ardeyouxipianyi/workbuddy2api-hub` 到 `package/workbuddy2api` | 不再发生，包里没有这个包 |
| 把 `wb_*.py` + `dashboard.html` 补进包的 `files/` | 不再发生 |
| 挂 `99-workbuddy2api` 首启初始化 | 不再发生 |

配置里的 `CONFIG_PACKAGE_workbuddy2api=m` 同时删掉了：包不在构建树里，留着这行只是个不存在的符号（defconfig 静默丢弃），什么也编不出来。所以现在 **WorkBuddy2API 既不进固件、也不产出 apk**，要用就去上游 release 下现成的包装。

### 恢复

```sh
git mv backup/prepare-workbuddy2api.sh Scripts/prepare-workbuddy2api.sh
git mv backup/uci-defaults Scripts/uci-defaults
git mv backup/luci-app-workbuddy2api LuCI/luci-app-workbuddy2api
```

然后在 `.github/workflows/WRT-CORE.yml` 的 `Custom Packages` 步骤里加回一行（放在 `prepare-luci-packages.sh` 之后即可）：

```yaml
          $GITHUB_WORKSPACE/Scripts/prepare-workbuddy2api.sh
```

配置里再加回 `CONFIG_PACKAGE_workbuddy2api=m`（只编译出包）或 `=y`（进固件）。

两点注意：① 脚本里的 `SCRIPT_DIR/uci-defaults/99-workbuddy2api` 是相对自身路径的，`uci-defaults/` 必须和脚本同级；② 恢复后它会再拷一遍 `LuCI/`，与 `prepare-luci-packages.sh` 重复，但重复拷贝无害。
