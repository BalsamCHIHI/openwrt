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

platform_do_upgrade_tqmls1088a_sdboot() {
	local diskdev partdev
	local tar_file="$1"
	local board_dir=$(tar tf "$tar_file" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	if export_partdevice partdev 1; then
		mkdir -p /boot
		mount "/dev/$partdev" /boot
		echo "Writing os-release..."
		tar xf "$tar_file" "${board_dir}/os-release" -O > /boot/os-release
		echo "Writing Kernel..."
		tar xf "$tar_file" "${board_dir}/Image" -O > /boot/Image
		echo "Writing DTB..."
		tar xf "$tar_file" "${board_dir}/fsl-ls1088a-tqmls1088a-connect.dtb" -O > /boot/fsl-ls1088a-tqmls1088a-connect.dtb
		umount /boot
	fi

	echo "Erasing RootFS..."
	dd if=/dev/zero of=/dev/mmcblk0p2 bs=1024
	echo "Writing RootFS..."
	tar xf "$tar_file" "${board_dir}/rootfs" -O | dd of=/dev/mmcblk0p2 bs=1024

	# Detect variant from kernel cmdline
	local variant
	variant=$(awk -F'variant=' '{print $2}' /proc/cmdline | awk '{print $1}')
	echo "variant: $variant"

	local qspi_bin=""
	if [ "$variant" = "2gb" ]; then
		qspi_bin="${board_dir}/qspi-atf-2gb.bin"
	elif [ "$variant" = "4gb" ]; then
		qspi_bin="${board_dir}/qspi-atf-4gb.bin"
	else
		echo "Error: Unknown or missing variant in kernel cmdline. Skipping QSPI flash to avoid bricking."
		return 0
	fi

	# Only proceed if the QSPI binary exists in the sysupgrade tar
	if tar tf "$tar_file" | grep -q "$qspi_bin"; then
		echo "Extracting QSPI partitions from Full binary ($qspi_bin)..."
		tar xf "$tar_file" "$qspi_bin" -O > /tmp/qspi-full.bin

		# Partition info: name, offset (bytes), size (bytes)
		# Format: name:offset:size
		local partitions="\
pbl:0x00000000:0x00100000
uboot:0x00100000:0x00300000
mc:0x00500000:0x00300000
dpc:0x00800000:0x00100000
dpl:0x00900000:0x00100000"

		echo "Flashing QSPI partitions..."
		echo "$partitions" | while IFS=: read -r name offset size; do
			# Convert offset and size from hex to decimal
			offset_dec=$((16#${offset#0x}))
			size_dec=$((16#${size#0x}))
			# Get MTD label and block number
			mtd_label=$(get_mtd_label "$name")
			mtd_block_num=$(get_mtd_block_number "$name")
			mtd_block="/dev/mtdblock${mtd_block_num}"
			# Skip if label or block number is missing
			if [ -z "$name" ] || [ -z "$mtd_label" ] || [ -z "$mtd_block_num" ]; then
				echo "Skipping $name: missing MTD label or block number"
				continue
			fi
			# Check if mtdblock device exists
			if [ ! -e "$mtd_block" ]; then
				echo "Skipping $name: $mtd_block not found"
				continue
			fi
			echo "  - $name ($mtd_label): offset=$offset size=$size"
			# Extract new partition slice from full binary
			dd if=/tmp/qspi-full.bin of=/tmp/${name}.new.bin bs=1 skip=$offset_dec count=$size_dec iflag=skip_bytes,count_bytes
			# Dump current partition content
			dd if="$mtd_block" of="/tmp/${name}.old.bin" bs=1 count=$size_dec
			# Compare old and new
			if cmp /tmp/${name}.old.bin /tmp/${name}.new.bin; then
				echo "Skipping $name: no changes"
			else
				echo "Updating $name: content differs"
				mtd write /tmp/${name}.new.bin "$mtd_label"
			fi
		done
	else
		echo "No QSPI binary ($qspi_bin) found in sysupgrade archive, skipping QSPI flash."
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
