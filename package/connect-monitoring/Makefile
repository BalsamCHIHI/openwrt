# OpenWrt Makefile for Syslog Monitoring Package

include $(TOPDIR)/rules.mk

PKG_NAME:=connect-monitoring
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/connect-monitoring
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Syslog monitoring client for OpenWrt devices
	URL:=
endef

define Package/connect-monitoring/description
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

define Package/connect-monitoring/install
	# Create directories
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/var/monitoring

	# Install monitoring services
	$(INSTALL_BIN) ./monitoring_hwmon.sh $(1)/etc/init.d/monitoring_hwmon
	$(INSTALL_BIN) ./monitoring_sfp.sh $(1)/etc/init.d/monitoring_sfp
	$(INSTALL_BIN) ./monitoring_qspi_setup $(1)/etc/init.d/monitoring_qspi_setup

	# Install print_all_sensors script
	$(INSTALL_BIN) ./monitoring_print_all_sensors.sh $(1)/usr/bin/monitoring_print_all_sensors
endef

$(eval $(call BuildPackage,connect-monitoring))
