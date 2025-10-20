#!/bin/sh

# Conditionally run Factory Reset for tqmls1088a boards
board=$(cat /tmp/sysinfo/board_name 2>/dev/null)

case "$board" in
    tq,ls1088a-tqmls1088a-mbls10xxa | \
    tq,ls1088a-tqmls1088a-mbls10xxa-sdboot | \
    moment,ls1088a-tqmls1088a-connect | \
    moment,ls1088a-tqmls1088a-connect-sdboot)
        echo "Running Factory Reset for board: $board"
        connect-erase_uboot_env.sh
        firstboot -y -r
        ;;
    *)
        echo "Skipping Factory Reset for board: $board"
        ;;
esac
