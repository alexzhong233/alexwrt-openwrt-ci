# 第三方仓库版本基线（2026-11-08 快照）

本表记录 `Scripts/Packages.sh` 引用的全部第三方仓库在 **2026-11-08 13:15 (GMT+8)** 的状态，
用来回答一个问题：把依赖锁到上游 tag 到底能不能提升构建稳定性。

**采集方法**：每个仓库执行一次 `git ls-remote --refs`，同时取回 `refs/heads/*` 与 `refs/tags/*`，
再比对「配置分支的 HEAD SHA」与「按 `sort -V` 取到的最新 tag 的 SHA」。
不使用 GitHub API（未认证配额 60 次/小时，49 个仓库一轮就会打满）。

## 汇总

| 分类 | 仓库数 | 含义 |
| --- | --- | --- |
| A. 分支 = 最新 tag | 12 | 切到 tag 与跟分支内容完全相同 |
| B. 无 tag | 8 | 锁 tag 无从谈起，只能跟分支 |
| C. 分支领先 tag | 29 | 锁 tag 等于主动放弃分支上的后续提交 |
| **合计** | **49** | |

## 结论

原先在 `clone_repo()` 之后调用的 `pin_tag_if_same_version()`，只在「分支上所有 Makefile 的
`PKG_VERSION` 与最新 tag 的同名版本完全一致」时才 `checkout` 该 tag。而这个条件成立时，
分支内容本来就是那个 tag（下表 A 类仓库全部如此），切换不产生任何差异；
真正需要「锁死」的 C 类仓库，规则按设计反而保持分支。

因此该规则实际是空转的，起不到「防止上游往主干乱推」的作用，已于同日移除：
所有第三方包恢复为**跟随各自配置的分支**，不再核对 tag。
若日后确需可复现构建，正确做法是对少数关键包做 commit SHA 锁定，而不是依赖 tag。

## A. 分支 HEAD 就是最新 tag（12 个）

| 仓库 | 分支 | 最新 tag |
| --- | --- | --- |
| `eamonxg/luci-app-aurora-config` | `master` | `v1.2.5` |
| `LianXia233/luci-app-qmodem-generic` | `main` | `v3.0.0-r7` |
| `looong-cat/luci-app-netbird` | `main` | `v0.2.1-r1` |
| `nikkinikki-org/OpenWrt-momo` | `main` | `v1.2.2` |
| `sbwml/luci-app-mosdns` | `v5` | `v5.3.4-r15` |
| `sbwml/luci-app-openlist2` | `main` | `v4.2.9` |
| `sirpdboy/luci-app-ddns-go` | `main` | `v6.17.1` |
| `sirpdboy/luci-app-kucat-config` | `master` | `v2.2.1` |
| `sirpdboy/luci-app-netwizard` | `main` | `v2.1.5` |
| `sirpdboy/netspeedtest` | `main` | `v5.2.1` |
| `vernesong/OpenClash` | `master` | `v0.48.002` |
| `xiaodoudou/luci-app-uugamebooster` | `master` | `v2.3.1` |

## B. 仓库没有任何 tag（8 个）

| 仓库 | 分支 |
| --- | --- |
| `linkease/istore` | `main` |
| `linkease/nas-packages-luci` | `main` |
| `mchome/openwrt-vlmcsd` | `master` |
| `muink/luci-app-natmapt` | `master` |
| `muink/openwrt-natmapt` | `master` |
| `sbwml/luci-app-qbittorrent` | `master` |
| `sbwml/luci-app-quickfile` | `main` |
| `sbwml/luci-theme-argon` | `openwrt-25.12` |

## C. 有 tag 但分支已跑到前面（29 个）

