#
# Copyright (C) 2021 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

QRTR_MENU:=Qualcomm IPC Router support

define KernelPackage/qrtr
  SUBMENU:=$(QRTR_MENU)
  TITLE:=Qualcomm IPC Router support
  KCONFIG:=CONFIG_QRTR
  FILES:= \
       $(LINUX_DIR)/net/qrtr/qrtr.ko \
       $(LINUX_DIR)/net/qrtr/ns.ko
endef

define KernelPackage/qrtr/description
  Kernel support for Qualcomm IPC Router
endef

$(eval $(call KernelPackage,qrtr))

define KernelPackage/qrtr-mhi
  SUBMENU:=$(QRTR_MENU)
  TITLE:=MHI IPC Router channels
  KCONFIG:=CONFIG_QRTR_MHI
  DEPENDS:=+kmod-mhi-bus +kmod-qrtr
  FILES:= $(LINUX_DIR)/net/qrtr/qrtr-mhi.ko
endef

define KernelPackage/qrtr-mhi/description
  Kernel support for MHI IPC Router channels
endef

$(eval $(call KernelPackage,qrtr-mhi))

define KernelPackage/qrtr-tun
  SUBMENU:=$(QRTR_MENU)
  TITLE:=TUN device for Qualcomm IPC Router
  KCONFIG:=CONFIG_QRTR_TUN
  DEPENDS:=+kmod-qrtr
  FILES:= $(LINUX_DIR)/net/qrtr/qrtr-tun.ko
endef

define KernelPackage/qrtr-tun/description
  Kernel support for TUN device for Qualcomm IPC Router
endef

$(eval $(call KernelPackage,qrtr-tun))
