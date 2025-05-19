#
# Monitoring package Makefile
#

include $(TOPDIR)/rules.mk

PKG_NAME:=monitoring
PKG_RELEASE:=1
PKG_MAINTAINER:=Artur Kambulov

include $(INCLUDE_DIR)/package.mk

define Package/monitoring
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Hardware monitoring Script
endef

define Package/monitoring/description
	custom monitoring script for HW
endef

define Build/Compile
	true
endef

define Package/monitoring/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/monitoring
	$(INSTALL_BIN) ./monitoring_init $(1)/etc/init.d/monitoring_init
	$(INSTALL_BIN) ./sfp_monitoring/sfp_network.sh $(1)/etc/init.d/monitoring_sfp
	$(INSTALL_BIN) ./hwmon_monitoring/hwmon_network.sh $(1)/etc/init.d/monitoring_hwmon
	$(INSTALL_BIN) ./monitoring_server.sh $(1)/etc/init.d/monitoring_server
	$(INSTALL_BIN) ./monitoring_parser.sh $(1)/usr/bin/monitoring_parser.sh
endef

$(eval $(call BuildPackage,monitoring))
