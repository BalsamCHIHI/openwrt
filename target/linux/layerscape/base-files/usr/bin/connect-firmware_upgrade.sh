#!/bin/sh

# Configuration & paths
SERVER="$(awk -F'ce_server=' '{print $2}' /proc/cmdline 2>/dev/null | awk '{print $1}')"
[ -z "$SERVER" ] && SERVER="172.100.1.1"

# Remote resources
FIRMWARE_URL="http://$SERVER/downloads/openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sysupgrade.bin"
CHECKSUM_URL="http://$SERVER/downloads/sha256sums"

# Local files (kept for traceability)
BASE_DIR="/tmp/connect-firmware_upgrade-tmp"
FW_FILE="$BASE_DIR/sysupgrade.bin"
SUM_FILE="$BASE_DIR/sha256sums"
CONTROL_FILE="$BASE_DIR/CONTROL"
PLATFORM_FILE="$BASE_DIR/platform.sh"

# Prevents hangs on flaky links
WGET="wget -T 10 -q"

mkdir -p "$BASE_DIR"

# Logging
log() {
    echo "$1"
    logger -t connect-firmware_upgrade "$1"
}

log "> Running Connect Firmware Upgrade Script..."

# Download firmware
log "Downloading firmware..."
$WGET -O "$FW_FILE" "$FIRMWARE_URL" || {
    log "Firmware download failed!"
    exit 1
}

# Download sha256sums and verify checksum
log "Downloading checksum..."
$WGET -O "$SUM_FILE" "$CHECKSUM_URL" || {
    log "Checksum download failed!"
    exit 1
}

FIRMWARE_URL_FILENAME="$(basename "$FIRMWARE_URL")"
EXPECTED_SHA="$(awk -v f="$FIRMWARE_URL_FILENAME" '{n=$2; sub(/^\*/, "", n); if (n==f) print $1}' "$SUM_FILE")"
ACTUAL_SHA="$(sha256sum "$FW_FILE" | awk '{print $1}')"

log "Expected SHA256: $EXPECTED_SHA"
log "Actual   SHA256: $ACTUAL_SHA"

if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    log "SHA256 mismatch or missing entry! Aborting upgrade."
    exit 1
fi

log "SHA256 verified successfully."

# Extract CONTROL file from sysupgrade image (BusyBox tar compatible)
CONTROL_PATH="$(tar -tf "$FW_FILE" 2>/dev/null | grep -E '/CONTROL$' | head -n1 || true)"
if [ -n "$CONTROL_PATH" ]; then
    tar -xOf "$FW_FILE" "$CONTROL_PATH" > "$CONTROL_FILE" 2>/dev/null || rm -f "$CONTROL_FILE"
fi

# Print CONTROL into the log
if [ ! -s "$CONTROL_FILE" ]; then
    log "CONTROL not found in sysupgrade image."
    exit 1
else
    # Extract and print current and new values
    CTRL_SOURCE_DATE_EPOCH="$(awk -F'=' '/^SOURCE_DATE_EPOCH=/{print $2}' "$CONTROL_FILE")"
    CTRL_VERSION_FWREL="$(awk -F'=' '/^VERSION_FWREL=/{print $2}' "$CONTROL_FILE")"

    CURRENT_OPENWRT_BUILD_DATE="$( . /etc/os-release 2>/dev/null; echo "${OPENWRT_BUILD_DATE:-${BUILD_DATE:-0}}" )"
    CURRENT_OPENWRT_DEVICE_FIRMWARE_RELEASE="$( . /etc/os-release 2>/dev/null; echo "${OPENWRT_DEVICE_FIRMWARE_RELEASE:-unknown}" )"

    log "Current OPENWRT_BUILD_DATE : $CURRENT_OPENWRT_BUILD_DATE : $(date -d @"$CURRENT_OPENWRT_BUILD_DATE" 2>/dev/null || echo n/a)"
    log "New SOURCE_DATE_EPOCH      : $CTRL_SOURCE_DATE_EPOCH : $(date -d @"$CTRL_SOURCE_DATE_EPOCH" 2>/dev/null || echo n/a)"
    log "Current OPENWRT_DEVICE_FIRMWARE_RELEASE : $CURRENT_OPENWRT_DEVICE_FIRMWARE_RELEASE"
    log "New VERSION_FWREL                       : $CTRL_VERSION_FWREL"
fi

# Extract platform.sh file from sysupgrade image (BusyBox tar compatible)
PLATFORM_PATH="$(tar -tf "$FW_FILE" 2>/dev/null | grep -E '/platform.sh$' | head -n1 || true)"
if [ -n "$PLATFORM_PATH" ]; then
    tar -xOf "$FW_FILE" "$PLATFORM_PATH" > "$PLATFORM_FILE" 2>/dev/null || rm -f "$PLATFORM_FILE"
fi

# Update platform.sh for sysupgrade compatibility
if [ ! -s "$PLATFORM_FILE" ]; then
    log "platform.sh not found in sysupgrade image."
    exit 1
else
    log "Updating platform.sh for sysupgrade compatibility..."
    cp "$PLATFORM_FILE" /lib/upgrade/platform.sh
    chmod 755 /lib/upgrade/platform.sh
fi

# Run sysupgrade
log "> Running sysupgrade Command..."
exec sysupgrade -v -F "$FW_FILE"
