#!/bin/sh /etc/rc.common

START=98
STOP=10

# Function to get flash usage percentage
get_flash_usage() {
    df "$flash_path" | awk 'NR==2 {print $5}' | sed 's/%//'
}

server_ip="192.168.10.1"
server_port="12345"
TIMEOUT=2
flash_path="/var/monitoring"
pid_path="/var/run/sfp_monitoring.pid"
max_flash_occupancy=90
values_not_connected="0 25 0 0 0"
values_missing="0 0 0 0 0"

get_board_type() {
    board_type=$(cat /proc/cmdline)
    if echo "$board_type" | grep -q "Server"; then
        board_type="server"
    elif echo "$board_type" | grep -q "Wap"; then
        board_type="wap"
    else
        board_type="comexpress"
    fi
    echo "$board_type"
}

save_logs() {
    line="$1"
    logfile_regex='^logfile_[0-9]{8}_[0-9]{6}\.log$'
    if [ -d "$flash_path" ] && [ -r "$flash_path" ]; then
        newest_file=$(ls -1v "$flash_path" 2>/dev/null | tail -n 1)
    else
        newest_file=""
    fi

    if ! echo "$newest_file" | grep -qE "$logfile_regex"; then
        newest_file=$(ls -t "$flash_path" 2>/dev/null | grep -E "$logfile_regex" | head -n 1)
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
        usage=$(get_flash_usage)
    else
        echo "Error: $flash_path is not a valid mount point."
        return
    fi

    if ! echo "$usage" | grep -qE '^[0-9]+$'; then
        echo "Error: Unable to determine flash usage. Skipping cleanup."
        return
    fi

    if [ "$usage" -gt $max_flash_occupancy ]; then
        echo "$line" > "$flash_path/logfile_$(date +%Y%m%d_%H%M%S).log"
        # Delete the oldest file in the directory
        oldest_file=$(ls -t "$flash_path" 2>/dev/null | tail -n 1)
        if [ -n "$oldest_file" ]; then
            rm -f "$flash_path/$oldest_file"
        fi
    fi
}

# Function to execute the ethtool command and get the output
get_ethtool_output() {
    interface=$1
    ethtool --phy-statistics "$interface"
}

# Function to parse the ethtool output and extract required data
parse_ethtool_output() {
    interface=$1
    output=$2
    board_type=$3
    line_not_connected=$4
    line_missing=$5
    temperature=$(echo "$output" | grep "Temperature" | awk '{print $NF}')
    vcc=$(echo "$output" | grep "VCC" | awk '{print $NF}')
    tx_bias=$(echo "$output" | grep "TX Bias" | awk '{print $NF}')
    tx_power=$(echo "$output" | grep "TX Power" | awk '{print $NF}')
    rx_power=$(echo "$output" | grep "RX Power" | awk '{print $NF}')

    # Count the number of digits in temperature
    num_digits=$(echo "$temperature" | wc -c)

    # Check if the number of digits exceeds 9
    if [ "$num_digits" -gt 6 ]; then
        temperature=0
    fi

    if [ "$board_type" = "server" ]; then
        data="$temperature $vcc $tx_bias $tx_power $rx_power"
        if [ "$data" = "$values_not_connected" ]; then
            line_not_connected="$interface $line_not_connected"
        elif [ "$data" = "$values_missing" ]; then
            line_missing="$interface $line_missing"
        else
            # Send to syslog
            logger -t "sfp_monitoring" -p local0.info "board_type=$board_type interface=$interface temperature=$temperature vcc=$vcc tx_bias=$tx_bias tx_power=$tx_power rx_power=$rx_power"
            
            # Also save locally as backup
            save_logs "$(date) $board_type $interface $data"
        fi
    else
        data="$temperature $vcc $tx_bias $tx_power $rx_power"
        if [ "$data" = "$values_not_connected" ]; then
            line_not_connected="$interface $line_not_connected"
        elif [ "$data" = "$values_missing" ]; then
            line_missing="$interface $line_missing"
        else
            # Send to syslog
            logger -t "sfp_monitoring" -p local0.info "board_type=$board_type interface=$interface temperature=$temperature vcc=$vcc tx_bias=$tx_bias tx_power=$tx_power rx_power=$rx_power"
            
            # Also save locally as backup
            save_logs "$(date) $interface $data"
        fi
    fi
}

# Main function to execute the script every 5 seconds
main() {
    #no sfp in comexpress
    board_type=$(get_board_type)
    if [ "$board_type" = "comexpress" ]; then
        exit 1
    fi
    
    # Dynamically detect available interfaces
    interfaces=""
    for iface in eth1 eth2 eth3 eth4 eth5 eth6; do
        if ip link show "$iface" >/dev/null 2>&1; then
            interfaces="$interfaces $iface"
        fi
    done
    interfaces=$(echo "$interfaces" | xargs)  # Trim whitespace
    
    if [ -z "$interfaces" ]; then
        echo "No interfaces found. Exiting."
        exit 1
    fi
    while true; do
        line_not_connected="$values_not_connected"
        line_missing="$values_missing"
        for interface in $interfaces; do
            output=$(get_ethtool_output "$interface")
            parse_ethtool_output "$interface" "$output" "$board_type" "$line_not_connected" "$line_missing"
            sleep 30
        done
        
        # Handle not connected interfaces
        if [ "$line_not_connected" != "$values_not_connected" ]; then
            save_logs "$(date) $board_type $line_not_connected"
            if [ "$board_type" != "server" ]; then
                # Send not connected status to syslog
                logger -t "sfp_monitoring" -p local0.warning "board_type=$board_type status=not_connected interfaces=$line_not_connected"
            fi
        fi
        
        # Handle missing interfaces
        if [ "$line_missing" != "$values_missing" ]; then
            save_logs "$(date) $board_type $line_missing"
            if [ "$board_type" != "server" ]; then
                # Send missing status to syslog
                logger -t "sfp_monitoring" -p local0.err "board_type=$board_type status=missing interfaces=$line_missing"
            fi
        fi
    done
}

start() {
    # Check if the PID file already exists
    if [ -f "$pid_path" ]; then
        echo "sfp monitoring is already running."
        exit 1
    fi
    
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
        main & echo $! > "$pid_path"
    fi
}

stop() {
    echo "Stopping sfp_monitoring"    
    if [ -f "$pid_path" ]; then
        kill "$(cat "$pid_path")" && rm -f "$pid_path"
    else
        echo "No running process found."
    fi
}
