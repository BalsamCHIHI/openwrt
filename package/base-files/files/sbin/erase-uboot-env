#!/bin/sh

# Conditionally erase U-Boot environment for tqmls1088a boards
board=$(cat /tmp/sysinfo/board_name 2>/dev/null)

case "$board" in
    tq,ls1088a-tqmls1088a-mbls10xxa | \
    tq,ls1088a-tqmls1088a-mbls10xxa-sdboot | \
    moment,ls1088a-tqmls1088a-connect | \
    moment,ls1088a-tqmls1088a-connect-sdboot)
        echo "Erasing U-Boot environment for board: $board"
        mtd erase env
        mtd erase env-backup
        ;;
    *)
        echo "Skipping U-Boot environment erase for board: $board"
        ;;
esac
