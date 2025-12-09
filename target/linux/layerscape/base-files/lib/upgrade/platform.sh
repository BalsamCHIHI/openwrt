#
# Copyright 2015-2019 Traverse Technologies
# Copyright 2020 NXP
#

RAMFS_COPY_BIN="md5sum cmp"
RAMFS_COPY_DATA=""

REQUIRE_IMAGE_METADATA=1

platform_do_upgrade_sdboot() {
	local diskdev partdev parttype=ext4
	local tar_file="$1"
	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mount -t $parttype -o rw,noatime "/dev/$partdev" /mnt 2>&1
		echo "Writing kernel..."
		tar xf $tar_file ${board_dir}/kernel -O > /mnt/fitImage
		umount /mnt
	fi

	echo "Erasing rootfs..."
	dd if=/dev/zero of=/dev/mmcblk0p2 bs=1M > /dev/null 2>&1
	echo "Writing rootfs..."
	tar xf $tar_file ${board_dir}/root -O  | dd of=/dev/mmcblk0p2 bs=512k > /dev/null 2>&1

}

# Map logical names to actual MTD partition labels
get_mtd_label() {
	case "$1" in
		pbl) echo "pbl" ;;
		uboot) echo "u-boot" ;;
		env) echo "env" ;;
		envbkp) echo "env-backup" ;;
		mc) echo "dpaa2-mc" ;;
		dpc) echo "dpaa2-dpc" ;;
		dpl) echo "dpaa2-dpl" ;;
		*) echo "" ;;
	esac
}

# Map logical names to actual MTD partition numbers
get_mtd_block_number() {
	case "$1" in
		pbl) echo "0" ;;
		uboot) echo "1" ;;
		env) echo "2" ;;
		envbkp) echo "3" ;;
		mc) echo "4" ;;
		dpc) echo "5" ;;
		dpl) echo "6" ;;
		*) echo "" ;;
	esac
}

dump_current_qspi_partitions() {
	local dump_current_qspi_dir="/boot/connect-sysupgrade-tmp/qspi-dump_current"
	mkdir -p "$dump_current_qspi_dir"

	echo "Dumping current QSPI partitions..."
	for name in pbl uboot mc dpc dpl; do
		local mtd_block="/dev/mtdblock$(get_mtd_block_number "$name")"
		local size_hex
		case "$name" in
			pbl)   size_hex="0x00100000" ;; # 1MB
			uboot) size_hex="0x00300000" ;; # 3MB
			mc)    size_hex="0x00300000" ;; # 3MB
			dpc)   size_hex="0x00100000" ;; # 1MB
			dpl)   size_hex="0x00100000" ;; # 1MB
		esac
		local size_dec=$((16#${size_hex#0x}))

		if [ -e "$mtd_block" ]; then
			dd if="$mtd_block" of="$dump_current_qspi_dir/${name}.current.bin" bs=1M count=$((size_dec / 1048576)) status=none conv=fsync
			sync
			echo "Dumped $name ($size_dec bytes)"
		else
			echo "Skipping $name: $mtd_block not found"
		fi
	done
}

verify_flash() {
	local part="$1" new_file="$2"
	local mtd_block="/dev/mtdblock$(get_mtd_block_number "$part")"
	local new_size blocks new_sha current_sha

	new_size=$(wc -c < "$new_file")
	blocks=$(( (new_size + 1048575) / 1048576 ))  # round up to 1 MiB blocks
	new_sha=$(md5sum "$new_file" | awk '{print $1}')

	# Read back same number of bytes from flash and compute md5
	current_sha=$(dd if="$mtd_block" bs=1M count=$blocks status=none conv=fsync 2>/dev/null | dd bs=1 count="$new_size" status=none conv=fsync | md5sum | awk '{print $1}')
	sync

	if [ "$new_sha" = "$current_sha" ]; then
		echo "Verified $part: md5 match"
	else
		echo "WARNING: Verification failed for $part!"
	fi
}

flash_qspi_partitions() {
	local tar_file="$1"
	local board_dir="$2"
	local variant="$3"

	local new_dir="/boot/connect-sysupgrade-tmp/qspi-new"
	mkdir -p "$new_dir"

	echo "Extracting and flashing QSPI partitions (variant=${variant})..."
	# Flash in safer order — critical boot first, PBL last
	for name in dpl dpc mc uboot pbl; do
		local file=""
		case "$name" in
			pbl)   file="${board_dir}/bootloader/atf-${variant}/bl2_qspi.pbl" ;;
			uboot) file="${board_dir}/bootloader/atf-${variant}/fip.bin" ;;
			mc)    file="${board_dir}/bootloader/dpaa2/mc_ls1088a_10.39.0.itb" ;;
			dpc)   file="${board_dir}/bootloader/dpaa2/dpc-backplane_mac2-phy_mac3_mac10.dtb" ;;
			dpl)   file="${board_dir}/bootloader/dpaa2/dpl-eth_mac2_mac10.dtb" ;;
		esac

		# Check presence in tarball (exact entry)
		if ! tar tf "$tar_file" | grep -qx "$file"; then
			echo "File for $name not found in sysupgrade archive, skipping."
			continue
		fi
		sync

		# Extract the new content
		tar xf "$tar_file" "$file" -O > "$new_dir/${name}.new.bin" || {
			echo "Failed to extract $file; skipping $name."
			continue
		}
		sync

		local current_file="/boot/connect-sysupgrade-tmp/qspi-dump_current/${name}.current.bin"
		local new_file="$new_dir/${name}.new.bin"

		# If no previous dump exists, flash directly
		if [ ! -s "$current_file" ]; then
			echo "No previous dump for $name; flashing directly..."
			mtd -e "$(get_mtd_label "$name")" write "$new_file" "$(get_mtd_label "$name")" || {
				echo "Error flashing $name"
				return 1
			}
			sync
			verify_flash "$name" "$new_file"
			continue
		fi

		# Compare only the first N bytes (size of new file) to avoid EOF noise
		local new_size
		new_size=$(wc -c < "$new_file")
		if cmp -s -n "$new_size" "$current_file" "$new_file"; then
			echo "Skipping $name: no changes in content prefix (size ${new_size} bytes)"
		else
			echo "Flashing $name..."
			mtd -e "$(get_mtd_label "$name")" write "$new_file" "$(get_mtd_label "$name")" || {
				echo "Error flashing $name"
				return 1
			}
			sync
			verify_flash "$name" "$new_file"
		fi
	done

	echo "QSPI update completed."
}

