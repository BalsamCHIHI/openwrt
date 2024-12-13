#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ath12k-firmware
PKG_SOURCE_DATE:=2025-02-11
PKG_SOURCE_VERSION:=ffd85db9b78e9428fc6e9846788aa8531b87f171
PKG_MIRROR_HASH:=f81389cc707ecb9526c1892044e89ecd783685c2eb0664584b21f4802abbe277
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://git.codelinaro.org/clo/ath-firmware/ath12k-firmware.git

PKG_LICENSE_FILES:=LICENSE.qca_firmware

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:
STRIP:=:

define Package/ath12k-firmware-default
  SECTION:=firmware
  CATEGORY:=Firmware
  URL:=$(PKG_SOURCE_URL)
  DEPENDS:=
endef

define Package/ath12k-firmware-qcn9274
$(Package/ath12k-firmware-default)
  TITLE:=QCN9274 ath12k firmware
endef

define Build/Compile

endef

define Package/ath12k-firmware-qcn9274/install
	$(INSTALL_DIR) $(1)/lib/firmware/ath12k/QCN9274/hw2.0

	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/QCN9274/hw2.0/1.4.1/WLAN.WBE.1.4.1-00199-QCAHKSWPL_SILICONZ-1/* \
		$(1)/lib/firmware/ath12k/QCN9274/hw2.0/

	$(INSTALL_DATA) $(PKG_BUILD_DIR)/QCN9274/hw2.0/board-2.bin \
		$(PKG_BUILD_DIR)/QCN9274/hw2.0/regdb.bin \
		$(1)/lib/firmware/ath12k/QCN9274/hw2.0/
endef

$(eval $(call BuildPackage,ath12k-firmware-qcn9274))
