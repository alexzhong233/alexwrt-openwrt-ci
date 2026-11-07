include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nss-status
PKG_VERSION:=1.0
PKG_RELEASE:=1

# 这个页面读的是 nss-wifi-drv 的 debugfs。上游用 qca-nss-drv 的变体没有这些
# 节点，所以依赖里不写死，由运行时判断是否存在。
LUCI_TITLE:=NSS Wi-Fi offload status
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +nss-firmware

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
