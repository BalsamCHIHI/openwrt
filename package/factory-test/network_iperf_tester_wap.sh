#!/bin/ash

# IPERF server IP
IPERF_SERVER="192.168.200.2"
IPERF_SERVER_WIFI="192.168.201.2"
IPERF_DURATION=10  # seconds
MAX_WAIT=20       # seconds

SENDER_IP="192.168.200.2"       # IP of the sender device
trigger_sfp_PORT="13000"              # Port to receive trigger_sfp
RESPONSE_PORT_sfp="13001"              # Port to send data back

trigger_hwm_PORT="14000"              # Port to receive trigger_hwm
RESPONSE_PORT_hwm="14001"              # Port to send data back
OUTPUT_FILE_sfp="/tmp/sfp_data_received.txt"
# Find the next available OUTPUT_FILE_hwm name
OUTPUT_FILE_HWM_BASE="/etc/factory/test_report"
OUTPUT_FILE_HWM_INDEX=1
while [ -e "${OUTPUT_FILE_HWM_BASE}${OUTPUT_FILE_HWM_INDEX}.txt" ]; do
    OUTPUT_FILE_HWM_INDEX=$((OUTPUT_FILE_HWM_INDEX + 1))
done
OUTPUT_FILE_hwm="${OUTPUT_FILE_HWM_BASE}${OUTPUT_FILE_HWM_INDEX}.txt"

OUTPUT_DIR=$(dirname "$OUTPUT_FILE_hwm")
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi

# Check for debug mode and test mode
DEBUG=0
TEST_MODE="all"

dmesg -n1

# Argument parsing
if [ "$#" -gt 2 ]; then
    echo "Usage: $0 [--ethernet|--wifi] [--debug]"
    exit 1
fi

for arg in "$@"; do
    case "$arg" in
        --debug)
            DEBUG=1
            dmesg -n7
            ;;
        --ethernet)
            TEST_MODE="ethernet"
            ;;
        --wifi)
            TEST_MODE="wifi"
            ;;
        *)
            echo "Usage: $0 [--ethernet|--wifi] [--debug]"
            echo "Error: Invalid argument '$arg'"
            exit 1
            ;;
    esac
done

log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "$1"
    fi
    # Always log to unified report file
    echo "$1" >> "$OUTPUT_FILE_hwm"
}

# Enable eth1 and eth4 initially
for i in 1 4; do
    ip link set eth$i up
done

sleep 5
# Remove OUTPUT_FILE_sfp if it exists
[ -f "$OUTPUT_FILE_sfp" ] && rm "$OUTPUT_FILE_sfp"

# Start listeners with improved setup (suppress output in non-debug mode)
if [ "$DEBUG" -eq 1 ]; then
    socat -u TCP4-LISTEN:$RESPONSE_PORT_sfp,reuseaddr OPEN:$OUTPUT_FILE_sfp,creat,append &
    SFP_LISTENER_PID=$!
    socat -u TCP4-LISTEN:$RESPONSE_PORT_hwm,reuseaddr OPEN:$OUTPUT_FILE_hwm,creat,append &
    HWM_LISTENER_PID=$!
else
    socat -u TCP4-LISTEN:$RESPONSE_PORT_sfp,reuseaddr OPEN:$OUTPUT_FILE_sfp,creat,append >/dev/null 2>&1 &
    SFP_LISTENER_PID=$!
    socat -u TCP4-LISTEN:$RESPONSE_PORT_hwm,reuseaddr OPEN:$OUTPUT_FILE_hwm,creat,append >/dev/null 2>&1 &
    HWM_LISTENER_PID=$!
fi

# Give socat a moment to start
sleep 1

# Function to send triggers and collect data
send_triggers() {
    # Send trigger to sender (suppress output in non-debug mode)
    if [ "$DEBUG" -eq 1 ]; then
        echo "SEND_SFP" | socat - TCP:$SENDER_IP:$trigger_sfp_PORT
        echo "SEND_HWD" | socat - TCP:$SENDER_IP:$trigger_hwm_PORT
    else
        echo "SEND_SFP" | socat - TCP:$SENDER_IP:$trigger_sfp_PORT >/dev/null 2>&1
        echo "SEND_HWD" | socat - TCP:$SENDER_IP:$trigger_hwm_PORT >/dev/null 2>&1
    fi

    for i in $(seq 1 20); do
        sleep 1
    done
}

