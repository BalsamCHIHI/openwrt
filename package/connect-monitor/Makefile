# OpenWrt Makefile for Syslog Monitoring Package

include $(TOPDIR)/rules.mk

PKG_NAME:=connect-monitor
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/connect-monitor
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Syslog monitoring client for OpenWrt devices
	URL:=
endef

define Package/connect-monitor/description
	Syslog monitoring client for OpenWrt devices.
	Collects hardware metrics (SFP, HWMon) and sends them to syslog.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/connect-monitor/install
	# Create directories
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin

	# Install monitoring scripts
	$(INSTALL_BIN) ./monitor_hwmon.sh $(1)/etc/init.d/monitor_hwmon
	$(INSTALL_BIN) ./monitor_sfp.sh $(1)/etc/init.d/monitor_sfp

	# Install print_all_sensors script
	$(INSTALL_BIN) ./monitor_print_all_sensors.sh $(1)/usr/bin/monitor_print_all_sensors
endef

$(eval $(call BuildPackage,connect-monitor))