platform_do_upgrade_tqmls1088a_sdboot() {
	local diskdev partdev
	local tar_file="$1"
	local board_dir
	board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	# Mount /boot and update kernel + DTB
	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	# Boot partition: kernel + dtb
	if export_partdevice partdev 1; then
		mkdir -p /boot
		mount "/dev/$partdev" /boot

		echo "Writing Kernel..."
		tar xf "$tar_file" "${board_dir}/boot/Image" -O > /boot/Image || {
			echo "Kernel Image not found in archive: ${board_dir}/boot/Image"
		}
		sync

		echo "Writing DTB..."
		tar xf "$tar_file" "${board_dir}/boot/fsl-ls1088a-tqmls1088a-connect.dtb" -O > /boot/fsl-ls1088a-tqmls1088a-connect.dtb || {
			echo "DTB not found in archive: ${board_dir}/boot/fsl-ls1088a-tqmls1088a-connect.dtb"
		}
		sync

		umount /boot
	fi

	# RootFS
	if export_partdevice partdev 2; then
		# Clear first 16 MiB to remove current File System signatures (quick format behavior)
		echo "Quick-clearing superblock..."
		dd if=/dev/zero of="/dev/$partdev" bs=1M count=16 status=none conv=fsync
		sync

		echo "Writing RootFS..."
		tar xf "$tar_file" "${board_dir}/rootfs" -O | dd of="/dev/$partdev" bs=1M status=none conv=fsync
		sync
	fi

	# Variant detection
	local variant
	variant=$(awk -F'variant=' '{print $2}' /proc/cmdline | awk '{print $1}')
	echo "Detected variant: ${variant:-<none>}"

	if [ -z "$variant" ]; then
		echo "Error: Missing variant in kernel cmdline. Skipping QSPI flash."
		return 0
	fi
	case "$variant" in
		2gb|4gb) : ;;  # OK
		*) echo "Error: Unknown variant '$variant'. Skipping QSPI flash."; return 0 ;;
	esac

	# Boot partition
	if export_partdevice partdev 1; then
		mkdir -p /boot
		mount "/dev/$partdev" /boot
	
		# QSPI dump + flash + verify
		dump_current_qspi_partitions
		flash_qspi_partitions "$tar_file" "$board_dir" "$variant"

		umount /boot
	fi
}

