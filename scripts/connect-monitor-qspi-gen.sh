#!/bin/bash
# Produce a JFFS2 summarized image and a fast 64MiB padded (0xFF) binary for U-Boot sf update.
# Optimized: use bs=1M for padding (much faster than bs=1) and overlay summarized image at offset 0.

set -e
set -u
set -o pipefail
#set -x

# --- Config ---
BIN_DIR="${1:-./bin/targets/layerscape/armv8_64b/monitor_qspi}"
ERASE_SIZE=8192                 # mkfs.jffs2 minimum (even if NOR is 4KiB)
PAGE_SIZE=8192                  # sumtool page; matching ERASE_SIZE is fine for NOR
FULL_MB=64
FULL_BYTES=$((FULL_MB * 1024 * 1024))

RAW_IMG="$BIN_DIR/monitor.jffs2"
SUM_IMG="$BIN_DIR/monitor-summarized.jffs2"
PAD_IMG="$BIN_DIR/monitor-qspi.bin"

# --- Tools check ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'. Install with: sudo apt-get install -y mtd-utils"; exit 1; }; }
need mkfs.jffs2
need sumtool

# --- Workspace ---
mkdir -p "$BIN_DIR"
STAGE_DIR="$(mktemp -d -t monitor_qspi-XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

ROOT="$STAGE_DIR/root"
mkdir -p "$ROOT"

# Small provenance marker (ensures FS non-empty)
cat > "$ROOT/FS_STAMP.txt" <<EOF
monitor JFFS2 Factory Image
Built (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Host       : $(hostname || echo unknown)
Notes      : Summarized image for fast mount; 64MiB padded 0xFF binary for U-Boot sf update.
EOF
chmod 0644 "$ROOT/FS_STAMP.txt"

echo ">>> mkfs.jffs2 (erase=${ERASE_SIZE}, endian=little)"
mkfs.jffs2 -n -e "${ERASE_SIZE}" -l -r "$ROOT" -o "$RAW_IMG"

echo ">>> sumtool (erase=${ERASE_SIZE}, page=${PAGE_SIZE})"
sumtool -e "${ERASE_SIZE}" -p "${PAGE_SIZE}" -i "$RAW_IMG" -o "$SUM_IMG"

echo ">>> create ${FULL_MB}MiB 0xFF padded binary (fast path)"
# Create a full 64MiB of 0xFF quickly
dd if=/dev/zero bs=1M count="${FULL_MB}" status=progress | tr '\0' '\377' > "$PAD_IMG"

echo ">>> overlay summarized image at offset 0 (conv=notrunc)"
# Overwrite the start of the 0xFF file with the summarized JFFS2 content
dd if="$SUM_IMG" of="$PAD_IMG" bs=1M conv=notrunc status=progress

echo ">>> artifacts"
rm -f "$RAW_IMG"
ls -lh "$SUM_IMG" "$PAD_IMG"

cat <<EOF

Done.

Artifacts:
  - Summarized JFFS2 image : $SUM_IMG          <-- Use this for 'mtd erase' + 'mtd write' on device
  - 64MiB 0xFF padded BIN  : $PAD_IMG                       <-- Use this for U-Boot 'sf update' (whole-chip or region)

EOF
