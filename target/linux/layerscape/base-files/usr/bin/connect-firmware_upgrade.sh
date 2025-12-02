#!/bin/sh

# Configuration & paths
SERVER="$(awk -F'ce_server=' '{print $2}' /proc/cmdline 2>/dev/null | awk '{print $1}')"
[ -z "$SERVER" ] && SERVER="172.100.1.1"

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"

# Remote resources
FIRMWARE_URL="http://$SERVER/downloads/openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sysupgrade.bin"
CHECKSUM_URL="http://$SERVER/downloads/sha256sums"

# Local files (kept for traceability)
BASE_DIR="/boot/connect-sysupgrade-tmp"
FW_FILE="$BASE_DIR/sysupgrade.bin"
SUM_FILE="$BASE_DIR/sha256sums"
LOG_FILE="$BASE_DIR/connect_sysupgrade_log"
CONTROL_FILE="$BASE_DIR/CONTROL"
PLATFORM_FILE="$BASE_DIR/platform.sh"

# Upload endpoint (single log upload)
LOG_UPLOAD_URL="http://$SERVER/cgi-bin/upload-raw.sh?filename=${HOSTNAME}-$(basename "$LOG_FILE")-${TIMESTAMP}"

# Prevents hangs on flaky links
WGET="wget -T 10 -q"

# mount /boot
mkdir -p "$BASE_DIR"
mount "/dev/mmcblk0p1" /boot

# Logging
log() {
    echo "$1" | tee -a "$LOG_FILE"
    logger -t connect-sysupgrade "$1"
    sync
}

log "> Triggered firmware upgrade script."

# Download firmware
log "Downloading firmware..."
$WGET -O "$FW_FILE" "$FIRMWARE_URL" || {
    log "Firmware download failed!"
    $WGET --post-file="$LOG_FILE" "$LOG_UPLOAD_URL" -O - || true
    exit 1
}

# Download sha256sums and verify checksum
log "Downloading checksum..."
$WGET -O "$SUM_FILE" "$CHECKSUM_URL" || {
    log "Checksum download failed!"
    $WGET --post-file="$LOG_FILE" "$LOG_UPLOAD_URL" -O - || true
    exit 1
}

FIRMWARE_URL_FILENAME="$(basename "$FIRMWARE_URL")"
EXPECTED_SHA="$(awk -v f="$FIRMWARE_URL_FILENAME" '{n=$2; sub(/^\*/, "", n); if (n==f) print $1}' "$SUM_FILE")"
ACTUAL_SHA="$(sha256sum "$FW_FILE" | awk '{print $1}')"

log "Expected SHA256: $EXPECTED_SHA"
log "Actual   SHA256: $ACTUAL_SHA"

if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    log "SHA256 mismatch or missing entry! Aborting upgrade."
    $WGET --post-file="$LOG_FILE" "$LOG_UPLOAD_URL" -O - || true
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
    # Print full CONTROL content into the log for traceability
    printf "%s\n" "----- BEGIN CONTROL FILE CONTENT -----" >> "$LOG_FILE"
    cat "$CONTROL_FILE" >> "$LOG_FILE"
    printf "%s\n" "----- END CONTROL FILE CONTENT -----" >> "$LOG_FILE"

    printf "%s\n" "----- BEGIN CONTROL FILE CONTENT -----" | logger -t connect-sysupgrade
    logger -t connect-sysupgrade < "$CONTROL_FILE"
    printf "%s\n" "----- END CONTROL FILE CONTENT -----" | logger -t connect-sysupgrade

    # Extract and print old and new values
    CTRL_SOURCE_DATE_EPOCH="$(awk -F'=' '/^SOURCE_DATE_EPOCH=/{print $2}' "$CONTROL_FILE")"
    CTRL_VERSION_FWREL="$(awk -F'=' '/^VERSION_FWREL=/{print $2}' "$CONTROL_FILE")"

    CURRENT_OPENWRT_BUILD_DATE="$( . /etc/os-release 2>/dev/null; echo "${OPENWRT_BUILD_DATE:-${BUILD_DATE:-0}}" )"
    CURRENT_OPENWRT_DEVICE_FIRMWARE_RELEASE="$( . /etc/os-release 2>/dev/null; echo "${OPENWRT_DEVICE_FIRMWARE_RELEASE:-unknown}" )"

    log "Running OPENWRT_BUILD_DATE : $CURRENT_OPENWRT_BUILD_DATE : $(date -d @"$CURRENT_OPENWRT_BUILD_DATE" 2>/dev/null || echo n/a)"
    log "New SOURCE_DATE_EPOCH      : $CTRL_SOURCE_DATE_EPOCH : $(date -d @"$CTRL_SOURCE_DATE_EPOCH" 2>/dev/null || echo n/a)"
    log "Running OPENWRT_DEVICE_FIRMWARE_RELEASE : $CURRENT_OPENWRT_DEVICE_FIRMWARE_RELEASE"
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

# Copy sysupgrade.bin to /tmp
[ -f "$FW_FILE" ] || { log "Firmware file missing!"; exit 1; }
log "Copy sysupgrade.bin to tmp..."
cp "$FW_FILE" /tmp/sysupgrade.bin

# Upload single log file
log "Uploading log file..."
log "> Running sysupgrade..."
$WGET --post-file="$LOG_FILE" "$LOG_UPLOAD_URL" -O - || true

# umount /boot
umount /boot

# Run sysupgrade
exec sysupgrade -v /tmp/sysupgrade.bin
