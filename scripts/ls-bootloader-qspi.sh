#!/bin/bash

set -e
set -u
set -o pipefail
#set -x

# Binary properties
BIN_DIR="bin/targets/layerscape/armv8_64b"
BOOTLOADER_DIR="$BIN_DIR/bootloader"
BOOTLOADER_ATF_2GB_DIR="$BOOTLOADER_DIR/atf-2gb"
BOOTLOADER_ATF_4GB_DIR="$BOOTLOADER_DIR/atf-4gb"
BOOTLOADER_DPAA2_DIR="$BOOTLOADER_DIR/dpaa2"
BOOTLOADER_SIZE_MB=64
BOOTLOADER_2GB_FILE="$BOOTLOADER_DIR/bootloader-2gb-qspi.bin"
BOOTLOADER_4GB_FILE="$BOOTLOADER_DIR/bootloader-4gb-qspi.bin"

# Input files
PBL_2GB_FILE="../atf/build/tqmls1088a/debug/bl2_qspi.pbl"
PBL_4GB_FILE="../atf/build/tqmls1088a_4gb/debug/bl2_qspi.pbl"
U_BOOT_2GB_FILE="../atf/build/tqmls1088a/debug/fip.bin"
U_BOOT_4GB_FILE="../atf/build/tqmls1088a_4gb/debug/fip.bin"
DPAA2_MC_FILE="../mc/ls1088a/mc_ls1088a_10.39.0.itb"
DPAA2_DPC_FILE="../mc-utils/config/ls1088a/tqmls1088a-connect/dpc-backplane_mac2-phy_mac3_mac10.dtb"
DPAA2_DPL_FILE="../mc-utils/config/ls1088a/tqmls1088a-connect/dpl-eth_mac2_mac10.dtb"

# Create directories
mkdir -p "$BOOTLOADER_ATF_2GB_DIR" "$BOOTLOADER_ATF_4GB_DIR" "$BOOTLOADER_DPAA2_DIR"

# List of required files
required_atf_2gb_files=(
  "$PBL_2GB_FILE"
  "$U_BOOT_2GB_FILE"
)
required_atf_4gb_files=(
  "$PBL_4GB_FILE"
  "$U_BOOT_4GB_FILE"
)
required_dpaa2_files=(
  "$DPAA2_MC_FILE"
  "$DPAA2_DPC_FILE"
  "$DPAA2_DPL_FILE"
)

# Function to check files
check_files_exist() {
  local files=("$@")
  local missing=()

  for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
      missing+=("$file")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "❌ Missing files:"
    for f in "${missing[@]}"; do
      echo "   - $f"
    done
    return 1
  fi

  return 0
}

# Function to copy files
copy_files() {
  local target_dir="$1"
  shift
  local files=("$@")

  echo "Copying files to $target_dir..."
  for file in "${files[@]}"; do
    cp "$file" "$target_dir/"
  done
}

# --- Check all files ---
echo "🔍 Checking required files..."
check_files_exist "${required_atf_2gb_files[@]}" || exit 1
check_files_exist "${required_atf_4gb_files[@]}" || exit 1
check_files_exist "${required_dpaa2_files[@]}" || exit 1
echo "✅ All required files exist."

# --- Copy files after successful check ---
copy_files "$BOOTLOADER_ATF_2GB_DIR" "${required_atf_2gb_files[@]}"
copy_files "$BOOTLOADER_ATF_4GB_DIR" "${required_atf_4gb_files[@]}"
copy_files "$BOOTLOADER_DPAA2_DIR" "${required_dpaa2_files[@]}"
echo "✅ All files copied successfully."

# Offsets in bytes
PBL_2GB_OFFSET=0x00000000
PBL_4GB_OFFSET=0x00000000
U_BOOT_2GB_OFFSET=0x00100000
U_BOOT_4GB_OFFSET=0x00100000
DPAA2_MC_OFFSET=0x00500000
DPAA2_DPC_OFFSET=0x00800000
DPAA2_DPL_OFFSET=0x00900000

# Sizes in bytes
PBL_SIZE=0x00100000
U_BOOT_SIZE=0x00300000
ENV_SIZE=0x00020000
ENV_BACKUP_SIZE=0x00020000
DPAA2_MC_SIZE=0x00300000
DPAA2_DPC_SIZE=0x00100000
DPAA2_DPL_SIZE=0x00100000