| 仓库 | 分支 | tag 数量 | 最新 tag | 分支 SHA | tag SHA |
| --- | --- | --- | --- | --- | --- |
| `4IceG/luci-app-mini-diskmanager` | `main` | 25 | `1.0.29-r20260215` | `4b2b733` | `cd13ef6` |
| `anothaDev/luci-theme-vantage` | `main` | 18 | `v1.0.16` | `c8f0d04` | `bc3a59e` |
| `destan19/luci-app-harbor-file` | `main` | 2 | `v1.0.3` | `385151f` | `8295c88` |
| `eamonxg/luci-theme-aurora` | `master` | 17 | `v1.4.0` | `298dbcc` | `84c27b6` |
| `eamonxg/luci-theme-shadcn` | `main` | 6 | `v0.6.0` | `1830d0a` | `329405c` |
| `EasyTier/luci-app-easytier` | `main` | 7 | `v2.6.4` | `9c51d3f` | `bbe6b84` |
| `FUjr/QModem` | `main` | 25 | `v3.4.0_rc3.1` | `99553e5` | `cf0789d` |
| `LazuliKao/luci-theme-fluent` | `main` | 10 | `v1.0.9` | `e19720d` | `8229062` |
| `LianXia233/luci-app-airpi3000m-fancontrol` | `main` | 17 | `v20261028220935` | `7f12c38` | `599d076` |
| `LianXia233/luci-app-chfs` | `main` | 2 | `v1.0.1` | `9bf35c3` | `fe6b8d7` |
| `LianXia233/luci-app-fm350` | `main` | 5 | `v1.2.0` | `b644ae9` | `b955409` |
| `LianXia233/luci-app-h5000m-netmode` | `main` | 1 | `v1.8.5` | `ba29f1b` | `802b26d` |
| `LianXia233/luci-app-mt5700` | `main` | 63 | `v1.32.7` | `67cf21a` | `8ccd61b` |
| `LianXia233/luci-app-mt5700m` | `main` | 5 | `v3.2.0` | `c6d22ec` | `a4441db` |
| `LianXia233/luci-app-netmonitor` | `main` | 1 | `v1.6.1` | `1ef387b` | `4f6312b` |
| `linkease/openwrt-app-actions` | `main` | 1 | `release` | `0b1d943` | `fcd7f72` |
| `lisaac/luci-app-dockerman` | `master` | 28 | `v0.5.26` | `6fd9937` | `ab7e523` |
| `lisaac/luci-lib-docker` | `master` | 6 | `v0.3.4` | `98a6634` | `3876334` |
| `mchome/luci-app-vlmcsd` | `master` | 2 | `1.0.1` | `530a6ee` | `192bd9a` |
| `muink/openwrt-stuntman` | `master` | 2 | `v1.2.16-20230829` | `f915c1e` | `08d7bc1` |
| `nikkinikki-org/OpenWrt-nikki` | `main` | 91 | `v1.26.2` | `78e1a75` | `31339d5` |
| `Openwrt-Passwall/openwrt-passwall` | `main` | 80 | `26.11.3-1` | `82678e8` | `0b969d5` |
| `Openwrt-Passwall/openwrt-passwall2` | `main` | 59 | `26.11.3-1` | `7d6b5bc` | `176e27c` |
| `sbwml/luci-app-diskman` | `main` | 4 | `v1.0.0-r4` | `be87fcb` | `215a3d3` |
| `sirpdboy/luci-app-partexp` | `main` | 9 | `v2.0.5` | `ef79d6b` | `236187c` |
| `sirpdboy/luci-app-timecontrol` | `main` | 5 | `v3.2.4` | `52b8200` | `bc65dd3` |
| `sirpdboy/luci-theme-kucat` | `master` | 26 | `v3.3.2` | `1c8e7f7` | `9a6d6ed` |
| `VIKINGYFY/packages` | `main` | 3 | `gecoosac-2.2.20251015` | `8eb106a` | `8aad5f5` |
| `VizzleTF/luci-theme-footstrap` | `main` | 117 | `v0.14.20` | `bc938b6` | `2a96c34` |
