# 高质量<免费>交流群

[IPQ技术讨论群](https://qm.qq.com/q/v7nMhzB4oU)

# 高质量<付费>中转站

[LiBwrt-Ai](https://api.zipimg.cn/register?aff=FFPS3UMJ8HJD)

# 本地编译器

https://github.com/VIKINGYFY/OWRT-Tools.git

# 自用修改版插件

https://github.com/VIKINGYFY/packages.git

# OpenWRT-CI

官方版：

https://github.com/immortalwrt/immortalwrt.git

自用版：

https://github.com/VIKINGYFY/immortalwrt.git

# U-BOOT

高通版-沉心：

https://github.com/chenxin527/uboot-qsdk12.5-build.git

高通版-小猪：

https://github.com/1980490718/u-boot-2016.git

联发科-全新版：

https://github.com/VIKINGYFY/UBOOT-CI/releases

联发科-官方版：

https://drive.wrt.moe/uboot/mediatek

# 固件简要说明

雅典娜个人固件每天北京时间 06:00 自动编译。

固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

MEDIATEK系列、QUALCOMMAX系列、ROCKCHIP系列、X86系列。

# 目录简要说明

workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

# niubiAlex 雅典娜 RE-CS-02 自定义构建

本仓库增加了针对京东云雅典娜 `jdcloud_re-cs-02` 的构建入口：

- 工作流：`.github/workflows/NIUBIALEX.yml`
- 设备配置：`Config/IPQ60XX-NIUBIALEX.txt`
- 软件包处理：`Scripts/Packages.sh`
- 固件文件注入：`Files/RE-CS-02/`
- 构建说明：[README-NIUBIALEX.md](README-NIUBIALEX.md)
- 脚本说明：[README-SCRIPTS.md](README-SCRIPTS.md)
- 基线代码级对比：[DIFF-BASELINE.md](DIFF-BASELINE.md)
- 固件内说明副本：`Files/RE-CS-02/usr/share/niubiAlex/`

这套构建使用 `VIKINGYFY/immortalwrt` 的 `owrt` 分支，目标设备限定为 `jdcloud_re-cs-02`。它加入了：

- 后台地址 `192.168.88.1`，root 初始密码不预设。
- 2.4 GHz 和板载 5 GHz 使用 `niubiAlex`，PCIe/5.2 GHz 使用 `niubiAlexGaming`。
- 默认 Wi-Fi 密码 `88888888`；2.4 GHz 使用信道 `5` 和 `HE40`，板载 5 GHz 使用信道 `161`，PCIe/5.2 GHz 使用信道 `36` 和 `HE160`。
- OpenAppFilter：`appfilter`、`kmod-oaf`、`luci-app-oaf` 和中文翻译。
- 雅典娜 LED、Harbor File、OpenList、qBittorrent、UU 游戏加速和 KMS 软件包。
- VIKING 上游的 NSS 功能主体：`nss-firmware`、`kmod-nss-wifi-drv`、`ATH11K_NSS_WIFI` 以及 ath11k/mac80211 NSS 补丁。
- `luci-app-nss` 监控页面，用于查看 NSS/ECM 状态，不负责启用 NSS。
- NetBird、PassWall、OpenClash、Dockerman 等默认软件包；HomeProxy 和 PassWall2 只编译为可安装模块。
- 1Panel 由用户手动安装；ZeroTier、易有云文件管理器和 WorkBuddy2API 不进入固件。
- NetBird/PassWall、NetBird/dnsmasq 冲突处理和升级前导出脚本。

软件包会在 GitHub Actions 编译时由 `Scripts/Packages.sh` 下载并加入编译树，仓库里不会预先保存编译好的 `.ipk` 文件。脚本会安装到 `/usr/bin/`，配套 README 会随固件安装到 `/usr/share/niubiAlex/`；脚本不会自动注册为常驻服务。

工作流每天北京时间 06:00 左右自动触发，也可以在 GitHub Actions 页面手动运行。

## Star History

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>
