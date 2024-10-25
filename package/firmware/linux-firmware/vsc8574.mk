Package/vsc8574-firmware = $(call Package/firmware-default,vsc8574 firmware)
define Package/vsc8574-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/microchip
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/microchip/mscc_vsc8574_revb_int8051_29e8.bin \
		$(1)/lib/firmware/microchip/mscc_vsc8574_revb_int8051_29e8.bin
endef
$(eval $(call BuildPackage,vsc8574-firmware))
