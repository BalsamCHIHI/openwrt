#
# Copyright 2015-2019 Traverse Technologies
# Copyright 2020 NXP
#

RAMFS_COPY_BIN=""
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
		mc) echo "dpaa2-mc" ;;
		dpc) echo "dpaa2-dpc" ;;
		dpl) echo "dpaa2-dpl" ;;
		*) ;;
	esac
}

platform_do_upgrade_tqmls1088a_sdboot() {
	local diskdev partdev
	local tar_file="$1"
	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mkdir -p /boot
		mount "/dev/$partdev" /boot 2>&1
		echo "Erasing Kernel..."
		rm /boot/Image
		echo "Writing Kernel..."
		tar xf $tar_file ${board_dir}/Image -O > /boot/Image
		echo "Erasing DTB..."
		rm /boot/fsl-ls1088a-tqmls1088a-connect.dtb
		echo "Writing DTB..."
		tar xf $tar_file ${board_dir}/fsl-ls1088a-tqmls1088a-connect.dtb -O > /boot/fsl-ls1088a-tqmls1088a-connect.dtb
		umount /boot
	fi

	echo "Erasing RootFS..."
	dd if=/dev/zero of=/dev/mmcblk0p2 bs=1024 > /dev/null 2>&1
	echo "Writing RootFS..."
	tar xf $tar_file ${board_dir}/rootfs -O  | dd of=/dev/mmcblk0p2 bs=1024 > /dev/null 2>&1

	# Flash optional QSPI partitions
	for part in pbl uboot mc dpc dpl; do
		image_path="${board_dir}/${part}.bin"
		if tar tf "$tar_file" | grep -q "$image_path"; then
			tar xf "$tar_file" "$image_path" -O > "/tmp/${part}.bin"
			mtd_label=$(get_mtd_label "$part")
			if [ -n "$mtd_label" ]; then
				mtd erase "$mtd_label"
				mtd write "/tmp/${part}.bin" "$mtd_label"
			else
				echo "Error: Unknown MTD label for $part"
			fi
		fi
	done
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
		mount "/dev/$partdev" /boot 2>&1
		echo "Saving config backup..."
		cp -af "$UPGRADE_BACKUP" "/boot/$BACKUP_FILE"
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
