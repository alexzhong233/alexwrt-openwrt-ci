include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-1panel
PKG_VERSION:=1.0
PKG_RELEASE:=1

# 只是状态与操作页面的壳。真正干活的是 /usr/libexec/1panel-ctl，由固件
# files 覆盖层提供，所以这里不依赖 docker 包（没装 Docker 时页面自己会提示）。
LUCI_TITLE:=1Panel 容器状态与操作
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
