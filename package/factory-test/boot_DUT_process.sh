#!/bin/sh /etc/rc.common

START=99
REPORT_INDEX=0
DEBIAN_USER="im-maintenance"
DEBIAN_IP="172.100.1.1"
SCRIPT_PATH="/usr/bin/check_gsm_modem.sh"
OUTPUT_FILE="/tmp/modem_status.txt"
DEBIAN_PASSWORD="rootroot"

RECEIVER_IP="192.168.200.1"     # IP of the receiver device
trigger_sfp_PORT="13000"        # Port to receive trigger_sfp
RESPONSE_PORT_sfp="13001"       # Port to send data back

trigger_hwm_PORT="14000"        # Port to receive trigger_hwm
RESPONSE_PORT_hwm="14001"       # Port to send data back

if [ ! -d /etc/monitoring ]; then
    mkdir -p /etc/monitoring
fi
while [ -e "/etc/monitoring/stats_report${REPORT_INDEX}.txt" ]; do
    REPORT_INDEX=$((REPORT_INDEX + 1))
done
REPORT_FILE="/etc/monitoring/stats_report${REPORT_INDEX}.txt"

get_ethtool_output() {
    interface=$1
    ethtool --phy-statistics "$interface"
}

convert_to_aa_xxx() {
    value=$1
    integer_part=$((value / 1000))
    fractional_part=$((value % 1000))
    printf "%02d.%03d" "$integer_part" "$fractional_part"
}

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

get_device_mac() {
    ip link show eth0 | awk '/ether/ {print $2}' 2>/dev/null || \
    uci get network.@device[0].macaddr 2>/dev/null || \
    cat /proc/device-tree/ethernet*/local-mac-address 2>/dev/null | hexdump -v -e '/1 "%02x"' | sed 's/../&:/g' | sed 's/:$//' | head -1 || \
    dmesg | grep -o -E '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}' | head -1
}



