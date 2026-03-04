
#
# Factory tests package 
#

include $(TOPDIR)/rules.mk

PKG_NAME:=factory-test
PKG_RELEASE:=1
PKG_MAINTAINER:=Artur Kambulov

AVIONICS_DIR:=$(abspath $(TOPDIR)/../avionics)
AVIONICS_BUILD_BIN:=$(AVIONICS_DIR)/_build/moment_board_f722.bin

include $(INCLUDE_DIR)/package.mk

define Package/factory-test
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Hardware  factory-test scripts
endef

define Package/factory-test/description
	factory HW tests done on first boot
endef

define Build/Compile
	true
endef

# Set DEVICE_ROLE to "DUT" or "TESTER" at build time:
#   make package/factory-test/compile DEVICE_ROLE=TESTER
DEVICE_ROLE ?= DUT

define Package/factory-test/install
	$(INSTALL_DIR) $(1)/etc/factory-test
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/lib/firmware/avionics

ifeq ($(DEVICE_ROLE),DUT)
	#====   DUT   =====
	$(INSTALL_BIN) ./boot_DUT_process.sh	 $(1)/etc/init.d/boot_factory_test
	$(INSTALL_BIN) ./stm32/stm32_flash.sh	 $(1)/usr/bin/stm32_flash.sh
	@if [ ! -f "$(AVIONICS_BUILD_BIN)" ]; then \
		echo "ERROR: Missing avionics binary: $(AVIONICS_BUILD_BIN)"; \
		exit 1; \
	fi
	$(CP) $(AVIONICS_BUILD_BIN) 			 $(1)/lib/firmware/avionics/moment_board_f722.bin
endif

ifeq ($(DEVICE_ROLE),TESTER)
	#==== TESTER ======
	$(INSTALL_BIN) ./factory-test			 $(1)/etc/config/factory-test
	$(INSTALL_BIN) ./switch_wifi_fw.sh		 $(1)/usr/bin/switch_wifi_fw.sh
	$(INSTALL_BIN) ./network_iperf_tester_server.sh  $(1)/usr/bin/network_iperf_server.sh
	$(INSTALL_BIN) ./network_iperf_tester_wap.sh	 $(1)/usr/bin/network_iperf_wap.sh
	$(INSTALL_BIN) ./boot_TESTER_process.sh		 $(1)/etc/init.d/boot_factory_test
endif
endef

$(eval $(call BuildPackage,factory-test))
