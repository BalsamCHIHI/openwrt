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
  DEPENDS:=+kmod-mac80211 +kmod-ath
  FILES:=\
	$(BUILD_DIR)/drivers/bus/mhi/core/mhi.ko \
  	$(BUILD_DIR)/net/qrtr/qrtr.ko \
	$(BUILD_DIR)/net/qrtr/qrtr-mhi.ko \
	$(BUILD_DIR)/drivers/net/ath11k/ath11k_pci.ko \
	$(BUILD_DIR)/drivers/net/ath11k/ath11k_core.ko
  AUTOLOAD:=$(call AutoProbe,ath11k)
endef

define Build/Compile
	$(BUILD_DIR)/drivers/bus/mhi/core/mhi.ko $(1)/lib/moduels/$(KERNEL_VERSION)/mhi.ko
  	$(BUILD_DIR)/net/qrtr/qrtr.ko $(1)/lib/moduels/$(KERNEL_VERSION)/qrtr.ko
	$(BUILD_DIR)/net/qrtr/qrtr-mhi.ko $(1)/lib/moduels/$(KERNEL_VERSION)/qrtr-mhi.ko
	$(BUILD_DIR)/drivers/net/ath11k/ath11k_pci.ko $(1)/lib/moduels/$(KERNEL_VERSION)/ath11k_pci.ko
	$(BUILD_DIR)/drivers/net/ath11k/ath11k_core.ko $(1)/lib/moduels/$(KERNEL_VERSION)/ath11k_core.ko
endef

$(eval $(call KernelPackage,ath11k))
