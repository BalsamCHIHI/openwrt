#!/bin/sh

server_port="12345"
flash_path="/mnt/monitor"
max_flash_occupancy=90
sfp_not_connected="0 25 0 0 0"

save_logs() {
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

client_ip="$SOCAT_PEERADDR"
while read -r line; do
    case "$(echo "$line" | cut -c1-3)" in
        SFP)
            if [ "${line##* }" = "0 25 0 0 0" ]; then
                eth_interface=$(echo "$line" | grep -oE "eth[0-9]+")
                sfp_line="$eth_interface $sfp_not_connected"
            else
                if [ "$sfp_line" != "$values_not_connected" ]; then
                    save_logs "$(date) $client_ip $sfp_line"
                fi
                sfp_line=$(echo "$line" | sed "s/^SFP//")
                save_logs "$(date) $client_ip $sfp_line"
                sfp_line="$sfp_not_connected"
            fi
            ;;
        HWM)
            hwm_line=$(echo "$line" | sed "s/^HWM//")
            save_logs "$(date) $client_ip $hwm_line"
            ;;
        *)
            continue
            ;;
    esac
done