create_and_verify_binary() {
  local variant="$1"
  local binary_file="$2"
  local pbl_file="$3"
  local uboot_file="$4"

  echo "🔧 Creating Bootloader QSPI binary for $variant..."

  # Save previous hash
  local previous_hash=""
  if [ -f "$binary_file" ]; then
    previous_hash=$(md5sum "$binary_file" | awk '{print $1}')
    echo "Previous $variant binary hash: $previous_hash"
  fi

  # Cleanup
  rm -f "$binary_file"

  # Create empty binary filled with 0xFF
  dd if=/dev/zero bs=1M count=$BOOTLOADER_SIZE_MB status=progress | tr '\0' '\377' > "$binary_file"

  # Write components
  local pbl_offset_var="PBL_${variant}_OFFSET"
  local uboot_offset_var="U_BOOT_${variant}_OFFSET"

  dd if="$pbl_file" of="$binary_file" bs=1 seek=$(( ${!pbl_offset_var} )) conv=notrunc status=progress
  dd if="$uboot_file" of="$binary_file" bs=1 seek=$(( ${!uboot_offset_var} )) conv=notrunc status=progress
  dd if="$DPAA2_MC_FILE" of="$binary_file" bs=1 seek=$((DPAA2_MC_OFFSET)) conv=notrunc status=progress
  dd if="$DPAA2_DPC_FILE" of="$binary_file" bs=1 seek=$((DPAA2_DPC_OFFSET)) conv=notrunc status=progress
  dd if="$DPAA2_DPL_FILE" of="$binary_file" bs=1 seek=$((DPAA2_DPL_OFFSET)) conv=notrunc status=progress

  # Info
  file "$binary_file"
  ls -alh "$binary_file"

  echo "🔍 Verifying binary: $binary_file"

  # Define components to verify for this variant
  local verify_components=(
    "PBL_${variant}"
    "U_BOOT_${variant}"
    "DPAA2_MC"
    "DPAA2_DPC"
    "DPAA2_DPL"
  )

  for BASE in "${verify_components[@]}"; do
    local VAR="${BASE}_FILE"
    local OFFSET_VAR="${BASE}_OFFSET"

    if [ -z "${!VAR:-}" ] || [ -z "${!OFFSET_VAR:-}" ]; then
      echo "⚠️  Skipping $BASE: missing file or offset"
      continue
    fi

    local FILE="${!VAR}"
    local OFFSET_DEC=$(( ${!OFFSET_VAR} ))

    if [ ! -f "$FILE" ]; then
      echo "❌ Missing source file: $FILE"
      continue
    fi

    local ACTUAL_FILE_SIZE
    ACTUAL_FILE_SIZE=$(stat -c%s "$FILE")
    dd if="$binary_file" of="/tmp/${BASE}.bin" bs=1 skip=$OFFSET_DEC count=$ACTUAL_FILE_SIZE status=progress

    local ORIG_HASH
    ORIG_HASH=$(md5sum "$FILE" | awk '{print $1}')
    local BIN_HASH
    BIN_HASH=$(md5sum "/tmp/${BASE}.bin" | awk '{print $1}')

    if [ "$ORIG_HASH" == "$BIN_HASH" ]; then
      echo "✅ $BASE: MD5 match"
    else
      echo "❌ $BASE: MD5 mismatch"
      echo "    Source: $FILE"
      echo "    Offset: $OFFSET_DEC"
      echo "    Size  : $ACTUAL_FILE_SIZE"
    fi
  done

  printf "🔒 MD5 of full binary: "
  md5sum "$binary_file"

  # Compare hashes
  local new_hash
  new_hash=$(md5sum "$binary_file" | awk '{print $1}')
  if [ -n "$previous_hash" ] && [ "$previous_hash" == "$new_hash" ]; then
    echo "⚠️  Warning: The new $variant binary is identical to the previous one."
  fi

  echo "✅ Bootloader QSPI binary for $variant created and verified successfully."
}

# Build and verify both variants
create_and_verify_binary "2GB" "$BOOTLOADER_2GB_FILE" "$PBL_2GB_FILE" "$U_BOOT_2GB_FILE"
create_and_verify_binary "4GB" "$BOOTLOADER_4GB_FILE" "$PBL_4GB_FILE" "$U_BOOT_4GB_FILE"
