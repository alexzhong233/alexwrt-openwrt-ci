include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-1panel
PKG_VERSION:=1.1
PKG_RELEASE:=1

# 状态 / 安装 / 升级页面。真正干活的是 /usr/libexec/1panel-ctl，由固件
# files 覆盖层提供。
#
# +bash 是硬依赖：官方 install.sh 与它装出来的 1pctl 都是 bash 脚本，
# busybox ash 跑不了。
LUCI_TITLE:=1Panel 裸机版安装与状态
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +bash +curl

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
