SUBTARGET:=ipq95xx
FEATURES += source-only
BOARDNAME:=Qualcomm Atheros IPQ95xx
CPU_TYPE:=cortex-a73

KERNEL_PATCHVER:=6.12

define Target/Description
	Build firmware images for Qualcomm Atheros IPQ95xx based boards.
endef

DEFAULT_PACKAGES+= -kmod-ath11k-ahb uboot-envtools
