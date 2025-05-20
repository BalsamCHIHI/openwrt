#!/bin/sh /etc/rc.common
START=90
STOP=10

server_port="12345"
flash_path="/mnt/monitor"
max_flash_occupancy=90
sfp_not_connected="0 25 0 0 0"


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

main() {
    while true; do
        socat TCP4-LISTEN:$server_port,fork,reuseaddr SYSTEM:'/usr/bin/monitoring_parser.sh'
    done &
}

# Function to start the TCP server
start() {
    board_type=$(get_board_type)
    if [ "$board_type" != "server" ]; then
        exit 1
    fi

    # Check if the PID file already exists
    if [ -f /var/run/monitor_server.pid ]; then
        echo "Server is already running."
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
                    echo $! > /var/run/monitor_server.pid
                    exit 0
                fi
                sleep 1
                count=$((count + 1))
            done

            echo "Timeout waiting for partition to mount." >&2
            exit 1
        ) &
    else
        main & echo $! > /var/run/monitor_server.pid
    fi
}

# Function to stop the TCP server
stop() {
    if [ -f /var/run/monitor_server.pid ]; then
        kill $(cat /var/run/monitor_server.pid) && rm -f /var/run/monitor_server.pid
    else
        echo "No running process found."
    fi
}