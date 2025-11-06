# Layerscape LS1088A Firmware

This document describes the partitioning and memory mapping for the QSPI flash and eMMC storage on the Layerscape LS1088A system, as well as instructions for flashing the firmware.

## Firmware Layout

### QSPI Flash Layout (64MB) : ATF based Bootloader

```
+---------------------------+
| QSPI 64MB 0x04000000      |
+---------------------------+
| PBL (ATF + RCW)           | -- 0x00000000 - 0x000FFFFF : 1MB
|                           |    "../atf/build/tqmls1088a/debug/bl2_qspi.pbl"
+---------------------------+
| U_BOOT (FIP: ATF + U-Boot)| -- 0x00100000 - 0x003FFFFF : 3MB
|                           |    "../atf/build/tqmls1088a/debug/fip.bin"
+---------------------------+
| ENV                       | -- 0x00400000 - 0x0041FFFF : 128KB
|                           |    "0xFF"
+---------------------------+
| ENV_BACKUP                | -- 0x00420000 - 0x0043FFFF : 128KB
|                           |    "0xFF"
+---------------------------+
| GAP (unused)              | -- 0x00440000 - 0x004FFFFF : ~880KB
|                           |    "0xFF"
+---------------------------+
| DPAA2_MC                  | -- 0x00500000 - 0x007FFFFF : 3MB
|                           |    "../mc/ls1088a/mc_ls1088a_10.39.0.itb"
+---------------------------+
| DPAA2_DPC                 | -- 0x00800000 - 0x008FFFFF : 1MB
|                           |    "../mc-utils/config/ls1088a/tqmls1088a-connect/dpc-backplane_mac2-phy_mac3_mac10.dtb"
+---------------------------+
| DPAA2_DPL                 | -- 0x00900000 - 0x009FFFFF : 1MB
|                           |    "../mc-utils/config/ls1088a/tqmls1088a-connect/dpl-eth_mac2_mac10.dtb"
+---------------------------+
| Free Space                | -- 0x00A00000 - 0x03FFFFFF : ~54MB
|                           |    "0xFF"
+---------------------------+
```

### eMMC Layout (3.4 GiB / ~3.65 GB)

```
+---------------------------+
| eMMC 3.6GB                |
+---------------------------+
| Partition 1 (FAT)         | -- 64MB
| +---------------------+   |
| | Device Tree         |   |    "../openwrt/build_dir/target-aarch64_generic_musl/linux-layerscape_armv8_64b/image-fsl-ls1088a-tqmls1088a-connect.dtb"
| |                     |   |
| +---------------------+   |
| | KERNEL Image        |   |    "../openwrt/build_dir/target-aarch64_generic_musl/linux-layerscape_armv8_64b/Image"
| |                     |   |
| +---------------------+   |
+---------------------------+
| Partition 2 (SqFS/Ext4)   | -- 960MB = 1024MB - 64MB
| +---------------------+   |
| | OpenWrt ROOTFS      |   |    "../openwrt/bin/targets/layerscape/armv8_64b/openwrt-layerscape-armv8_64b-moment_tqmls1088a-connect-rootfs.tar.gz"
| |                     |   |
| +---------------------+   |
+---------------------------+
| Unallocated eMMC Space    | -- 2.6GB = 3.6GB - 64MB - 960MB
|                           |
+---------------------------+
```

### Component Details

#### QSPI : ATF based bootloader

- **pbl**: Reset Configuration Word and Pre-Boot Instructions + Arm Trusted Firmware BL21
- **u_boot**: Arm Trusted Firmware BL31 + Universal Bootloader BL33
- **env**: Environment variable for u-boot
- **env_backup**: A backup of environment variable for u-boot
- **dpaa2_mc**: Management Complex Firmware
- **dpaa2_dpc**: Data Path Acceleration Architecture Configuration
- **dpaa2_dpl**: Data Path Acceleration Architecture Layout

#### eMMC : OpenWRT

- **VFAT partition**: Device Tree Blob + Linux kernel image
- **SquashFS / Ext4 partition**: Root filesystem for OpenWRT OS

## Flashing Instructions

### Flashing Bootloader in QSPI and OS in eMMC via USB

#### Enable USB subsystem, List USB devices and List files
```
usb reset
ls usb 0
```

#### Load the Bootloader to DRAM and Flash it in the QSPI
```
load usb 0 0xA0000000 qspi-atf-2gb.bin
sf probe
sf update $fileaddr 0x0 $filesize
```

#### Load OpenWrt to DRAM and Flash it in the eMMC
```
load usb 0 0xA0000000 openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sdcard.img.gz
mmc info
gzwrite mmc 0 $fileaddr $filesize
```

#### Reset the Device and apply the changes
```
reset
```

---

### Flashing Bootloader in QSPI and OS in eMMC via TFTP

#### COMexpress (Server-Side)

##### Install TFTP Server
```
sudo apt update
sudo apt install tftpd-hpa
```

