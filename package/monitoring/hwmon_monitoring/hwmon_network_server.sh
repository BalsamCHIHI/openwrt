#!/bin/sh -e
START=98
STOP=10

server_ip="172.100.1.2"
server_port="12345"
TIMEOUT=2
flash_path="/etc/monitor"
max_flash_occupancy=90
pid_path="/var/run/monitoring_hwmon.pid"

save_logs() {
    if [ ! -d "$flash_path" ]; then
        mkdir -p "$flash_path"
    fi
    line="$1"
    if [ -d "$flash_path" ] && [ -r "$flash_path" ]; then
        newest_file=$(ls -1v "$flash_path" 2>/dev/null | tail -n 1)
    else
        newest_file=""
    fi

    if ! echo "$newest_file" | grep -qE '^logfile_[0-9]{8}_[0-9]{6}\.log$'; then
        newest_file=$(ls -t "$flash_path" 2>/dev/null | grep -E '^logfile_[0-9]{8}_[0-9]{6}\.log$' | tail -n 1)
    fi

    if [ -z "$newest_file" ]; then
        newest_file="logfile_$(date +%Y%m%d_%H%M%S).log"
    fi

    if [ -n "$newest_file" ]; then
        echo "$line" >> "$flash_path/$newest_file"
        # Trim file to last 10k lines
        line_count=$(wc -l < "$flash_path/$newest_file")
        if [ "$line_count" -gt 10000 ]; then
            # Create a new file with the current date and time
            new_file_name="logfile_$(date +%Y%m%d_%H%M%S).log"
            echo "$line" > "$flash_path/$new_file_name"
        fi
    fi

    if grep -qs "$flash_path" /proc/mounts; then
        usage=$(df "$flash_path" | awk 'NR==2 {print $5}' | sed 's/%//')
    else
        echo "Error: $flash_path is not a valid mount point."
        return
    fi

    usage=$(df "$flash_path" | awk 'NR==2 {print $5}' | sed 's/%//')
    if ! echo "$usage" | grep -qE '^[0-9]+$'; then
        echo "Error: Unable to determine flash usage. Skipping cleanup."
        return
    fi

    if [ "$usage" -gt $max_flash_occupancy ]; then
        echo "$line" > "$flash_path/logfile_$(date +%Y%m%d_%H%M%S).log"
    fi

    # Check if the partition is more than 90% full
    usage=$(df "$flash_path" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$usage" -gt $max_flash_occupancy ]; then
        # Delete the oldest file in the directory
        oldest_file=$(ls -t "$flash_path" 2>/dev/null | tail -n 1)
        if [ -n "$oldest_file" ]; then
            rm -f "$flash_path/$oldest_file"
        fi
    fi
}

get_board_type() {
    if [ -r /proc/cmdline ]; then
        board_type=$(cat /proc/cmdline)
    else
        echo "Error: /proc/cmdline is not accessible."
        board_type="unknown"
    fi
    if echo "$board_type" | grep -q "SERVER"; then
        board_type="server"
    elif echo "$board_type" | grep -q "WAP"; then
        board_type="wap"
    else
        board_type="comexpress"
    fi
    echo "$board_type"
}

main() {
    board_type=$(get_board_type)
    while true; do
        data=""

        for hwmon in /sys/class/hwmon/hwmon*; do
            if [ -f "$hwmon/name" ]; then
                name=$(cat "$hwmon/name")
            else
                continue
            fi

            if ! ls "$hwmon"/*_input >/dev/null 2>&1; then
                continue
            fi

            if [ -f "$hwmon/label" ]; then
                label=$(cat "$hwmon/label")
            else
                label=""
            fi
            
            hwmon_name=$(basename "$hwmon" | sed 's/[^0-9]//g')
            if [ -n "$label" ]; then
                data="HWM$board_type $hwmon_name $label $name"
            else
                data="HWM$board_type $hwmon_name $name"
            fi

            for input in "$hwmon"/*_input; do
                if [ -r "$input" ]; then
                    input_name=$(basename "$input" | sed 's/[^0-9]//g')
                    value=$(cat "$input" 2>/dev/null)
                    if [ $? -eq 0 ]; then

                        case "$name" in
                            "ads7830")
                                case "$label" in
                                    "db-sensor-adc")
                                        if [ "$input_name" == *6* ]; then
                                            echo 1 > /sys/class/leds/adcen-bat/brightness
                                            value=$(cat "$input" 2>/dev/null)
                                            echo 0 > /sys/class/leds/adcen-bat/brightness
                                        fi

                                        if [ "$input_name" == *7* ]; then
                                            echo 1 > /sys/class/leds/adcen-edlc/brightness
                                            value=$(cat "$input" 2>/dev/null)
                                            echo 0 > /sys/class/leds/adcen-edlc/brightness
                                        fi
                                        ;;
                                    *)
                                        ;;
                                esac
                                ;;
                            *)
                                ;;
                        esac

                        data="$data $input_name $value"

                    else
                        echo "Cannot read $input: No such device or address"
                    fi
                else
                    echo "Cannot read $input"
                fi
            done

            if [ -z "$data" ]; then
                sleep 100
                continue
            fi

            if [ "$board_type" = "server" ]; then
                if echo "$data" | grep -q "HWM"; then
                    data=$(echo "$data" | sed 's|HWM||')
                fi
                save_logs "$(date) $data"
                data=""
            else
                # Check if the server is available
                if socat -T "$TIMEOUT" - TCP:"$server_ip":"$server_port",connect-timeout="$TIMEOUT" >/dev/null 2>&1; then
                    printf "%s\n" "$data" | socat - TCP:"$server_ip":"$server_port"
                fi
                if echo "$data" | grep -q "HWM"; then
                    data=$(echo "$data" | sed 's|HWM||')
                fi
                save_logs "$(date) $data"
                data=""
            fi
            sleep 100

        done
    done
}

start() {
    board_type=$(get_board_type)
    if [ "$board_type" = "comexpress" ]; then
        echo $$ > "$pid_path"
        main
    else
        if ! grep -qs "$flash_path" /proc/mounts || ! grep -qs "jffs2" /proc/mounts; then
        (
            timeout=60  # Maximum wait time in seconds
            count=0

            while [ $count -lt $timeout ]; do
                if grep -qs "$flash_path" /proc/mounts && grep -qs "jffs2" /proc/mounts; then
                    echo "Partition mounted."
                    main &
                    echo $! > "$pid_path"
                    exit 0
                fi
                sleep 1
                count=$((count + 1))
            done

            echo "Timeout waiting for partition to mount." >&2
            exit 1
        ) &
        else
            echo $$ > "$pid_path"
            main
        fi
    fi
}



stop() {
    echo "Stopping hwmon_monitor"
    if [ -f "$pid_path" ]; then
        kill "$(cat "$pid_path")" && rm -f "$pid_path"
    else
        echo "No PID file found. Process may not be running."
    fi
}

start
