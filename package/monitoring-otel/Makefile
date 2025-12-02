# OpenWrt Makefile for Syslog Monitoring Package

include $(TOPDIR)/rules.mk

PKG_NAME:=monitoring-otel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/monitoring-otel
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Syslog monitoring client for OpenWrt devices
	URL:=
endef

define Package/monitoring-otel/description
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

define Package/monitoring-otel/install
	# Create directories
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin
		
	# Install monitoring scripts
	$(INSTALL_BIN) ./sfp_monitoring/sfp_network_otel.sh $(1)/etc/init.d/sfp_monitor
	$(INSTALL_BIN) ./hwmon_monitoring/hwmon_network_otel.sh $(1)/etc/init.d/hwmon_monitor

	# Install print_all_sensors script
	$(INSTALL_BIN) ./print_all_sensors.sh $(1)/usr/bin/print_all_sensors
endef

$(eval $(call BuildPackage,monitoring-otel))
