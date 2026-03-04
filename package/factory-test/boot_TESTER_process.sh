#!/bin/sh /etc/rc.common

START=99

RECEIVER_IP="192.168.200.2"     # IP of the receiver device
TRIGGER_PORT="13000"            # Port to receive trigger
RESPONSE_PORT="13001"           # Port to send data back

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

hwmon_test() {
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


start() {
    set_conf=$(uci get factory-test.setConf.enabled)
    start_network_test=$(uci get factory-test.startTest.enabled)

    if [ "$set_conf" = "99" ] && [ "$start_network_test" = "99" ]; then
        return 0
    fi

    if [ "$set_conf" = "0" ] && [ "$start_network_test" = "0" ]; then
        cp /etc/config/network.bak /etc/config/network
        cp /etc/config/firewall.bak /etc/config/firewall
        rm /etc/config/network.bak
        rm /etc/config/firewall.bak
        rm /etc/config/dhcp.bak
        /etc/init.d/network restart
        /etc/init.d/firewall restart

        uci set factory-test.setConf.enabled="99"
        uci set factory-test.startTest.enabled="99"
        uci commit
        return 0
    fi

    if [ "$set_conf" = "1" ]; then
        cp /etc/config/network  /etc/config/network.bak
        cp /etc/config/firewall /etc/config/firewall.bak
        cp /etc/config/dhcp     /etc/config/dhcp.bak


        for section in $(uci show network | grep "=device" | cut -d. -f2 | cut -d= -f1); do
            name=$(uci get network.$section.name 2>/dev/null)
            if [ "$name" = "br-lan" ]; then
                uci delete network.$section.ports
            fi
        done
        uci set system.@system[0].hostname='Connect-Tester'
        # Loopback interface
        uci set network.loopback='interface'
        uci set network.loopback.device='lo'
        uci set network.loopback.proto='static'
        uci set network.loopback.ipaddr='127.0.0.1'
        uci set network.loopback.netmask='255.0.0.0'

        # Global settings
        uci set network.globals='globals'
        uci set network.globals.ula_prefix='fd00:1e90:70e6::/48'
        uci set network.globals.packet_steering='0'

        # Bridge device
        uci set network.@device[0]='device'
        uci set network.@device[0].name='br-lan'
        uci set network.@device[0].type='bridge'

        # LAN interface WIFI
        uci set network.lan='interface'
        uci set network.lan.device='br-lan'
        uci set network.lan.proto='static'
        uci set network.lan.ipaddr='192.168.201.1'
        uci set network.lan.netmask='255.255.255.0'
        uci set network.lan.ip6assign='60'

        # Bonding device
        uci add network device
        uci set network.@device[-1].type='bonding'
        uci set network.@device[-1].name='bound'
        uci add_list network.@device[-1].ports='eth1'
        uci add_list network.@device[-1].ports='eth2'
        uci add_list network.@device[-1].ports='eth3'
        uci add_list network.@device[-1].ports='eth4'
        uci add_list network.@device[-1].ports='eth5'
        uci add_list network.@device[-1].ports='eth6'
        uci add_list network.@device[-1].ports='eth7'
        uci add_list network.@device[-1].ports='eth8'
        uci set network.@device[-1].policy='balance-rr'
        uci set network.@device[-1].all_ports_active='1'

        # ethnet interface
        uci set network.ethnet='interface'
        uci set network.ethnet.proto='static'
        uci set network.ethnet.device='bound'
        uci set network.ethnet.ipaddr='192.168.200.1'
        uci set network.ethnet.netmask='255.255.255.0'
        uci set network.ethnet.ip6assign='64'

        # Add static Wi-Fi interface 'wifi_static'
        uci set network.wifi_static=interface
        uci set network.wifi_static.proto='static'
        uci set network.wifi_static.ipaddr='192.168.201.1'
        uci set network.wifi_static.netmask='255.255.255.0'

        # Delete existing AP interfaces
        uci delete wireless.default_radio0
        uci delete wireless.default_radio1
        
        # Add STA interface on radio0 (2.4GHz)
        uci set wireless.sta_radio0=wifi-iface
        uci set wireless.sta_radio0.device='radio0'
        uci set wireless.sta_radio0.network='wifi_static'
        uci set wireless.sta_radio0.mode='sta'
        uci set wireless.sta_radio0.encryption='none'

        uci set factory-test.setConf.enabled="0"

        # Save and apply
        uci commit
        /etc/init.d/firewall stop
        /etc/init.d/network restart
        wifi reload
    fi

    if [ "$start_network_test" = "1" ]; then
        echo "Starting network test..."
        /etc/init.d/firewall stop
        iperf -s &
    fi
}