hwmon_test() {
    # Use ip link with timeout, fallback to other methods
    mac=$(ip link show eth0 | awk '/ether/ {print $2}' 2>/dev/null || \
          uci get network.@device[0].macaddr 2>/dev/null || \
          cat /proc/device-tree/ethernet*/local-mac-address 2>/dev/null | hexdump -v -e '/1 "%02x"' | sed 's/../&:/g' | sed 's/:$//' | head -1 || \
          dmesg | grep -o -E '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}' | head -1)
    echo "Machine MAC Address: $mac"
    for hwmon in /sys/class/hwmon/hwmon*; do
        current_date=$(date)

        if [ -f "$hwmon/name" ]; then
            name=$(cat "$hwmon/name")
        else
            continue
        fi

        if ! ls "$hwmon"/*_input >/dev/null 2>&1; then
            continue
        fi

        for input in "$hwmon"/*_input; do
            if [ -r "$input" ]; then
                input_name=$(basename "$input" | sed 's/_input$//')

                value=$(cat "$input" 2>/dev/null)
                if [ $? -eq 0 ]; then

                    value=$(convert_to_aa_xxx "$value")

                    echo "name: $name, input: $input_name, value: $value"
                fi
            else
                echo "Cannot read $input"
            fi
        done
    done
}

parse_ethtool_output() {
    interface=$1
    output=$2
    temperature=$(echo "$output" | grep "Temperature" | awk '{print $NF}')
    vcc=$(echo "$output" | grep "VCC" | awk '{print $NF}')
    tx_bias=$(echo "$output" | grep "TX Bias" | awk '{print $NF}')
    tx_power=$(echo "$output" | grep "TX Power" | awk '{print $NF}')
    rx_power=$(echo "$output" | grep "RX Power" | awk '{print $NF}')

    num_digits=$(echo "$temperature" | wc -c)
    if [ "$num_digits" -gt 9 ]; then
        temperature=0
    fi

    temperature_converted=$((temperature / 256))
    temperature_fraction=$((temperature * 100 / 256 % 100))
    vcc_converted=$(convert_to_aa_xxx $((vcc / 10)))
    tx_bias_converted=$(convert_to_aa_xxx $((tx_bias * 2)))
    tx_power_converted=$(convert_to_aa_xxx $((tx_power / 10)))
    rx_power_converted=$(convert_to_aa_xxx $((rx_power / 10)))

    printf "Port: %s, Temperature: %d.%02d, VCC: %s, TX Bias: %s, TX Power: %s, RX Power: %s\n" "$interface" "$temperature_converted" "$temperature_fraction" "$vcc_converted" "$tx_bias_converted" "$tx_power_converted" "$rx_power_converted"
}

sfp_test() {
    interfaces="eth1 eth2 eth3 eth4 eth5 eth6"
    for interface in $interfaces; do
        output=$(get_ethtool_output "$interface")
        parse_ethtool_output "$interface" "$output"
        sleep 1
    done
}

show_mb_id(){
    # Run i2cdump and capture output
    dump=$(i2cdump -y -f 0 0x5C b)

    # Extract the line starting with 80:
    line=$(echo "$dump" | grep "^80:")

    # Extract the hex values (fields 2 to 17)
    id_hex=$(echo "$line" | awk '{for(i=2;i<=17;i++) printf "%s", $i}')

    # Optionally format with colons or dashes
    formatted_id=$(echo "$id_hex" | sed 's/../&:/g' | sed 's/:$//')
    # Check if formatted_id matches the expected format
    if ! echo "$formatted_id" | grep -qE '^([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}$'; then
        formatted_id="error"
    fi
    # Display the result
    echo "Unique ID MB:  $formatted_id"
}

show_db_id(){
    # Run i2cdump and capture output
    dump=$(i2cdump -y -f 0 0x5D b)

    # Extract the line starting with 80:
    line=$(echo "$dump" | grep "^80:")

    # Extract the hex values (fields 2 to 17)
    id_hex=$(echo "$line" | awk '{for(i=2;i<=17;i++) printf "%s", $i}')

    # Optionally format with colons or dashes
    formatted_id=$(echo "$id_hex" | sed 's/../&:/g' | sed 's/:$//')
    if ! echo "$formatted_id" | grep -qE '^([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}$'; then
        formatted_id="error"
    fi
    # Display the result
    echo "Unique ID DB:  $formatted_id"
}

show_ant_id(){
    # Run i2cdump and capture output
    dump=$(i2cdump -y -f 0 0x5A b)

    # Extract the line starting with 80:
    line=$(echo "$dump" | grep "^80:")

    # Extract the hex values (fields 2 to 17)
    id_hex=$(echo "$line" | awk '{for(i=2;i<=17;i++) printf "%s", $i}')

    # Optionally format with colons or dashes
    formatted_id=$(echo "$id_hex" | sed 's/../&:/g' | sed 's/:$//')
    if ! echo "$formatted_id" | grep -qE '^([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}$'; then
        formatted_id="error"
    fi
    # Display the result
    echo "Unique ID ANT: $formatted_id"
}

configure_wifi_ssid() {
    mac=$(ip link show eth0 | awk '/ether/ {print $2}' | tr -d ':')
    if [ -n "$mac" ]; then
        uci set wireless.default_radio0.ssid="${mac}-2.4GHz"
        uci set wireless.default_radio1.ssid="${mac}-5GHz"
        uci commit wireless
        wifi reload
        sleep 30
    fi
}

start() {
    # Check if factory test mode is activated using fw_printenv
    factory_mode=$(fw_printenv -n factory_mode 2>/dev/null)

    # If factory_mode doesn't exist, create it and set to yes
    if [ -z "$factory_mode" ]; then
        fw_setenv factory_mode first_boot
        factory_mode="first_boot"
    fi

    # If factory_mode is not "yes", do nothing (normal operation mode)
    if [ "$factory_mode" = "no" ]; then
        return 0
    fi

    /etc/init.d/firewall stop

    # Check if factory_mode is "first_boot" and backup configs
    if [ "$factory_mode" = "first_boot" ]; then
        echo "First boot mode detected - backing up OpenWrt configs..."
        if [ ! -d /etc/factory/backup ]; then
            mkdir -p /etc/factory/backup
        fi
        sysupgrade -b /etc/factory/backup/openwrt-backup.tar.gz
        echo "Backup complete: /etc/factory/backup/openwrt-backup.tar.gz"
        fw_setenv factory_mode yes

        # Update LAN IP address
        uci set network.lan.ipaddr='192.168.201.2'

        # Add bonding device 'bound'
        uci add network device
        uci set network.@device[-1].type='bonding'
        uci set network.@device[-1].name='bound'
        uci set network.@device[-1].ports='eth1 eth2 eth3 eth4 eth5 eth6 eth7 eth8'
        uci set network.@device[-1].policy='balance-rr'
        uci set network.@device[-1].all_ports_active='1'

        # Add new interface 'ethnet' using bonded device
        uci set network.ethnet=interface
        uci set network.ethnet.proto='static'
        uci set network.ethnet.device='bound'
        uci set network.ethnet.ipaddr='192.168.200.2'
        uci set network.ethnet.netmask='255.255.255.0'
        uci set network.ethnet.ip6assign='64'

        uci delete network.wan2
        uci delete network.wan4
        uci delete network.wan6
        uci delete network.wan8
        uci set network.@device[0].ports='eth1 eth2 eth3 eth4 eth5 eth6 eth7 eth8'


        uci set wireless.radio0.channel='1'            # choose 1, 6, or 11 after a quick scan
        uci set wireless.radio0.htmode='HT20'
        uci set wireless.radio0.noscan='1'  
        uci set wireless.radio1.channel=64
        # Save and apply
        uci delete system.@system[0].ttylogin
        uci commit
        /etc/init.d/firewall stop

        # Configure WiFi SSIDs with MAC address
        configure_wifi_ssid
        wifi reload

        /etc/init.d/network restart
        reload_config

        echo "Configuration set successfully."
        /usr/bin/stm32_flash.sh
        reboot
    fi

    # Check if factory_mode is "last_boot" and restore configs
    if [ "$factory_mode" = "last_boot" ]; then
        echo "Last boot mode detected - restoring OpenWrt configs..."
        if [ -d /etc/factory/backup ]; then
            sysupgrade -r /etc/factory/backup/openwrt-backup.tar.gz
            echo "Restore complete: /etc/factory/backup/openwrt-backup.tar.gz"
        else
            echo "Error: No backup found at /etc/factory/backup/"
        fi
        fw_setenv factory_mode no
        reboot
    fi



    # Factory test mode is active
    echo "Factory test mode detected - starting services..."

    ip link set br-lan up
    ip link set bound up
    wifi up

    # Start network test services
    echo "Starting network test..."
    /etc/init.d/firewall stop
    iperf -s &

    # Start background listeners for both ports
    (
        while true; do
            # Listen for SFP trigger
            socat TCP4-LISTEN:$trigger_sfp_PORT,reuseaddr - | while IFS= read -r line; do
                if [ "$line" = "SEND_SFP" ]; then
                    {
                    for i in $(seq 1 6); do
                        echo "Interface: eth$i"
                        ethtool --phy-statistics "eth$i" 2>/dev/null | grep -E 'TX Power:|RX Power:|VCC:|Temperature:'
                        echo ""
                    done
                    } | socat - TCP:$RECEIVER_IP:$RESPONSE_PORT_sfp
                    break
                fi
            done
        done
    ) &

    (
        while true; do
            # Listen for hardware monitoring trigger
            socat TCP4-LISTEN:$trigger_hwm_PORT,reuseaddr - | while IFS= read -r line; do
                if [ "$line" = "SEND_HWD" ]; then
                    # Log the trigger receipt

                    if [ "$(get_board_type)" = "server" ]; then
                        # Trigger GSM test on Debian and wait for response
                        echo "TRIGGER_GSM" | socat - TCP:$DEBIAN_IP:13000 &
                        sleep 10  # Give time for Debian to process and send back
                    fi
                    
                    # Accumulate all logs in temporary file
                    temp_log="/tmp/hwmon_response.tmp"
                    > "$temp_log"  # Clear the file
                    mac=$(ip link show eth0 | awk '/ether/ {print $2}' 2>/dev/null || \
                        uci get network.@device[0].macaddr 2>/dev/null || \
                        cat /proc/device-tree/ethernet*/local-mac-address 2>/dev/null | hexdump -v -e '/1 "%02x"' | sed 's/../&:/g' | sed 's/:$//' | head -1 || \
                        dmesg | grep -o -E '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}' | head -1)
                    echo "Machine MAC Address: $mac" >> "$temp_log"
                    show_db_id >> "$temp_log"
                    show_ant_id >> "$temp_log"
                    show_mb_id >> "$temp_log"
                    # Include GSM data if available
                    [ -f /tmp/test_status.tmp ] && cat /tmp/test_status.tmp >> "$temp_log"

                    # Log file size and send
                    cat "$temp_log" | socat - TCP:$RECEIVER_IP:$RESPONSE_PORT_hwm

                    # Clean up temp files
                    rm -f "$temp_log"
                    rm -f /tmp/test_status.tmp
                    break

                elif echo "$line" | grep -q "=== GSM Test Output ==="; then
                    # This is GSM status data from Debian, save to temp file
                    echo "$line" > /tmp/test_status.tmp
                    # Read the rest of the GSM output
                    while IFS= read -r gsm_line; do
                        echo "$gsm_line" >> /tmp/test_status.tmp
                        # Break if we see end marker or timeout
                        [ "$gsm_line" = "=== Test End ===" ] && break
                    done
                    break
                fi
            done
        done
    ) &
}