platform_do_upgrade_traverse_slotubi() {
	part="$(awk -F 'ubi.mtd=' '{printf $2}' /proc/cmdline | sed -e 's/ .*$//')"
	echo "Active boot slot: ${part}"
	new_active_sys="b"

	if [ ! -z "${part}" ]; then
		if [ "${part}" = "ubia" ]; then
			CI_UBIPART="ubib"
		else
			CI_UBIPART="ubia"
			new_active_sys="a"
		fi
	fi
	echo "Updating UBI part ${CI_UBIPART}"
	fw_setenv "openwrt_active_sys" "${new_active_sys}"
	nand_do_upgrade "$1"
	return $?
}

platform_copy_config_sdboot() {
	local diskdev partdev parttype=ext4

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mount -t $parttype -o rw,noatime "/dev/$partdev" /mnt 2>&1
		echo "Saving config backup..."
		cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE"
		umount /mnt
	fi
}

platform_copy_config_tqmls1088a_sdboot() {
	local diskdev partdev

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mkdir -p /boot
		mount "/dev/$partdev" /boot

		echo "Saving config backup..."
		cp -af "$UPGRADE_BACKUP" "/boot/$BACKUP_FILE"
		sync

		umount /boot
	fi
}

platform_copy_config() {
	local board=$(board_name)

	case "$board" in
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb-sdboot | \
	fsl,lx2160a-rdb-sdboot)
		platform_copy_config_sdboot
		;;
	tq,ls1088a-tqmls1088a-mbls10xxa-sdboot | \
	moment,ls1088a-tqmls1088a-connect-sdboot)
		platform_copy_config_tqmls1088a_sdboot
		;;
	esac
}
platform_check_image() {
	local board=$(board_name)

	case "$board" in
	traverse,ten64)
		nand_do_platform_check "ten64-mtd" $1
		return $?
		;;
	fsl,ls1012a-frdm | \
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1012a-rdb | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb | \
	fsl,ls1088a-rdb-sdboot | \
	tq,ls1088a-tqmls1088a-mbls10xxa | \
	tq,ls1088a-tqmls1088a-mbls10xxa-sdboot | \
	moment,ls1088a-tqmls1088a-connect | \
	moment,ls1088a-tqmls1088a-connect-sdboot | \
	fsl,ls2088a-rdb | \
	fsl,lx2160a-rdb | \
	fsl,lx2160a-rdb-sdboot)
		return 0
		;;
	*)
		echo "Sysupgrade is not currently supported on $board"
		;;
	esac

	return 1
}
platform_do_upgrade() {
	local board=$(board_name)

	# Force the creation of fw_printenv.lock
	mkdir -p /var/lock
	touch /var/lock/fw_printenv.lock

	case "$board" in
	traverse,ten64)
		platform_do_upgrade_traverse_slotubi "${1}"
		;;
	fsl,ls1012a-frdm | \
	fsl,ls1012a-rdb | \
	fsl,ls1021a-twr | \
	fsl,ls1028a-rdb | \
	fsl,ls1043a-rdb | \
	fsl,ls1046a-frwy | \
	fsl,ls1046a-rdb | \
	fsl,ls1088a-rdb | \
	fsl,ls2088a-rdb | \
	fsl,lx2160a-rdb)
		PART_NAME=firmware
		default_do_upgrade "$1"
		;;
	fsl,ls1012a-frwy-sdboot | \
	fsl,ls1021a-iot-sdboot | \
	fsl,ls1021a-twr-sdboot | \
	fsl,ls1028a-rdb-sdboot | \
	fsl,ls1043a-rdb-sdboot | \
	fsl,ls1046a-frwy-sdboot | \
	fsl,ls1046a-rdb-sdboot | \
	fsl,ls1088a-rdb-sdboot | \
	fsl,lx2160a-rdb-sdboot)
		platform_do_upgrade_sdboot "$1"
		return 0
		;;
	tq,ls1088a-tqmls1088a-mbls10xxa-sdboot | \
	moment,ls1088a-tqmls1088a-connect-sdboot)
		platform_do_upgrade_tqmls1088a_sdboot "$1"
		return 0
		;;
	*)
		echo "Sysupgrade is not currently supported on $board"
		;;
	esac
}
