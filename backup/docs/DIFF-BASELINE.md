# niubiAlex 与 VIKINGYFY/OpenWRT-CI 基线的代码级对比

对比基线：上游 `VIKINGYFY/OpenWRT-CI` 的 `main`。

查看完整原始差异：

```sh
git remote add upstream https://github.com/VIKINGYFY/OpenWRT-CI.git  # 仅首次
git fetch upstream
git diff upstream/main..HEAD
```

> 本文是撰写时的快照，文件数和行数为当时数据。后续增删工作流、改动脚本后会有出入，以 `git diff` 实际结果为准。

## 1. 编译入口

文件：`.github/workflows/NIUBIALEX.yml`

基线没有这个雅典娜专用入口。当前新增：

```yaml
on:
  schedule:
    - cron: '0 22 * * *'
  workflow_dispatch:
```

`0 22 * * *` 是 UTC 时间每天 22:00，对应北京时间第二天 06:00 左右。GitHub Actions 的实际启动可能有延迟。

工作流把编译参数固定为：

```yaml
WRT_CONFIG: IPQ60XX-NIUBIALEX-WIFI-YES
WRT_REPO: https://github.com/VIKINGYFY/immortalwrt.git
WRT_BRANCH: owrt
WRT_SOURCE: VIKINGYFY/immortalwrt
WRT_FILES: RE-CS-02
WRT_APPFILTER: true
```

这说明项目没有修改 VIKING 的 immortalwrt 源码，而是让 CI 在每次编译时拉取该源码，再应用本仓库的配置和文件。

## 2. 通用工作流扩展

文件：`../../.github/workflows/WRT-CORE.yml`

新增三个输入参数：

```yaml
WRT_EXTRA_CONFIG
WRT_FILES
WRT_APPFILTER
```

新增的文件注入步骤：

```sh
cd ./wrt/
mkdir -p ./files
cp -a "$GITHUB_WORKSPACE/Files/$WRT_FILES/." ./files/
```

这一步是脚本进入最终固件的关键。OpenWrt 的 `files/` 目录会被映射到固件根文件系统，所以：

- `Files/RE-CS-02/usr/bin/*.sh` 会进入固件的 `/usr/bin/`。
- `Files/RE-CS-02/usr/share/niubiAlex/*.md` 会进入固件的 `/usr/share/niubiAlex/`。
- `Files/RE-CS-02/etc/uci-defaults/99-niubialex-wireless` 会在首次启动时执行。

新增的配置注入步骤：

```sh
if [ -n "$WRT_EXTRA_CONFIG" ]; then
    cat "$GITHUB_WORKSPACE/Config/$WRT_EXTRA_CONFIG" >> .config
fi
```

## 3. 雅典娜设备配置

文件：`Config/IPQ60XX-NIUBIALEX-WIFI-YES.txt`

新增目标设备选择：

```text
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq60xx=y
CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-cs-02=y
```

新增并明确选中的软件包：

```text
CONFIG_PACKAGE_appfilter=y
CONFIG_PACKAGE_kmod-oaf=y
CONFIG_PACKAGE_luci-app-oaf=y
CONFIG_PACKAGE_luci-i18n-oaf-zh-cn=y
CONFIG_PACKAGE_nss-firmware=y
CONFIG_PACKAGE_kmod-nss-wifi-drv=y
CONFIG_ATH11K_NSS_WIFI=y
CONFIG_NSS_FIRMWARE_VERSION_12_5=y
CONFIG_PACKAGE_luci-app-nss=y
```

其中 `nss-firmware`、`kmod-nss-wifi-drv` 和 `ATH11K_NSS_WIFI` 是 VIKING 上游提供的 NSS 功能主体；`luci-app-nss` 只提供监控页面。

## 4. Wi-Fi 首次启动逻辑

文件：`Files/RE-CS-02/etc/uci-defaults/99-niubialex-wireless`

脚本通过 UCI 枚举 `wifi-device` 和对应的第一个 `wifi-iface`，然后按设备频段修改：

```sh
2g:*    -> ssid niubiAlex, channel 5, HE40
5g:*pci* -> ssid niubiAlexGaming, channel 36, HE160
5g:*    -> ssid niubiAlex, channel 161, HE80
```

2.4 GHz 额外设置：

```sh
uci set "wireless.$section.htmode=HE40"
uci set "wireless.$section.channel=5"
```

所有匹配到的无线接口使用：

```sh
encryption=psk2+ccmp
key=88888888
```

该脚本是一次性的 `uci-defaults` 初始化脚本，不是常驻服务。OpenWrt 成功执行后会移除它。