# Initial attempt to collect data
send_triggers

kill $SFP_LISTENER_PID 2>/dev/null
kill $HWM_LISTENER_PID 2>/dev/null

# Clear previous report
echo "IPERF Test Report - $(date)" >> "$OUTPUT_FILE_hwm"
echo "==================" >> "$OUTPUT_FILE_hwm"
echo "" >> "$OUTPUT_FILE_hwm"

# Disable eth1 and eth4 initially
for i in 1 4; do
    ip link set eth$i down
done
#Disable wifi
wifi down

#*****************************************************************
#               ETHERNET INTERFACE CHECK
#*****************************************************************
ip link set bound up
if [ "$TEST_MODE" = "all" ] || [ "$TEST_MODE" = "ethernet" ]; then
    # Iterate through eth2 and eth4
    for i in 2 4; do
        ip link set eth$i up
        log "Bringing up eth$i..."

        # Poll for interface to be up
        WAITED=0
        while [ "$WAITED" -lt "$MAX_WAIT" ]; do
            STATE=$(cat /sys/class/net/eth$i/operstate 2>/dev/null)
            if [ "$STATE" = "up" ]; then
                log "eth$i is up"
                break
            fi
            sleep 1
            WAITED=$((WAITED + 1))
        done

        if [ "$STATE" != "up" ]; then
            [ "$DEBUG" -eq 1 ] && echo "❌ eth$i: Interface did not come up"
            [ "$DEBUG" -eq 0 ] && echo "❌ KO eth$i"
            echo "eth$i: Interface did not come up" >> "$OUTPUT_FILE_hwm"
            continue
        fi

        log "Checking connectivity to $IPERF_SERVER from eth$i..."
        if ! ping -c 10 -W 1 $IPERF_SERVER >/dev/null 2>&1; then
            [ "$DEBUG" -eq 1 ] && echo "❌ eth$i: No connectivity to $IPERF_SERVER"
            [ "$DEBUG" -eq 0 ] && echo "❌ KO eth$i"
            echo "eth$i: No connectivity to $IPERF_SERVER" >> "$OUTPUT_FILE_hwm"
            ip link set eth$i down
            continue
        fi

        log "Starting iperf test on eth$i..."
        IPERF_OUTPUT=$(iperf -c $IPERF_SERVER -t $IPERF_DURATION -P 8 2>&1)

        # Extract transfer and bitrate
        TRANSFER_LINE=$(echo "$IPERF_OUTPUT" | grep -E '[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\s+sec\s+[0-9.]+\s+[MG]Bytes\s+[0-9.]+\s+Mbits/sec' | tail -n1)
        TRANSFER=$(echo "$TRANSFER_LINE" | awk '{print $(NF-3), $(NF-2)}')
        BITRATE_VALUE=$(echo "$TRANSFER_LINE" | awk '{print $(NF-1)}')
        BITRATE_UNIT=$(echo "$TRANSFER_LINE" | awk '{print $NF}')

        # Convert bitrate to numeric Mbps
        BITRATE_MBPS=$(echo "$BITRATE_VALUE" | awk '{printf "%.0f", $1}')

        if [ -n "$BITRATE_MBPS" ] && [ "$BITRATE_MBPS" -ge 50 ]; then
            if [ "$DEBUG" -eq 1 ]; then
                echo "✅ eth$i: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT"
            else
                echo "✅ OK eth$i"
            fi
            echo "eth$i: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT" >> "$OUTPUT_FILE_hwm"
        else
            if [ "$DEBUG" -eq 1 ]; then
                echo "❌ eth$i: Bitrate too low or iperf test failed: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT"
            else
                echo "❌ KO eth$i"
            fi
            echo "eth$i: Bitrate too low or iperf test failed: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT" >> "$OUTPUT_FILE_hwm"
            echo "$IPERF_OUTPUT" >> "$OUTPUT_FILE_hwm"
        fi

        if [ "$i" -ne 7 ] && [ "$i" -ne 8 ]; then
            if [ -f "$OUTPUT_FILE_sfp" ]; then
                REMOTE_STATS=$(awk -v iface="eth$i" '
                    $0 ~ "Interface: "iface {
                        getline; temp=$2;
                        getline; vcc=$2;
                        getline; tx=$3;
                        getline; rx=$3;
                        print temp, vcc, tx, rx
                    }
                ' "$OUTPUT_FILE_sfp")

                # Get PHY statistics
                PHY_STATS=$(ethtool --phy-statistics eth$i 2>/dev/null)
                TX_POWER_LOCAL=$(echo "$PHY_STATS" | grep "TX Power" | awk '{print $NF}')
                RX_POWER_LOCAL=$(echo "$PHY_STATS" | grep "RX Power" | awk '{print $NF}')
                TEMPERATURE_LOCAL=$(echo "$PHY_STATS" | grep "Temperature" | awk '{print $NF}')
                VCC_LOCAL=$(echo "$PHY_STATS" | grep "VCC" | awk '{print $NF}')

                TEMPERATURE_REMOTE=$(echo "$REMOTE_STATS" | awk '{print $1}')
                VCC_REMOTE=$(echo "$REMOTE_STATS" | awk '{print $2}')
                TX_POWER_REMOTE=$(echo "$REMOTE_STATS" | awk '{print $3}')
                RX_POWER_REMOTE=$(echo "$REMOTE_STATS" | awk '{print $4}')

                echo "eth$i: Local TX Power: $TX_POWER_LOCAL, Local RX Power: $RX_POWER_LOCAL, Remote TX Power: $TX_POWER_REMOTE, Remote RX Power: $RX_POWER_REMOTE" >> "$OUTPUT_FILE_hwm"
                [ "$DEBUG" -eq 1 ] && echo "eth$i: Local TX: $TX_POWER_LOCAL, Local RX: $RX_POWER_LOCAL, Remote TX: $TX_POWER_REMOTE, Remote RX: $RX_POWER_REMOTE"

                if [ -n "$TX_POWER_LOCAL" ] && [ -n "$RX_POWER_LOCAL" ] && [ -n "$TX_POWER_REMOTE" ] && [ -n "$RX_POWER_REMOTE" ]; then
                    RATIO_TX_REMOTE_RX_LOCAL=$(awk "BEGIN {printf \"%.2f\", $TX_POWER_REMOTE / $RX_POWER_LOCAL}")
                    RATIO_TX_LOCAL_RX_REMOTE=$(awk "BEGIN {printf \"%.2f\", $TX_POWER_LOCAL / $RX_POWER_REMOTE}")
                    ATTENUATION_TX_LOCAL_RX_REMOTE=$(awk "BEGIN {printf \"%.2f\", 10 * log($TX_POWER_LOCAL / $RX_POWER_REMOTE) / log(10)}")
                    ATTENUATION_RX_LOCAL_TX_REMOTE=$(awk "BEGIN {printf \"%.2f\", 10 * log($RX_POWER_LOCAL / $TX_POWER_REMOTE) / log(10)}")
                    echo "eth$i:  Local TX: $TX_POWER_LOCAL, RX: $RX_POWER_LOCAL  |  Remote TX: $TX_POWER_REMOTE, RX: $RX_POWER_REMOTE" >> "$OUTPUT_FILE_hwm"
                    echo "eth$i:  Attenuation TX_LOCAL/RX_REMOTE = $ATTENUATION_TX_LOCAL_RX_REMOTE | Attenuation RX_LOCAL/TX_REMOTE = $ATTENUATION_RX_LOCAL_TX_REMOTE" >> "$OUTPUT_FILE_hwm"

                    # Check if ratios are within acceptable range (0.4 to 2.5)
                    RATIO_CHECK=$(awk -v r1="$RATIO_TX_REMOTE_RX_LOCAL" -v r2="$RATIO_TX_LOCAL_RX_REMOTE" 'BEGIN {
                        if ((r1 < 0.4 || r1 > 2.5) || (r2 < 0.4 || r2 > 2.5)) print "FAIL"; else print "PASS"
                    }')

                    if [ "$RATIO_CHECK" = "FAIL" ]; then
                        [ "$DEBUG" -eq 1 ] && echo "❌ eth$i: TX/RX ratio out of range (0.4-2.5): TX_REMOTE/RX_LOCAL=$RATIO_TX_REMOTE_RX_LOCAL, TX_LOCAL/RX_REMOTE=$RATIO_TX_LOCAL_RX_REMOTE"
                        [ "$DEBUG" -eq 0 ] && echo "❌ KO eth$i (TX/RX ratio)"
                        echo "eth$i: FAIL - TX/RX ratio out of acceptable range (0.4-2.5)" >> "$OUTPUT_FILE_hwm"
                    else
                        [ "$DEBUG" -eq 1 ] && echo "eth$i:  Attenuation TX_LOCAL/RX_REMOTE = $ATTENUATION_TX_LOCAL_RX_REMOTE | Attenuation RX_LOCAL/TX_REMOTE = $ATTENUATION_RX_LOCAL_TX_REMOTE"
                    fi
                else
                    echo "eth$i: ⚠️ Incomplete data for TX/RX power difference calculation" >> "$OUTPUT_FILE_hwm"
                    [ "$DEBUG" -eq 1 ] && echo "⚠️ eth$i: Incomplete data for TX/RX power difference calculation"
                fi
            else
                if [ -n "$TX_POWER_LOCAL" ] && [ -n "$RX_POWER_LOCAL" ]; then
                    echo "eth$i: TX Power: $TX_POWER_LOCAL, RX Power: $RX_POWER_LOCAL" >> "$OUTPUT_FILE_hwm"
                    [ "$DEBUG" -eq 1 ] && echo "📶 eth$i: TX Power: $TX_POWER_LOCAL, RX Power: $RX_POWER_LOCAL"
                else
                    echo "eth$i: Failed to retrieve TX/RX Power" >> "$OUTPUT_FILE_hwm"
                    [ "$DEBUG" -eq 1 ] && echo "⚠️ eth$i: Failed to retrieve TX/RX Power"
                fi
            fi
        fi

        ip link set eth$i down
    done
fi

#*****************************************************************
#               WIFI INTERFACE CHECK
#*****************************************************************
if [ "$TEST_MODE" = "all" ] || [ "$TEST_MODE" = "wifi" ]; then
    # Extract MAC address for WiFi SSID configuration
    MAC_FOR_WIFI=""
    if [ -f "$OUTPUT_FILE_hwm" ]; then
        MAC_LINE=$(grep "Machine MAC Address:" "$OUTPUT_FILE_hwm" | head -1)
        if [ -n "$MAC_LINE" ]; then
            MAC_FOR_WIFI=$(echo "$MAC_LINE" | awk '{print $4}')
        fi
    fi
    
    # Connect to 5GHz WiFi network
    wifi up
    sleep 2
    uci delete wireless.sta_radio1.disabled 2>/dev/null  # Enable 5GHz
    if [ "$DEBUG" -eq 1 ]; then
        if [ -n "$MAC_FOR_WIFI" ]; then
            /usr/bin/switch_wifi_fw.sh switch compex 5g "$MAC_FOR_WIFI"
        else
            /usr/bin/switch_wifi_fw.sh switch compex 5g
        fi
    else
        if [ -n "$MAC_FOR_WIFI" ]; then
            /usr/bin/switch_wifi_fw.sh switch compex 5g "$MAC_FOR_WIFI" >/dev/null 2>&1
        else
            /usr/bin/switch_wifi_fw.sh switch compex 5g >/dev/null 2>&1
        fi
    fi
    sleep 30
    # Test WiFi 5GHz
    log "Checking connectivity to $IPERF_SERVER_WIFI over WiFi..."
    if ! ping -c 10 -W 1 $IPERF_SERVER_WIFI >/dev/null 2>&1; then
        [ "$DEBUG" -eq 1 ] && echo "❌ WiFi 5GHz: No connectivity to $IPERF_SERVER_WIFI"
        [ "$DEBUG" -eq 0 ] && echo "❌ WiFi 5GHz"
        echo "WiFi 5GHz: No connectivity to $IPERF_SERVER_WIFI" >> "$OUTPUT_FILE_hwm"
    else
        log "Starting iperf test on WiFi 5GHz..."

        IPERF_OUTPUT=$(iperf -c $IPERF_SERVER_WIFI -t $IPERF_DURATION -P 8 2>&1)

        # Extract the [SUM] line
        SUM_LINE=$(echo "$IPERF_OUTPUT" | grep '\[SUM\]')

        # Extract transfer and bitrate from the SUM line
        TRANSFER=$(echo "$SUM_LINE" | awk '{print $(NF-3), $(NF-2)}')
        BITRATE_VALUE=$(echo "$SUM_LINE" | awk '{print $(NF-1)}')
        BITRATE_UNIT=$(echo "$SUM_LINE" | awk '{print $NF}')

        # Convert bitrate to Mbps for comparison
        if [[ "$BITRATE_UNIT" == "Gbits/sec" ]]; then
            BITRATE_MBPS=$(awk "BEGIN {printf \"%.0f\", $BITRATE_VALUE * 1000}")
        else
            BITRATE_MBPS=$(awk "BEGIN {printf \"%.0f\", $BITRATE_VALUE}")
        fi

        # Evaluate result
        if [ -n "$BITRATE_MBPS" ] && [ "$BITRATE_MBPS" -ge 200 ]; then
            [ "$DEBUG" -eq 1 ] && echo "✅ WiFi 5GHz: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT"
            [ "$DEBUG" -eq 0 ] && echo "✅ WiFi 5GHz"
            echo "WiFi 5GHz: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT" >> "$OUTPUT_FILE_hwm"
        else
            [ "$DEBUG" -eq 1 ] && echo "❌ WiFi 5GHz: Bitrate too low or iperf test failed"
            [ "$DEBUG" -eq 0 ] && echo "❌ WiFi 5GHz"
            echo "WiFi 5GHz: Bitrate too low or iperf test failed" >> "$OUTPUT_FILE_hwm"
            echo "$IPERF_OUTPUT" >> "$OUTPUT_FILE_hwm"
        fi
    fi

    if [ "$DEBUG" -eq 1 ]; then
        if [ -n "$MAC_FOR_WIFI" ]; then
            /usr/bin/switch_wifi_fw.sh switch compex 2g "$MAC_FOR_WIFI"
        else
            /usr/bin/switch_wifi_fw.sh switch compex 2g
        fi
    else
        if [ -n "$MAC_FOR_WIFI" ]; then
            /usr/bin/switch_wifi_fw.sh switch compex 2g "$MAC_FOR_WIFI" >/dev/null 2>&1
        else
            /usr/bin/switch_wifi_fw.sh switch compex 2g >/dev/null 2>&1
        fi
    fi
    sleep 10
    # Test WiFi 2.4GHz
    log "Checking connectivity to $IPERF_SERVER_WIFI over WiFi..."
    
    # Try ping up to 3 times with 30s intervals, restarting WiFi between attempts
    PING_SUCCESS=0
    for PING_ATTEMPT in 1 2 3 4 5; do
        if ping -c 10 -W 1 $IPERF_SERVER_WIFI >/dev/null 2>&1; then
            PING_SUCCESS=1
            [ "$DEBUG" -eq 1 ] && echo "WiFi 2.4GHz: Ping successful on attempt $PING_ATTEMPT"
            break
        else
            [ "$DEBUG" -eq 1 ] && echo "WiFi 2.4GHz: Ping failed on attempt $PING_ATTEMPT"
            
            if [ $PING_ATTEMPT -lt 3 ]; then
                log "Restarting WiFi after failed ping attempt $PING_ATTEMPT..."
                wifi down
                sleep 2
                wifi up
                sleep 30
            fi
        fi
    done
    
    if [ $PING_SUCCESS -eq 0 ]; then
        [ "$DEBUG" -eq 1 ] && echo "❌ WiFi 2.4GHz: No connectivity to $IPERF_SERVER_WIFI after 3 attempts"
        [ "$DEBUG" -eq 0 ] && echo "❌ WiFi 2.4GHz"
        echo "WiFi 2.4GHz: No connectivity to $IPERF_SERVER_WIFI after 3 attempts" >> "$OUTPUT_FILE_hwm"
    else

        log "Starting iperf test on WiFi 2.4GHz..."
        IPERF_OUTPUT=$(iperf -c $IPERF_SERVER_WIFI -t $IPERF_DURATION -P 8 2>&1)

        TRANSFER_LINE=$(echo "$IPERF_OUTPUT" | grep -E '[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\s+sec\s+[0-9]+\.*[0-9]*\s+MBytes\s+[0-9]+\.*[0-9]*\s+Mbits/sec' | tail -n1)

        if [ -n "$TRANSFER_LINE" ]; then
            TRANSFER=$(echo "$TRANSFER_LINE" | awk '{print $(NF-3), $(NF-2)}')
            BITRATE_VALUE=$(echo "$TRANSFER_LINE" | awk '{print $(NF-1)}')
            BITRATE_UNIT=$(echo "$TRANSFER_LINE" | awk '{print $NF}')
            BITRATE_MBPS=$(echo "$BITRATE_VALUE" | awk '{printf "%.0f", $1}')
        else
            TRANSFER="0 MBytes"
            BITRATE_VALUE="0"
            BITRATE_UNIT="Mbits/sec"
            BITRATE_MBPS=0
        fi

        if [ "$BITRATE_MBPS" -ge 5 ]; then
            [ "$DEBUG" -eq 1 ] && echo "✅ WiFi 2.4GHz: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT"
            [ "$DEBUG" -eq 0 ] && echo "✅ WiFi 2.4GHz"
            echo "WiFi 2.4GHz: Transfer: $TRANSFER, Bitrate: $BITRATE_VALUE $BITRATE_UNIT" >> "$OUTPUT_FILE_hwm"
        else
            [ "$DEBUG" -eq 1 ] && echo "❌ WiFi 2.4GHz: Bitrate too low or iperf test failed"
            [ "$DEBUG" -eq 0 ] && echo "❌ WiFi 2.4GHz"
            echo "WiFi 2.4GHz: Bitrate too low or iperf test failed" >> "$OUTPUT_FILE_hwm"
            echo "$IPERF_OUTPUT" >> "$OUTPUT_FILE_hwm"
        fi
    fi
    wifi down
fi

# Enable eth1 and eth4
for i in 1 4; do
    ip link set eth$i up
done

# Rename output file to MAC_ADDRESS_INDEX.txt format
if [ -f "$OUTPUT_FILE_hwm" ]; then
    MAC_LINE=$(grep "Machine MAC Address:" "$OUTPUT_FILE_hwm" | head -1)
    if [ -n "$MAC_LINE" ]; then
        MAC_ADDR=$(echo "$MAC_LINE" | awk '{print $4}' | tr -d ':')
        if [ -n "$MAC_ADDR" ]; then
            # Per-MAC index: find next available number
            idx=1
            while [ -e "${OUTPUT_DIR}/${MAC_ADDR}_${idx}.txt" ]; do
                idx=$((idx + 1))
            done
            NEW_FILENAME="${OUTPUT_DIR}/${MAC_ADDR}_${idx}.txt"
            mv "$OUTPUT_FILE_hwm" "$NEW_FILENAME"
            echo "Test report saved as: $NEW_FILENAME"
        else
            echo "Test report saved as: $OUTPUT_FILE_hwm"
        fi
    else
        echo "Test report saved as: $OUTPUT_FILE_hwm"
    fi
else
    echo "No test report generated"
fi