##### Configure TFTP Server
Edit the TFTP server configuration file:
```
sudo nano /etc/default/tftpd-hpa
```
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
```
Save and close the file.

##### Create TFTP Directory and Copy Files
```
sudo mkdir -p /srv/tftp
sudo cp qspi-atf-2gb.bin /srv/tftp
sudo cp openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sdcard.img.gz /srv/tftp
```

##### Enable, Restart and Check TFTP Service
```
sudo systemctl enable tftpd-hpa
sudo systemctl restart tftpd-hpa
sudo systemctl status tftpd-hpa
```

##### Reset the Layerscape to Access U-Boot
```
.~/susi/susi4Connect/pca9555apw-reset-layerscape
```

#### Layerscape (Client-Side)

After resetting the Layerscape, switch quickly to it's serial console.
Stop the Layerscape boot in **U-Boot** prompt by typing **"fgh"** when you see the countdown.

##### Verify the active interface (DPMAC2@xgmii, by default)
```
printenv ethact
```

##### Switch network interface for Firmware loading from external tftp server, if needed
```
setenv ethact DPMAC9@qsgmii
```

##### Set IP addresses
```
setenv ipaddr 172.100.1.2
setenv serverip 172.100.1.1
```

##### Ping the TFTP Server
```
ping 172.100.1.1
```

##### Load the Bootloader to DRAM and Flash it in the QSPI
```
tftpboot 0xA0000000 qspi-atf-2gb.bin
sf probe
sf update $fileaddr 0x0 $filesize
```

##### Load OpenWrt to DRAM and Flash it in the eMMC
```
tftpboot 0xA0000000 openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sdcard.img.gz
mmc info
gzwrite mmc 0 $fileaddr $filesize
```

##### Reset the Device and apply the changes
```
reset
```


![OpenWrt logo](include/logo.png)

OpenWrt Project is a Linux operating system targeting embedded devices. Instead
of trying to create a single, static firmware, OpenWrt provides a fully
writable filesystem with package management. This frees you from the
application selection and configuration provided by the vendor and allows you
to customize the device through the use of packages to suit any application.
For developers, OpenWrt is the framework to build an application without having
to build a complete firmware around it; for users this means the ability for
full customization, to use the device in ways never envisioned.

Sunshine!

## Download

Built firmware images are available for many architectures and come with a
package selection to be used as WiFi home router. To quickly find a factory
image usable to migrate from a vendor stock firmware to OpenWrt, try the
*Firmware Selector*.

* [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/)

If your device is supported, please follow the **Info** link to see install
instructions or consult the support resources listed below.

## 

An advanced user may require additional or specific package. (Toolchain, SDK, ...) For everything else than simple firmware download, try the wiki download page:

* [OpenWrt Wiki Download](https://openwrt.org/downloads)

## Development

To build your own firmware you need a GNU/Linux, BSD or macOS system (case
sensitive filesystem required). Cygwin is unsupported because of the lack of a
case sensitive file system.

### Requirements

You need the following tools to compile OpenWrt, the package names vary between
distributions. A complete list with distribution specific packages is found in
the [Build System Setup](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem)
documentation.

```
binutils bzip2 diff find flex gawk gcc-6+ getopt grep install libc-dev libz-dev
make4.1+ perl python3.7+ rsync subversion unzip which
```

### Quickstart

1. Run `./scripts/feeds update -a` to obtain all the latest package definitions
   defined in feeds.conf / feeds.conf.default

2. Run `./scripts/feeds install -a` to install symlinks for all obtained
   packages into package/feeds/

3. Run `make menuconfig` to select your preferred configuration for the
   toolchain, target system & firmware packages.

4. Run `make` to build your firmware. This will download all sources, build the
   cross-compile toolchain and then cross-compile the GNU/Linux kernel & all chosen
   applications for your target system.

### Related Repositories

The main repository uses multiple sub-repositories to manage packages of
different categories. All packages are installed via the OpenWrt package
manager called `opkg`. If you're looking to develop the web interface or port
packages to OpenWrt, please find the fitting repository below.

* [LuCI Web Interface](https://github.com/openwrt/luci): Modern and modular
  interface to control the device via a web browser.

* [OpenWrt Packages](https://github.com/openwrt/packages): Community repository
  of ported packages.

* [OpenWrt Routing](https://github.com/openwrt/routing): Packages specifically
  focused on (mesh) routing.

* [OpenWrt Video](https://github.com/openwrt/video): Packages specifically
  focused on display servers and clients (Xorg and Wayland).

## Support Information

For a list of supported devices see the [OpenWrt Hardware Database](https://openwrt.org/supported_devices)

### Documentation

* [Quick Start Guide](https://openwrt.org/docs/guide-quick-start/start)
* [User Guide](https://openwrt.org/docs/guide-user/start)
* [Developer Documentation](https://openwrt.org/docs/guide-developer/start)
* [Technical Reference](https://openwrt.org/docs/techref/start)

### Support Community

* [Forum](https://forum.openwrt.org): For usage, projects, discussions and hardware advise.
* [Support Chat](https://webchat.oftc.net/#openwrt): Channel `#openwrt` on **oftc.net**.

### Developer Community

* [Bug Reports](https://bugs.openwrt.org): Report bugs in OpenWrt
* [Dev Mailing List](https://lists.openwrt.org/mailman/listinfo/openwrt-devel): Send patches
* [Dev Chat](https://webchat.oftc.net/#openwrt-devel): Channel `#openwrt-devel` on **oftc.net**.

## License

OpenWrt is licensed under GPL-2.0
