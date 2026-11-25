# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-emmc-health
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_LICENSE:=MIT
PKG_MAINTAINER:=Alex Zhong <alexzhong233@users.noreply.github.com>

LUCI_TITLE:=eMMC Health & Lifetime Monitor
LUCI_DESCRIPTION:=LuCI status overview widget and detail page for eMMC lifetime estimation, Pre-EOL status, and I/O write monitoring.
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +mmc-utils

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
