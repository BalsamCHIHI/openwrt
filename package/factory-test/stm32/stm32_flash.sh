#!/bin/sh

LOG="/tmp/stm32flash.log"
echo "Starting STM32 flash script..." > "$LOG"

echo "Entering bootloader mode..." | tee -a "$LOG"
echo 1 > /sys/class/leds/mcu-boot0/brightness
echo 0 > /sys/class/leds/mcu-nrst/brightness
sleep 1
echo 1 > /sys/class/leds/mcu-nrst/brightness
sleep 3

echo "Trying to detect STM32..." | tee -a "$LOG"

# Retry loop
for i in 1 2 3 4 5; do
    echo "Attempt $i..." | tee -a "$LOG"
    output=$(/usr/bin/stm32flash /dev/ttyS3 2>&1)
    echo "$output" | tee -a "$LOG"

    if echo "$output" | grep -q "Device ID" && echo "$output" | grep -q "STM32F7"; then
        echo "✅ Device detected: STM32F7" | tee -a "$LOG"
        if [ ! -f /lib/firmware/avionics/moment_board_f722.bin ]; then
            echo "❌ Firmware file /lib/firmware/avionics/moment_board_f722.bin not found!" | tee -a "$LOG"
            break
        fi
        /usr/bin/stm32flash -w /lib/firmware/avionics/moment_board_f722.bin -v -g 0x0 /dev/ttyS3
        break
    else
        echo "❌ Not detected, retrying..." | tee -a "$LOG"
        sleep 2
    fi
done

# Exit bootloader mode
echo "Exiting bootloader mode..." | tee -a "$LOG"
echo 0 > /sys/class/leds/mcu-boot0/brightness 
echo 0 > /sys/class/leds/mcu-nrst/brightness 
sleep 1
echo 1 > /sys/class/leds/mcu-nrst/brightness 

echo "Done." | tee -a "$LOG"
if echo "$output" | grep -q "Device ID" && echo "$output" | grep -q "STM32F7"; then
    cp "$LOG" /lib/firmware/avionics/stm32flash.log
fi
