#
# LuCI support for WorkBuddy2API
#
# 只提供界面和控制入口，网关本体在 workbuddy2api 包里，靠 LUCI_DEPENDS 带进来。
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for WorkBuddy2API gateway
LUCI_DEPENDS:=+workbuddy2api +luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-workbuddy2api
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=niubiAlex

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
