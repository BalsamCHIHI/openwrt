#
# Copyright (C) 2022 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ath11k-firmware
PKG_VERSION:=2023.03.13
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=git@gitlab.com:interactive-mobility/connect/drivers/wireless/ath11k-firmware.git
PKG_SOURCE_VERSION:=32093573496f4a1ad7f1d9ec9dcce1747b4117b3
PKG_MIRROR_HASH:=7ee5adb97da4aff2a80a54a02290b59fb20302db03c4bcb16661f4345cc65e45

PKG_LICENSE_FILES:=LICENSE.qca_firmware

PKG_MAINTAINER:=Damien Meyer <damien@moment.tech>

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:
STRIP:=:

define Package/ath11k-firmware-default
  SECTION:=firmware
  CATEGORY:=Firmware
  URL:=$(PKG_SOURCE_URL)
  DEPENDS:=
endef

define Package/ath11k-firmware-qcn9074
$(Package/ath11k-firmware-default)
  TITLE:=QCN9074 ath11k firmware
endef

define Build/Compile

endef

define Package/ath11k-firmware-qcn9074/install
	$(INSTALL_DIR) $(1)/lib/firmware/ath11k/QCN9074/hw1.0/
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/QCN9074/hw1.0/* $(1)/lib/firmware/ath11k/QCN9074/hw1.0/
	$(INSTALL_DIR) $(1)/etc/modules.d/
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/etc/modules.d/55-ath11k $(1)/etc/modules.d/55-ath11k
	$(INSTALL_DIR) $(1)/etc/modules-boot.d
	ln -s ../modules.d/55-ath11k $(1)/etc/modules-boot.d/55-ath11k
endef

$(eval $(call BuildPackage,ath11k-firmware-qcn9074))
