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
PKG_SOURCE_URL:=https://gitlab.com/interactive-mobility/connect/drivers/wireless/ath11k-firmware.git
PKG_SOURCE_VERSION:=fe07efe2795738419f307ba89625cab58f77ced1
PKG_MIRROR_HASH:=b497ed6d16dfabd55a66e8a4bddcec9cd069c803d6630c02314be5cfee12a530

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
	$(INSTALL_DIR) $(1)/lib/firmware/ath11k/QCN9074/hw1.0
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/QCN9074/hw1.0/* $(1)/lib/firmware/ath11k/QCN9074/hw1.0/
endef

$(eval $(call BuildPackage,ath11k-firmware-qcn9074))
