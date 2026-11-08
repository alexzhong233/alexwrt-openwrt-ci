include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netbird-tools
PKG_VERSION:=1.0
PKG_RELEASE:=1

# 状态与操作页面的壳。真正的逻辑在 /usr/bin/niubialex-netbird 里，
# 由固件的 files 覆盖层提供，所以这里只需要 luci-base。
LUCI_TITLE:=NetBird 兼容守护状态与操作
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
