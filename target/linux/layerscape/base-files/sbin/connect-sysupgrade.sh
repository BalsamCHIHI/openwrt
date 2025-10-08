#!/bin/sh

FIRMWARE_URL="http://10.10.0.190/downloads/openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sysupgrade.bin"
CHECKSUM_URL="http://10.10.0.190/downloads/sha256sums"
PROFILE_URL="http://10.10.0.190/downloads/profiles.json"
TMP_FW="/tmp/sysupgrade.bin"
TMP_SUM="/tmp/sha256sums"
TMP_PROFILE="/tmp/profiles.json"
TMP_LOG="/tmp/connect-sysupgrade.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(cat /proc/sys/kernel/hostname)
LOG_UPLOAD_URL="http://10.10.0.190/cgi-bin/upload-raw.sh?filename=connect_sysupgrade-${HOSTNAME}-$TIMESTAMP.log"

log() {
    echo "$1" | tee -a "$TMP_LOG"
    logger -t connect-sysupgrade "$1"
}

log "Triggered firmware upgrade script"

# Download firmware
log "Downloading firmware..."
wget -O "$TMP_FW" "$FIRMWARE_URL" || {
    log "Firmware download failed!"
    wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# Download checksum
log "Downloading checksum..."
wget -O "$TMP_SUM" "$CHECKSUM_URL" || {
    log "Checksum download failed!"
    wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# Verify checksum
EXPECTED_SHA=$(grep "$(basename "$TMP_FW")" "$TMP_SUM" | awk '{print $1}')
ACTUAL_SHA=$(sha256sum "$TMP_FW" | awk '{print $1}')
log "Expected SHA256: $EXPECTED_SHA"
log "Actual SHA256:   $ACTUAL_SHA"

if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    log "SHA256 mismatch! Aborting upgrade."
    wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
fi

log "SHA256 verified successfully."

# Compare build dates
log "Downloading profiles.json..."
wget -O "$TMP_PROFILE" "$PROFILE_URL" || {
    log "Failed to download profiles.json!"
    wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# Extract current firmware build date from /etc/os-release
CURRENT_DATE=$(grep OPENWRT_BUILD_DATE /etc/os-release | cut -d= -f2 | tr -d '"')
# Extract new firmware build date from profiles.json
NEW_DATE=$(grep -o '"source_date_epoch":[0-9]*' "$TMP_PROFILE" | cut -d: -f2)

log "Current firmware build date (epoch): $CURRENT_DATE"
log "New firmware build date (epoch):     $NEW_DATE"

if [ "$NEW_DATE" -le "$CURRENT_DATE" ]; then
    log "New firmware is not newer than current. Aborting."
    wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
fi

log "Build date check passed."

# Upload log before upgrade
log "Uploading log before sysupgrade..."
wget --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -

# Trigger sysupgrade (this will kill the script)
log "Starting sysupgrade..."
exec sysupgrade "$TMP_FW"
