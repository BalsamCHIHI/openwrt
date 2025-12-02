#!/bin/sh

# Script to print all hwmon and SFP sensor data

echo "========================================"
echo "HWMON SENSOR DATA"
echo "========================================"

# Function to convert hwmon values based on hwmon device and input number
convert_hwmon_value() {
    hwmon_num=$1
    input_num=$2
    value=$3
    
    case "$hwmon_num" in
        0)
            case "$input_num" in
                0|1|2)
                    # real value = 2 * readed value
                    echo $((value * 2))
                    ;;
                3)
                    # real value = 0.1 * readed value
                    # Using awk for decimal multiplication
                    echo "$value" | awk '{printf "%.1f", $1 * 0.1}'
                    ;;
                4|5)
                    # real value = 11 * readed value
                    echo $((value * 11))
                    ;;
                6)
                    # real value = 2.8 * readed value
                    echo "$value" | awk '{printf "%.1f", $1 * 2.8}'
                    ;;
                7)
                    # real value = 2 * readed value
                    echo $((value * 2))
                    ;;
                *)
                    echo "$value"
                    ;;
            esac
            ;;
        *)
            # For other hwmon devices, no conversion
            echo "$value"
            ;;
    esac
}

# Function to check if input should be printed for hwmon1
should_print_hwmon1_input() {
    input_num=$1
    case "$input_num" in
        0|1|6|7)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get label for hwmon sensor inputs
get_sensor_label() {
    hwmon_num=$1
    input_num=$2
    
    case "$hwmon_num" in
        0)
            case "$input_num" in
                0) echo "Current sense 12V5 (12V->5V converter input current)" ;;
                1) echo "Current sense 12V3 (12V->3.3V converter input current)" ;;
                2) echo "Current sense 12V4 (12V COMexpress converter input current)" ;;
                3) echo "Current sense 12V6 (12V daughter board supply current)" ;;
                4) echo "Voltage sense 12V4 (115V->12V converter output)" ;;
                5) echo "Voltage sense 12VR (12V COMexpress regulator output)" ;;
                6) echo "Voltage sense 5V (5V converter output)" ;;
                7) echo "Voltage sense 3.3V (3.3V converter output)" ;;
                *) echo "" ;;
            esac
            ;;
        1)
            case "$input_num" in
                0) echo "Voltage sense 1V0 (5V->1V converter output)" ;;
                1) echo "Voltage sense 2V5 (5V->2.5V converter output)" ;;
                6) echo "Voltage sense supercapacitor" ;;
                7) echo "Voltage sense lithium battery" ;;
                *) echo "" ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

