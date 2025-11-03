#!/bin/sh

MODE="$1"
case "$MODE" in
    --test|--upgrade) ;;
    *)
        echo "Usage: $0 [--test | --upgrade]"
        echo "  --test    : Dry run mode, verify image and config only"
        echo "  --upgrade : Perform full sysupgrade"
        exit 1
        ;;
esac

SERVER=$(cat /proc/cmdline | awk -F'ce_server=' '{print $2}' | awk '{print $1}')

# Fallback if ce_server is not set
[ -z "$SERVER" ] && SERVER="172.100.1.1"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(cat /proc/sys/kernel/hostname)
FIRMWARE_URL="http://$SERVER/downloads/openwrt-layerscape-armv8_64b-moment_ls1088a-tqmls1088a-connect-squashfs-sysupgrade.bin"
FIRMWARE_URL_FILENAME=$(basename "$FIRMWARE_URL")
CHECKSUM_URL="http://$SERVER/downloads/sha256sums"
PROFILE_URL="http://$SERVER/downloads/profiles.json"
TMP_FW="/tmp/sysupgrade.bin"
TMP_FW_FILENAME=$(basename "$TMP_FW")
TMP_SUM="/tmp/sha256sums"
TMP_PROFILE="/tmp/profiles.json"
TMP_LOG="/tmp/connect_sysupgrade.log"
TMP_LOG_FILENAME=$(basename "$TMP_LOG")
TMP_METADATA="/tmp/metadata.json"
TMP_METADATA_FILENAME=$(basename "$TMP_METADATA")
LOG_UPLOAD_URL="http://$SERVER/cgi-bin/upload-raw.sh?filename=${HOSTNAME}-${TMP_LOG_FILENAME}-${TIMESTAMP}"
METADATA_UPLOAD_URL="http://$SERVER/cgi-bin/upload-raw.sh?filename=${HOSTNAME}-${TMP_METADATA_FILENAME}-${TIMESTAMP}"

# Prevents hangs on flaky links
WGET="wget -T 10 -q"

log() {
    echo "$1" | tee -a "$TMP_LOG"
    logger -t connect-sysupgrade "$1"
}

log "Triggered firmware upgrade script in mode: $MODE"

# Download firmware
log "Downloading firmware..."
$WGET -O "$TMP_FW" "$FIRMWARE_URL" || {
    log "Firmware download failed!"
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# Download checksum
log "Downloading checksum..."
$WGET -O "$TMP_SUM" "$CHECKSUM_URL" || {
    log "Checksum download failed!"
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# Verify checksum
# Strip a leading '*' if present
EXPECTED_SHA="$(awk -v f="$FIRMWARE_URL_FILENAME" '{n=$2; sub(/^\*/, "", n); if (n==f) print $1}' "$TMP_SUM")"
ACTUAL_SHA="$(sha256sum "$TMP_FW" | awk '{print $1}')"
log "Expected SHA256: $EXPECTED_SHA"
log "Actual   SHA256: $ACTUAL_SHA"

if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    log "SHA256 mismatch or missing entry! Aborting upgrade."
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
fi

log "SHA256 verified successfully."

# Compare build dates : OPENWRT_BUILD_DATE in /etc/os-release equals SOURCE_DATE_EPOCH in profiles.json
CURRENT_DATE=$( . /etc/os-release 2>/dev/null; echo "${OPENWRT_BUILD_DATE:-${BUILD_DATE:-0}}" )
[ -n "$CURRENT_DATE" ] || CURRENT_DATE=0

log "Downloading profiles.json..."
$WGET -O "$TMP_PROFILE" "$PROFILE_URL" || {
    log "Failed to download profiles.json!"
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    exit 1
}

# epoch from top-level source_date_epoch : in profiles.json
NEW_DATE="$(jsonfilter -i "$TMP_PROFILE" -e '@.source_date_epoch')"

log "Running firmware BUILD_DATE : $CURRENT_DATE : $(date -d @"$CURRENT_DATE")"
log "New firmware     BUILD_DATE : $NEW_DATE : $(date -d @"$NEW_DATE")"

# Numeric compare
if [ "$NEW_DATE" -le "$CURRENT_DATE" ]; then
    log "New firmware is not newer than running."
    if [ "$MODE" = "--upgrade" ]; then
        log "Aborting upgrade."
        log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
        $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
        exit 1
    else
        log "Continuing in test mode despite no new firmware."
    fi
fi

log "Build date check passed."

# Trigger sysupgrade : this will replace the shell and later drop networking
if [ "$MODE" = "--test" ]; then
    log "Dry run mode: verifying image only, no flashing will occur."
    sysupgrade -v --test "$TMP_FW"
    log "Extracting '$TMP_METADATA_FILENAME' from '$TMP_FW_FILENAME'..."
    fwtool -i "$TMP_METADATA" -t "$TMP_FW"
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    log "Uploading '$TMP_METADATA_FILENAME' to '$SERVER'..."
    $WGET --post-file="$TMP_METADATA" "$METADATA_UPLOAD_URL" -O -
    exit 0
else
    log "Uploading '$TMP_LOG_FILENAME' to '$SERVER' before sysupgrade..."
    $WGET --post-file="$TMP_LOG" "$LOG_UPLOAD_URL" -O -
    log "Starting sysupgrade..."
    exec sysupgrade -v "$TMP_FW"
fi
