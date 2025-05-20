#!/bin/sh /etc/rc.common
START=99
STOP=10

server_ip="192.168.10.1"
#"172.100.1.1"
server_port="12345"
TIMEOUT=2
flash_path="/mnt/monitor"
pid_path="/var/run/sfp_monitor.pid"
max_flash_occupancy=90
values_not_connected="0 25 0 0 0"
values_missing="0 0 0 0 0"

get_board_type() {
    board_type=$(cat /proc/cmdline)
    if echo "$board_type" | grep -q "SERVER"; then
        board_type="server"
    elif echo "$board_type" | grep -q "WAP"; then
        board_type="wap"
    else
        board_type="comexpress"
    fi
    echo "$board_type"
}

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
    
    # Convert temperature from unsigned to signed 16-bit value
    if [ "$temperature" -gt 32767 ]; then
        temperature=$((temperature - 65536))
    fi

    vcc_converted=$((vcc / 10))
    tx_bias_converted=$((tx_bias * 2))
    tx_power_converted=$((tx_power / 10))
    rx_power_converted=$((rx_power / 10))

    if [ "$board_type" = "server" ]; then
        data="$temperature $vcc_converted $tx_bias_converted $tx_power_converted $rx_power_converted"
        if [ "$data" = "$values_not_connected" ]; then
            line_not_connected="$interface $line_not_connected"
        elif [ "$data" = "$values_missing" ]; then
            line_missing="$interface $line_missing"
        else
            # Server is not available, call save_nor_flash function
            save_logs "$(date) $board_type $interface $data"
        fi
    else
        data="$temperature $vcc_converted $tx_bias_converted $tx_power_converted $rx_power_converted"
        if [ "$data" = "$values_not_connected" ]; then
            line_not_connected="$interface $line_not_connected"
        elif [ "$data" = "$values_missing" ]; then
            line_missing="$interface $line_missing"
        else
            # Check if the server is available
            if socat -T $TIMEOUT - TCP:$server_ip:$server_port,connect-timeout=$TIMEOUT >/dev/null 2>&1; then
                # Server is available, send the message
                data="SFP$board_type $interface $temperature $vcc_converted $tx_bias_converted $tx_power_converted $rx_power_converted"
                echo -e "$data" | socat - TCP:$server_ip:$server_port
            fi
            # Server is not available, call save_nor_flash function
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
    interfaces="eth1 eth2 eth3 eth4 eth5 eth6"
    while true; do
        line_not_connected="$values_not_connected"
        line_missing="$values_missing"
        for interface in $interfaces; do
            output=$(get_ethtool_output "$interface")
            parse_ethtool_output "$interface" "$output" "$board_type" "$line_not_connected" "$line_missing"
            sleep 5
        done
        if [ "$line_not_connected" != "$values_not_connected" ]; then
            save_logs "$(date) $board_type $line_not_connected"
            if [ "$board_type" != "server" ]; then
                if socat -T $TIMEOUT - TCP:$server_ip:$server_port,connect-timeout=$TIMEOUT >/dev/null 2>&1; then
                    # Server is available, send the message
                    data="SFP$board_type $line_not_connected"
                    echo -e "$data" | socat - TCP:$server_ip:$server_port
                fi
            fi
        fi
        if [ "$line_missing" != "$values_missing" ]; then
            save_logs "$(date) $board_type $line_missing"
            if [ "$board_type" != "server" ]; then
                if socat -T $TIMEOUT - TCP:$server_ip:$server_port,connect-timeout=$TIMEOUT >/dev/null 2>&1; then
                    # Server is available, send the message
                    data="SFP$board_type $line_missing"
                    echo -e "$data" | socat - TCP:$server_ip:$server_port
                fi
            fi
        fi
    done
}

start() {
    # Check if the PID file already exists
    if [ -f "$pid_path" ]; then
        echo "sfp monitor is already running."
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
    echo "Stopping sfp_monitor"    
    if [ -f "$pid_path" ]; then
        kill $(cat "$pid_path") && rm -f "$pid_path"
    else
        echo "No running process found."
    fi
}