# Process all hwmon devices
for hwmon in /sys/class/hwmon/hwmon*; do
    if [ ! -d "$hwmon" ]; then
        continue
    fi
    
    # Get hwmon name
    if [ -f "$hwmon/name" ]; then
        name=$(cat "$hwmon/name")
    else
        name="unknown"
    fi
    
    # Get hwmon number (e.g., hwmon0 -> 0)
    hwmon_basename=$(basename "$hwmon")
    hwmon_num=$(echo "$hwmon_basename" | sed 's/hwmon//')
    
    # Get label if it exists
    if [ -f "$hwmon/label" ]; then
        label=$(cat "$hwmon/label")
    else
        label="N/A"
    fi
    
    # Check if there are any input files
    if ! ls "$hwmon"/*_input >/dev/null 2>&1; then
        continue
    fi
    
    echo ""
    echo "Device: $hwmon_basename"
    echo "Name: $name"
    echo "Label: $label"
    echo "----------------------------------------"
    
    # Process all input files
    for input_file in "$hwmon"/*_input; do
        if [ ! -r "$input_file" ]; then
            continue
        fi
        
        # Get input filename and extract number
        input_basename=$(basename "$input_file")
        input_num=$(echo "$input_basename" | sed 's/[^0-9]//g')
        
        # Skip if input_num is empty
        if [ -z "$input_num" ]; then
            continue
        fi
        
        # For hwmon1, only print specific inputs
        if [ "$hwmon_num" = "1" ]; then
            if ! should_print_hwmon1_input "$input_num"; then
                continue
            fi
        fi
        
        # Read the value
        value=$(cat "$input_file" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "  $input_basename: Error reading value"
            continue
        fi
        
        # Handle special cases for ads7830
        if [ "$name" = "ads7830" ] && [ "$label" = "db-sensor-adc" ]; then
            case "$input_num" in
                6)
                    echo 1 > /sys/class/leds/adcen-bat/brightness 2>/dev/null
                    value=$(cat "$input_file" 2>/dev/null)
                    echo 0 > /sys/class/leds/adcen-bat/brightness 2>/dev/null
                    ;;
                7)
                    echo 1 > /sys/class/leds/adcen-edlc/brightness 2>/dev/null
                    value=$(cat "$input_file" 2>/dev/null)
                    echo 0 > /sys/class/leds/adcen-edlc/brightness 2>/dev/null
                    ;;
            esac
        fi
        
        # Convert value if needed
        converted_value=$(convert_hwmon_value "$hwmon_num" "$input_num" "$value")
        
        # Get sensor label
        sensor_label=$(get_sensor_label "$hwmon_num" "$input_num")
        
        # Print the result
        if [ -n "$sensor_label" ]; then
            echo "  $input_basename: raw=$value, converted=$converted_value - $sensor_label"
        else
            echo "  $input_basename: raw=$value, converted=$converted_value"
        fi
    done
done

echo ""
echo "========================================"
echo "SFP SENSOR DATA"
echo "========================================"

# Function to get ethtool output for SFP data
get_sfp_data() {
    interface=$1
    
    # Check if interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        return 1
    fi
    
    # Get ethtool output
    output=$(ethtool --phy-statistics "$interface" 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Extract values
    temperature=$(echo "$output" | grep "Temperature" | awk '{print $NF}')
    vcc=$(echo "$output" | grep "VCC" | awk '{print $NF}')
    tx_bias=$(echo "$output" | grep "TX Bias" | awk '{print $NF}')
    tx_power=$(echo "$output" | grep "TX Power" | awk '{print $NF}')
    rx_power=$(echo "$output" | grep "RX Power" | awk '{print $NF}')
    
    # Check if temperature is valid (not too long)
    num_digits=$(echo "$temperature" | wc -c)
    if [ "$num_digits" -gt 6 ]; then
        temperature=0
    fi
    
    # Convert values
    vcc_converted=$((vcc / 10))
    tx_bias_converted=$((tx_bias * 2))
    tx_power_converted=$((tx_power / 10))
    rx_power_converted=$((rx_power / 10))
    
    echo ""
    echo "Interface: $interface"
    echo "  Temperature: raw=$temperature, converted=$temperature m°C"
    echo "  VCC: raw=$vcc, converted=$vcc_converted µV"
    echo "  TX Bias: raw=$tx_bias, converted=$tx_bias_converted µA"
    echo "  TX Power: raw=$tx_power, converted=$tx_power_converted µW"
    echo "  RX Power: raw=$rx_power, converted=$rx_power_converted µW"
    
    return 0
}

# Check all possible SFP interfaces
for iface in eth1 eth2 eth3 eth4 eth5 eth6; do
    get_sfp_data "$iface"
done

echo ""
echo "========================================"
echo "BOARD IDS"
echo "========================================"

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
    echo "ID MB:  $formatted_id"
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
    echo "ID DB:  $formatted_id"
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
    echo "ID ANT: $formatted_id"
}

show_eth0_mac(){
    mac=$(cat /sys/class/net/eth0/address 2>/dev/null)
    if [ -z "$mac" ]; then
        mac="error"
    fi
    echo "MAC TQ: $mac"
}

show_remote_mac(){
    if ! ping -c 1 -W 2 172.100.1.1 >/dev/null 2>&1; then
        echo "MAC COMexpress: not available"
        return
    fi
    
    # Get MAC address from ARP table
    mac=$(arp -n 172.100.1.1 | grep '172.100.1.1' | awk '{print $4}')
    
    # Validate MAC address format
    if [ -z "$mac" ] || ! echo "$mac" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
        mac="error"
    fi
    echo "MAC COMexpress: $mac"
}

# Main execution
show_mb_id
show_db_id
show_ant_id
show_eth0_mac
show_remote_mac