#
# Copyright (C) 2022 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ath11k
PKG_RELEASE:=$(AUTORELEASE)

PKG_MAINTAINER:=Damien Meyer <damien@moment.tech>

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/ath11k
  SUBMENU:=Wireless Drivers
  TITLE:=Atheros 802.11ax wireless cards support
  DEPENDS:=\
	+kmod-mac80211 \
	+kmod-ath \
	+@DRIVER_11N_SUPPORT \
	+@PCI_SUPPORT \
	+kmod-hwmon-core \
	+kmod-mhi-bus \
	+kmod-qrtr \
	+kmod-qrtr-mhi \
	+kmod-qmi-helpers
  	+kmod-other
  FILES:=\
	$(LINUX_DIR)/drivers/net/wireless/ath/ath11k/ath11k.ko \
	$(LINUX_DIR)/drivers/net/wireless/ath/ath11k/ath11k_pci.ko
  AUTOLOAD:=$(call AutoProbe,ath11k)
endef

define Build/Compile

endef

define Package/ath11k/install
	$(INSTALL_DIR) $(1)/lib/modules/$(LINUX_VERSION)
	$(INSTALL_DATA) $(LINUX_DIR)/drivers/bus/mhi/core/mhi.ko $(1)/lib/modules/$(LINUX_VERSION)/mhi.ko
	$(INSTALL_DATA) $(LINUX_DIR)/net/qrtr/qrtr.ko $(1)/lib/modules/$(LINUX_VERSION)/qrtr.ko
	$(INSTALL_DATA) $(LINUX_DIR)/net/qrtr/qrtr-mhi.ko $(1)/lib/modules/$(LINUX_VERSION)/qrtr-mhi.ko
	$(INSTALL_DATA) $(LINUX_DIR)/drivers/net/wireless/ath/ath11k/ath11k.ko $(1)/lib/modules/$(LINUX_VERSION)/ath11k.ko
	$(INSTALL_DATA) $(LINUX_DIR)/drivers/net/wireless/ath/ath11k/ath11k_pci.ko $(1)/lib/modules/$(LINUX_VERSION)/ath11k_pci.ko
endef

$(eval $(call KernelPackage,ath11k))