当前实现的边界：它只修改每个无线设备找到的第一个 `wifi-iface`。设备路径仍由上游设备树决定；如果 PCIe 设备路径没有包含 `pci`，需要在编译后查看 `uci show wireless`，再调整匹配条件。

## 5. 默认设置脚本的修改

文件：`../../Scripts/Settings.sh`

基线原来无条件替换 SSID 和密码：

```sh
sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g; s/key '.*'/key '$WRT_WORD'/g"
```

当前拆成条件逻辑：

```sh
sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g"
if [ -n "$WRT_WORD" ]; then
    sed -i "s/key '.*'/key '$WRT_WORD'/g"
else
    sed -i "s/encryption '.*'/encryption 'none'/g; s/key '.*'//g"
fi
```

当前工作流传入 `WRT_WORD=88888888`，所以实际使用 WPA2 密码；如果以后把 `WRT_WORD` 留空，才会生成无密码 Wi-Fi。

## 6. 软件包脚本的实际变化

文件：`../../Scripts/Packages.sh`

新增：

1. Dockerman 源码：

```sh
UPDATE_PACKAGE "dockerman" "lisaac/luci-app-dockerman" "master"
```

2. NetBird 源码兜底下载：如果 feeds 或 package 里没有 `netbird`，就从 OpenWrt packages 仓库的 `net/netbird` 复制进编译树。

3. OpenAppFilter 源码：当 `WRT_APPFILTER=true` 时复制 `open-app-filter`、`oaf`、`luci-app-oaf` 三个目录。

4. `luci-app-nss` 源码：从 `yduke/luci-app-nss` 复制 Makefile、htdocs 和 root 目录。

必须区分两件事：

- `Packages.sh` 把软件包源码放进编译树，不代表软件一定进入固件。
- 只有 `.config` 中存在 `CONFIG_PACKAGE_xxx=y`，或者其他配置间接选择了它，软件才会被编译进固件。

当前明确选中的新增软件包括 OpenAppFilter、VIKING 上游 NSS 功能包、`luci-app-nss`、NetBird、Dockerman、1Panel LuCI 管理页、PassWall 和 OpenClash。HomeProxy 与 PassWall2 编译为模块，默认不进入 rootfs。

配置中的明确选择为：

```text
CONFIG_PACKAGE_netbird=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall2=m
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-homeproxy=m
CONFIG_PACKAGE_luci-app-istorepanel=y
```

现在这些包会被 `.config` 明确选择，进入最终固件或作为模块产出。PassWall、PassWall2 和 OpenClash 的源码处理本来就在 VIKING 基线中；本次新增的是雅典娜配置中的明确选入，以及 NetBird、Dockerman、OpenAppFilter 和 NSS 监控页的额外包处理。NSS 固件、Wi-Fi 主机驱动和 ath11k/mac80211 NSS 补丁继续直接使用 VIKING 上游。

## 7. 手动脚本

新增目录：`Files/RE-CS-02/usr/bin/`

脚本用途：

| 脚本 | 作用 | 是否自动运行 |
|---|---|---|
| `netbird-passwall-compat.sh` | 动态发现 PassWall mark 和 NetBird prerouting 链，补回标记保护规则 | 默认不启动；可选 procd 服务 |
| `netbird-dnsmasq-wt0-fix.sh` | 处理 NetBird `wt0` 和 dnsmasq 的 53 端口冲突 | 否，手动执行 |
| `netbird-dns-guard.sh` | 检查或切换 NetBird DNS | 否，手动执行 |
| `netbird-passwall-diagnose.sh` | 收集 NetBird、DNS、PassWall、路由和 NSS 状态 | 否，手动执行 |
| `netbird-passwall-lan-fix.sh` | 检查或修改 NetBird 网络和防火墙转发 | 否，手动执行 |
| `export-router-state.sh` | 升级前导出软件包和配置状态 | 否，手动执行 |
| `restore-package-list.sh` | 按清单重新安装软件包 | 否，手动执行 |

本次没有新增 `/etc/init.d/` 服务，没有新增自动 `enable`，也没有新增开机守护进程。

## 8. 当前没有改动的部分

本仓库没有新增或修改：

- ath11k/NSS/Wi-Fi NSS 驱动实现；这些功能继续由 VIKING 上游提供；
- DTS、分区表、U-Boot；
- TurboACC；
- VIKING immortalwrt 的源码提交；
- OpenWrt 内核转发路径；
- `luci_plugins` 全局开关逻辑。

所以它的定位是：

```text
VIKING immortalwrt 源码
        + VIKING OpenWRT-CI 编译框架
        + 雅典娜设备配置
        + OpenAppFilter/NSS 功能包选择和监控页
        + Wi-Fi 初始化
        + 手动诊断和修复脚本
```
