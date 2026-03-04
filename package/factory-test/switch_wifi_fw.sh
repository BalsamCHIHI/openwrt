#!/bin/ash

# Configuration
ATH11K_FIRMWARE_DIR="/lib/firmware/ath11k"
COMPEX_DIR="$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0/compex"
EIGHTDEVICES_DIR="$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0/8devices"

BOARD_CAL_DIR="$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0"
BOARD_2G_FILE="board-2-2g.bin"
BOARD_5G_FILE="board-2-5g.bin"
BOARD_ACTIVE="board-2.bin"

# Get actual PCI device path
get_actual_pci_path() {
    # POSIX-safe implementation (avoid [[ ]] )
    lspci | grep -i -E 'network|wireless' | awk '{print $1}' | while read addr; do
        case "$addr" in
            *01:00.0)
                case "$addr" in
                    0000:*) echo 0000:01:00.0; return 0;;
                    0001:*) echo 0001:01:00.0; return 0;;
                    *) echo "$addr"; return 0;;
                esac
                ;;
        esac
    done
}

# Sanitize band input
sanitize_band() {
    echo "$1" | tr -d ' \t\r\n'
}


# Revised: do NOT point to non-existent 2G/5G blobs. Only keep override if real file exists.
create_band_config() {
    local firmware_set=$1
    local raw_band=$2
    local band=$(sanitize_band "$raw_band")
    local actual_pci=$3
    local target_config="$ATH11K_FIRMWARE_DIR/fwcfg-pci-$actual_pci.txt"

    local two_g five_g desired blob_path
    case "$firmware_set" in
        compex)
            two_g="compex/WLE3000HX_2G.bin"; five_g="compex/WLE3000HX_5G.bin" ;;
        8devices)
            two_g="8devices/2G_Temporary_GoldenBin.bin"; five_g="8devices/5G_Temporary_GoldenBin.bin" ;;
        *) echo "ℹ️ Unknown firmware set '$firmware_set' (no override)"; return 0 ;;
    esac

    case "$band" in
        2g) desired="$two_g" ;;
        5g) desired="$five_g" ;;
        both) desired="" ;; # no override, rely on board-2.bin
        *) echo "⚠️ Invalid band '$band' in create_band_config"; desired="" ;;
    esac

    if [ -n "$desired" ]; then
        blob_path="$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0/$desired"
        if [ -f "$blob_path" ]; then
            echo "bname = $desired" > "$target_config"
            echo "✅ Band=$band -> using blob: $desired"
        else
            rm -f "$target_config" 2>/dev/null
            echo "ℹ️ Desired blob not found ($blob_path); falling back to board-2.bin"
        fi
    else
        rm -f "$target_config" 2>/dev/null
        echo "ℹ️ No per-band blob selected (band=$band). Using board-2.bin"
    fi
}

# Safer wireless config adjustment (no full wipe)
configure_wireless_for_band() {
    local band=$1
    local phy=$2

    # Determine radio section (reuse existing or create)
    local radio_section
    # Try to find an existing device pointing to our PCI path
    local pci_path='soc/3500000.pcie/pci0001:00/0001:00:00.0/0001:01:00.0'
    radio_section=$(uci show wireless 2>/dev/null | grep "$pci_path" | cut -d'.' -f2 | cut -d'=' -f1 | head -1)
    [ -z "$radio_section" ] && radio_section=radio0

    if ! uci -q get wireless.$radio_section >/dev/null; then
        uci set wireless.$radio_section=wifi-device
        uci set wireless.$radio_section.type='mac80211'
        uci set wireless.$radio_section.path="$pci_path"
    fi

    uci set wireless.sta_radio0.disabled='1' 2>/dev/null
    uci set wireless.sta_radio1.disabled='1' 2>/dev/null
    case $band in
        2g)
            uci set wireless.$radio_section.band='2g'
            uci set wireless.$radio_section.channel='auto'
            uci set wireless.$radio_section.htmode='HT20'
            #uci set wireless.sta_$radio_section.ssid='Connect-Server-2.4GHz'
            uci set wireless.sta_radio0.encryption='none'
            uci set wireless.sta_radio0.disabled='0'
            ;;
        5g)
            uci set wireless.$radio_section.band='5g'
            uci set wireless.$radio_section.channel='auto'
            uci set wireless.$radio_section.htmode='HE160'
            #uci set wireless.sta_$radio_section.ssid='Connect-Server-5GHz'
            uci set wireless.sta_radio1.encryption='none'
            uci set wireless.sta_radio1.disabled='0'
            ;;
        both)
            # Fallback: keep 5g settings (cannot truly dual-band same single phy)
            uci set wireless.$radio_section.band='5g'
            uci set wireless.$radio_section.channel='auto'
            uci set wireless.$radio_section.htmode='HE160'
            ;;
    esac

    uci commit wireless
    echo "✅ Applied wireless band configuration ($band) to $radio_section"
}

check_board_magic_and_fallback() {
    # If invalid board magic appears, drop override config and reload once
    if dmesg | tail -120 | grep -q "invalid board magic"; then
        local cfg=$(ls /lib/firmware/ath11k/fwcfg-pci-*.txt 2>/dev/null | head -1)
        if [ -n "$cfg" ]; then
            echo "⚠️ Detected invalid board magic. Removing override $(basename "$cfg") and reloading driver.";
            mv "$cfg" "$cfg.bad_$(date +%s)" 2>/dev/null || rm -f "$cfg"
            unload_driver_stack
            load_driver || echo "⚠️ Reload after fallback failed"
        fi
    fi
}

# Stop WiFi services
stop_wifi() {
    echo "Stopping WiFi services..."
    wifi down 2>/dev/null
    /etc/init.d/network stop
    killall wpa_supplicant 2>/dev/null
    killall hostapd 2>/dev/null
    sleep 3
}

ATH11K_LOAD_SEQUENCE="compat cfg80211 mac80211 qrtr qrtr_tun qrtr_mhi mhi qmi_helpers ath11k ath11k_pci"
ATH11K_UNLOAD_SEQUENCE="ath11k_pci ath11k qmi_helpers mhi qrtr_mhi qrtr_tun qrtr mac80211 cfg80211 compat"

module_loaded() {
    local module=$1
    lsmod | awk 'NR>1 {print $1}' | grep -Fxq "$module" 2>/dev/null
}

load_module_sequenced() {
    local module=$1
    if module_loaded "$module"; then
        echo "Module $module already present"
        return 0
    fi

    echo "Loading module: $module"
    case "$module" in
        ath11k)
            modprobe ath11k skip_otp=Y 2>/dev/null || return 1
            ;;
        *)
            modprobe "$module" 2>/dev/null || return 1
            ;;
    esac
    sleep 1
    return 0
}

unload_module_sequenced() {
    local module=$1
    if ! module_loaded "$module"; then
        return 0
    fi

    echo "Removing module: $module"
    modprobe -r "$module" 2>/dev/null || rmmod "$module" 2>/dev/null || true
    sleep 1
}

unload_driver_stack() {
    echo "Unloading ath11k driver stack (reverse order)"
    for module in $ATH11K_UNLOAD_SEQUENCE; do
        unload_module_sequenced "$module"
    done
}

# Load ath11k driver with proper sequencing
load_driver() {
    echo "Loading ath11k driver with proper sequencing..."
    
    # Clean any stale firmware files
    rm -f /tmp/ath11k*
    
    # Force kernel firmware loader timeout to be longer
    echo 30 > /sys/class/firmware/timeout 2>/dev/null || true
    
    # Check PCI device is accessible before loading driver
    if ! lspci | grep -q "0001:01:00.0"; then
        echo "❌ PCI device not found, checking PCI bus..."
        lspci | grep -i "network\|wireless"
        return 1
    fi
    
    # Load in proper dependency order based on lsmod snapshot
    for module in $ATH11K_LOAD_SEQUENCE; do
        if ! load_module_sequenced "$module"; then
            echo "❌ Failed to load module $module"
            return 1
        fi
    done
    sleep 2
    
    # Check if module loaded successfully
    if ! lsmod | grep -q "ath11k_pci"; then
        echo "❌ ath11k_pci module failed to load!"
        echo "Checking dmesg for errors:"
        dmesg | tail -10 | grep -E "(ath11k|mhi|firmware|error)"
        return 1
    fi
    
    # Verify the firmware was loaded correctly
    echo "Verifying firmware loading..."
    local fw_config="/lib/firmware/ath11k/fwcfg-pci-0001:01:00.0.txt"
    if [ -f "$fw_config" ]; then
        echo "Firmware config: $(cat $fw_config)"
    else
        echo "❌ Firmware config file not found!"
    fi
    
    echo "✅ All modules loaded successfully:"
    lsmod | grep -E "(ath11k|mhi|qmi)" | awk '{print "  " $1}'
    
    # Wait for device to be ready with enhanced timeout
    local timeout=30  # Reduced timeout since PCI issues are immediate
    local count=0
    echo "Waiting for PHY device..."
    while [ $count -lt $timeout ]; do
        if ls /sys/class/ieee80211/phy* >/dev/null 2>&1; then
            echo "✅ PHY device found after $count seconds"
            
            # Give the device additional time to initialize
            sleep 3
            
            # Force regulatory domain to match your country code
            iw reg set FR
            
            return 0
        fi
        sleep 1
        count=$((count + 1))
        # Show progress every 5 seconds
        if [ $((count % 5)) -eq 0 ]; then
            echo "Still waiting for PHY device... ($count/$timeout)"
            # Check for errors early
            if dmesg | tail -5 | grep -q "failed to claim device"; then
                echo "❌ PCI device claim failed - aborting"
                dmesg | tail -10 | grep -E "(ath11k|error|failed)"
                return 1
            fi
        fi
    done
    
    echo "❌ No PHY device found after $timeout seconds"
    echo "Checking dmesg for errors:"
    dmesg | tail -30 | grep -E "(ath11k|mhi|firmware)"
    return 1
}

# Verify setup
verify_setup() {
    echo ""
    echo "=== Verifying WiFi Setup ==="
    
    echo "1. WiFi interfaces:"
    iw dev 2>/dev/null || echo "No WiFi interfaces found"
    
    echo ""
    echo "2. Firmware configuration:"
    ls -la "$ATH11K_FIRMWARE_DIR"/fwcfg-pci-*.txt 2>/dev/null || echo "No firmware config found"
    echo "Active firmware config content:"
    if [ -f "$ATH11K_FIRMWARE_DIR/fwcfg-pci-0001:01:00.0.txt" ]; then
        cat "$ATH11K_FIRMWARE_DIR/fwcfg-pci-0001:01:00.0.txt"
    fi
    
    echo ""
    echo "3. Wireless UCI configuration:"
    uci show wireless 2>/dev/null | grep -E "(band|channel|ssid|encryption|disabled)" || echo "No wireless config found"
    
    echo ""
    echo "4. Connection status:"
    local wifi_iface=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
    if [ -n "$wifi_iface" ]; then
        echo "Interface: $wifi_iface"
        local link_info=$(iw dev "$wifi_iface" link 2>/dev/null)
        echo "$link_info"
        
        # Extract frequency from link info
        local freq=$(echo "$link_info" | grep "freq:" | awk '{print $2}')
        if [ -n "$freq" ]; then
            if [ "$freq" -lt 3000 ]; then
                echo "✅ Connected to 2.4GHz ($freq MHz)"
            else
                echo "✅ Connected to 5GHz ($freq MHz)"
            fi
        fi
    else
        echo "No WiFi interface found"
    fi
}

# Verify firmware switch was successful
verify_firmware_switch() {
    local expected_band=$(sanitize_band "$1")
    local fw_config_root="$ATH11K_FIRMWARE_DIR/fwcfg-pci-0001:01:00.0.txt"
    local override_line
    echo "=== Verifying Firmware Switch (expected $expected_band) ==="
    for cfg in "$fw_config_root" "$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0/compex/fwcfg-pci-0001:01:00.0.txt" "$ATH11K_FIRMWARE_DIR/QCN9074/hw1.0/8devices/fwcfg-pci-0001:01:00.0.txt"; do
        [ -f "$cfg" ] && { override_line=$(grep -E '^bname' "$cfg" 2>/dev/null); echo "Found override: $cfg -> $override_line"; break; }
    done
    [ -z "$override_line" ] && echo "ℹ️ No override; relying on board-2.bin"
    local iface=$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
    if [ -z "$iface" ]; then echo "⚠️ No interface for verification"; return 1; fi
    ip link set "$iface" up 2>/dev/null; iw reg set FR 2>/dev/null
    iw dev "$iface" scan trigger >/dev/null 2>&1; sleep 5
    local pattern count
    if [ "$expected_band" = "2g" ]; then pattern='freq: 24[0-9][0-9]'; else pattern='freq: [345][0-9][0-9][0-9]'; fi
    count=$(iw dev "$iface" scan dump 2>/dev/null | grep -E "$pattern" | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "✅ Verification scan found $count channels for $expected_band"
        return 0
    else
        echo "❌ Verification scan found 0 channels for $expected_band"
        return 1
    fi
}

# Force WiFi interface creation if missing
force_wifi_interface_creation() {
    local phy=$1
    echo "Attempting to force WiFi interface creation..."
    local existing_iface=$(iw dev | awk '/Interface/ {print $2; exit}')
    if [ -n "$existing_iface" ]; then
        echo "WiFi interface already exists: $existing_iface"; return 0; fi
    local iface_name="${phy}-sta0"
    echo "Creating interface $iface_name on $phy..."
    if iw phy "$phy" interface add "$iface_name" type managed; then
        echo "✅ Successfully created interface: $iface_name"
        sleep 1
        ip link set "$iface_name" up 2>/dev/null
        return 0
    else
        echo "❌ Failed to create WiFi interface"; return 1
    fi
}

# Minimal start_wifi helper (re-added)
start_wifi() {
    echo "Starting WiFi (wifi up)";
    wifi up 2>/dev/null || /etc/init.d/network start 2>/dev/null || true
    sleep 3
    local iface=$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
    if [ -n "$iface" ]; then
        ip link set "$iface" up 2>/dev/null
        iw reg set FR 2>/dev/null
        iw dev "$iface" scan trigger >/dev/null 2>&1
        sleep 4
        echo "Interfaces:"; iw dev 2>/dev/null | awk '/Interface/ {print "  - "$2}'
    else
        echo "⚠️ No interface after wifi up"
    fi
}

# Generic band connectivity / presence test
# Args: label min_freq max_freq
test_band_connection() {
    local label=$1; local min_f=$2; local max_f=$3
    local iface=$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
    [ -z "$iface" ] && { echo "❌ $label: no interface"; return 1; }
    # If already connected, check freq
    local link=$(iw dev "$iface" link 2>/dev/null)
    local freq=$(echo "$link" | awk '/freq:/ {print $2}')
    if [ -n "$freq" ]; then
        if [ "$freq" -ge "$min_f" ] && [ "$freq" -le "$max_f" ]; then
            echo "✅ $label: interface freq $freq MHz in range ($min_f-$max_f)"
            return 0
        fi
    fi
    # Otherwise scan and see if any channels in range appear
    iw dev "$iface" scan trigger >/dev/null 2>&1
    sleep 5
    local count=$(iw dev "$iface" scan dump 2>/dev/null | awk '/freq:/ {f=$2; if (f>='"$min_f"' && f<='"$max_f"') c++} END {print c+0}')
    if [ "$count" -gt 0 ]; then
        echo "✅ $label: detected $count channels in range ($min_f-$max_f)"
        return 0
    else
        echo "❌ $label: no channels detected in range ($min_f-$max_f)"
        return 1
    fi
}

# Main firmware switching function
switch_firmware() {
    local firmware_set=$1
    local band=$2
    
    echo "=========================================="
    echo "    WiFi Firmware Switching Script v3"
    echo "=========================================="
    echo "Switching to $firmware_set firmware ($band band)"
    echo "Target network: 'Moment' (WPA2-PSK)"
    echo ""
    
    # Validate inputs
    case $firmware_set in
        "compex"|"8devices") ;;
        *)
            echo "Error: Unknown firmware set '$firmware_set'"
            echo "Valid options: compex, 8devices"
            exit 1
            ;;
    esac
    
    case $band in
        "2g"|"5g"|"both") ;;
        *)
            echo "Error: Unknown band '$band'"
            echo "Valid options: 2g, 5g, both"
            exit 1
            ;;
    esac
    
    # Get the correct PCI path
    ACTUAL_PCI=$(get_actual_pci_path)
    if [ -z "$ACTUAL_PCI" ]; then
        echo "Error: Could not detect WiFi PCI device"
        exit 1
    fi
    echo "Detected PCI path: $ACTUAL_PCI"
    
    # Set firmware directory
    case $firmware_set in
        "compex")
            FIRMWARE_DIR="$COMPEX_DIR"
            ;;
        "8devices")
            FIRMWARE_DIR="$EIGHTDEVICES_DIR"
            ;;
    esac
    
    # Check if firmware directory exists
    if [ ! -d "$FIRMWARE_DIR" ]; then
        echo "Error: Firmware directory not found: $FIRMWARE_DIR"
        exit 1
    fi
    
    # Stop services and unload driver
    stop_wifi
    
    # Skip driver unload/reload for now - just change firmware config
    echo "Changing firmware configuration without driver reload..."
    
    # Create band-specific firmware configuration
    echo ""
    if ! create_band_config "$firmware_set" "$band" "$ACTUAL_PCI" "$FIRMWARE_DIR"; then
        echo "Error: Failed to create firmware config"
        exit 1
    fi
    
    
    # Check if PHY interface already exists (avoid driver reload)
    EXISTING_PHY=$(ls /sys/class/ieee80211/ 2>/dev/null | head -1)
    if [ -n "$EXISTING_PHY" ]; then
        echo "Using existing PHY interface: $EXISTING_PHY"
        NEW_PHY="$EXISTING_PHY"
    else
        # Load driver only if no PHY exists
        echo ""
        if ! load_driver; then
            echo "Error: Failed to load driver"
            exit 1
        fi
        
        # Find the new PHY interface
        echo ""
        echo "Waiting for PHY interface..."
        sleep 3
        NEW_PHY=$(ls /sys/class/ieee80211/ 2>/dev/null | head -1)
        if [ -z "$NEW_PHY" ]; then
            echo "Error: No PHY interface found"
            exit 1
        fi
        echo "New PHY interface: $NEW_PHY"
    fi
    
    # Configure wireless for the correct band
    echo ""
    configure_wireless_for_band "$band" "$NEW_PHY"
    
    # Start WiFi services
    echo ""
    start_wifi
    
    # Test connection for specific bands
    case $band in
        "2g")
            echo ""
            test_band_connection "2.4GHz" 2400 2500
            ;;
        "5g")
            echo ""
            test_band_connection "5GHz" 5000 6000
            ;;
        "both")
            echo ""
            echo "Dual-band mode configured - manual testing required"
            ;;
    esac
    
    # Verify firmware switch
    verify_firmware_switch "$band" "$firmware_set"
    
    echo ""
    echo "=== Firmware switch completed ==="
}

# Simple firmware switch without driver reload
simple_firmware_switch() {
    local firmware_set=$1
    local raw_band=$2
    local band=$(sanitize_band "$raw_band")
    
    echo "=========================================="
    echo "  Simple Firmware Switch (No Driver Reload)"
    echo "=========================================="
    echo "Switching to $firmware_set firmware ($band band)"
    echo "Target network: 'Moment' (WPA2-PSK)"
    echo ""
    
    # Validate inputs
    case $firmware_set in
        "compex"|"8devices") ;;
        *)
            echo "Error: Unknown firmware set '$firmware_set'"
            echo "Valid options: compex, 8devices"
            exit 1
            ;;
    esac
    
    case $band in
        "2g"|"5g"|"both") ;;
        *)
            echo "Error: Unknown band '$band'"
            echo "Valid options: 2g, 5g, both"
            exit 1
            ;;
    esac
    
    # Get the correct PCI path
    ACTUAL_PCI=$(get_actual_pci_path)
    if [ -z "$ACTUAL_PCI" ]; then
        echo "Error: Could not detect WiFi PCI device"
        exit 1
    fi
    echo "Detected PCI path: $ACTUAL_PCI"
    
    # Set firmware directory
    case $firmware_set in
        "compex")
            FIRMWARE_DIR="$COMPEX_DIR"
            ;;
        "8devices")
            FIRMWARE_DIR="$EIGHTDEVICES_DIR"
            ;;
    esac
    
    # Check if firmware directory exists
    if [ ! -d "$FIRMWARE_DIR" ]; then
        echo "Error: Firmware directory not found: $FIRMWARE_DIR"
        exit 1
    fi
    
    # Just stop WiFi, don't touch drivers
    stop_wifi
    
    # Create band-specific firmware configuration
    echo ""
    if ! create_band_config "$firmware_set" "$band" "$ACTUAL_PCI" "$FIRMWARE_DIR"; then
        echo "Error: Failed to create firmware config"
        exit 1
    fi
    
    # Force firmware reload by restarting ath11k_pci module briefly
    echo "Forcing complete firmware reload with aggressive cleanup..."
    
    # Save current dmesg marker
    local dmesg_marker=$(dmesg | wc -l)
    echo "Current dmesg line count: $dmesg_marker"
    
    # Step 1: Disconnect from any network and bring interface down
    local wifi_iface=$(iw dev | grep Interface | awk '{print $2}' | head -1)
    if [ -n "$wifi_iface" ]; then
        echo "Disconnecting interface $wifi_iface..."
        iw dev "$wifi_iface" disconnect 2>/dev/null || true
        ip link set "$wifi_iface" down 2>/dev/null || true
    fi
    
    # Step 2: Kill all wireless processes
    killall wpa_supplicant 2>/dev/null || true
    killall hostapd 2>/dev/null || true
    
    # Step 3: Unload the entire ath11k stack
    echo "Unloading entire ath11k driver stack..."
    unload_driver_stack
    
    # Step 4: Aggressive cache clearing
    echo "Performing aggressive cache cleanup..."
    rm -rf /tmp/ath11k* 2>/dev/null || true
    rm -rf /tmp/firmware* 2>/dev/null || true
    rm -rf /tmp/qmi* 2>/dev/null || true
    
    # Clear all caches
    echo 3 > /proc/sys/vm/drop_caches
    sync
    
    # Step 5: Reset firmware loader
    echo "Resetting firmware loader..."
    echo 1 > /sys/class/firmware/timeout 2>/dev/null || true
    sleep 1
    echo 60 > /sys/class/firmware/timeout 2>/dev/null || true
    
    # Step 6: Wait for hardware to fully reset
    echo "Waiting for hardware stabilization..."
    sleep 8
    
    # Step 7: Reload the entire stack in proper order
    echo "Reloading ath11k driver stack..."
    if ! load_driver; then
        echo "Error: Failed to reload driver stack"
        exit 1
    fi
    
    # Step 8: Wait for firmware loading and monitor
    echo "Waiting for firmware loading..."
    local timeout=30
    local count=0
    local new_firmware_loaded=0
    
    while [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
        
        # Check for new dmesg entries
        local current_lines=$(dmesg | wc -l)
        if [ $current_lines -gt $dmesg_marker ]; then
            # Check for firmware loading messages
            local new_fw_msg=$(dmesg | tail -$((current_lines - dmesg_marker)) | grep -E "(firmware|ath11k.*fw_version)")
            if [ -n "$new_fw_msg" ]; then
                echo "✅ New firmware loading detected:"
                echo "$new_fw_msg"
                new_firmware_loaded=1
                break
            fi
        fi
        
        if [ $((count % 5)) -eq 0 ]; then
            echo "Waiting for firmware load... ($count/$timeout)"
        fi
    done
    
    if [ $new_firmware_loaded -eq 0 ]; then
        echo "⚠️ No new firmware loading messages detected"
        echo "Recent dmesg:"
        dmesg | tail -10
    fi
    
    # Step 9: Wait additional time for PHY initialization
    echo "Waiting for PHY initialization..."
    sleep 10
    
    # Check if PHY interface exists and wait for WiFi interface creation
    echo "Waiting for PHY and WiFi interface creation..."
    local timeout=5
    local count=0
    local phy_found=0
    local wifi_iface=""
    
    while [ $count -lt $timeout ]; do
        # Check for PHY
        EXISTING_PHY=$(ls /sys/class/ieee80211/ 2>/dev/null | head -1)
        if [ -n "$EXISTING_PHY" ] && [ $phy_found -eq 0 ]; then
            echo "✅ PHY interface found: $EXISTING_PHY"
            phy_found=1
        fi
        
        # Check for WiFi interface
        wifi_iface=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
        if [ -n "$wifi_iface" ] && [ $phy_found -eq 1 ]; then
            echo "✅ WiFi interface found: $wifi_iface"
            NEW_PHY="$EXISTING_PHY"
            break
        fi
        
        sleep 1
        count=$((count + 1))
        if [ $((count % 1)) -eq 0 ]; then
            echo "Still waiting for interface creation... ($count/$timeout)"
            if [ $phy_found -eq 0 ]; then
                echo "  - Waiting for PHY device"
            else
                echo "  - PHY found, waiting for WiFi interface"
            fi
        fi
    done
    
    if [ -z "$EXISTING_PHY" ]; then
        echo "Error: No PHY interface found after firmware reload"
        echo "Please reboot the device first"
        exit 1
    fi
    
    if [ -z "$wifi_iface" ]; then
        echo "Warning: WiFi interface not found, but PHY exists."
        echo "Attempting to manually create WiFi interface..."
        if force_wifi_interface_creation "$EXISTING_PHY"; then
            wifi_iface=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
            if [ -n "$wifi_iface" ]; then
                echo "✅ Successfully created WiFi interface: $wifi_iface"
                NEW_PHY="$EXISTING_PHY"
            else
                echo "❌ Interface creation failed"
                echo "Continuing with PHY only - verification may fail"
                NEW_PHY="$EXISTING_PHY"
            fi
        else
            echo "❌ Manual interface creation failed"
            echo "Continuing with PHY only - verification may fail"
            NEW_PHY="$EXISTING_PHY"
        fi
    fi
    
    # Configure wireless for the correct band
    echo ""
    configure_wireless_for_band "$band" "$NEW_PHY"
    
    # Verify the firmware switch was successful
    echo ""
    if ! verify_firmware_switch "$band" "$firmware_set"; then
        echo "❌ Firmware switch verification failed!"
        echo "The firmware may not have actually changed."
        exit 1
    fi
    
    # Start WiFi services
    echo ""
    start_wifi
    
    # Test connection for specific bands
    case $band in
        "2g")
            echo ""
            test_band_connection "2.4GHz" 2400 2500
            ;;
        "5g")
            echo ""
            test_band_connection "5GHz" 5000 6000
            ;;
        "both")
            echo ""
            echo "Dual-band mode configured - manual testing required"
            ;;
    esac
    
    echo ""
    echo "=== Simple firmware switch completed ==="
}

# Configure WiFi SSIDs based on MAC address
configure_ssid_from_mac() {
    local mac_addr=$1
    if [ -z "$mac_addr" ]; then
        echo "⚠️ No MAC address provided for SSID configuration"
        return 1
    fi
    
    # Remove colons from MAC address if present
    local clean_mac=$(echo "$mac_addr" | tr -d ':')
    
    echo "Configuring WiFi SSIDs with MAC: $clean_mac"
    
    # Configure 2.4GHz SSID
    uci set wireless.sta_radio0.ssid="${clean_mac}-2.4GHz"
    uci set wireless.sta_radio0.mode='sta'

    # Configure 5GHz SSID
    uci set wireless.sta_radio1.ssid="${clean_mac}-5GHz"
    uci set wireless.sta_radio1.mode='sta'

    uci commit wireless
    echo "✅ Configured SSIDs: ${clean_mac}-2.4GHz, ${clean_mac}-5GHz"
    return 0
}

# Help function
show_help() {
    cat << EOF
WiFi Firmware Switching Script v3 (Fixed)

Usage: $0 [COMMAND] [OPTIONS] [MAC_ADDRESS]

Commands:
    switch [firmware] [band] [mac]     - Switch firmware and band with MAC SSID
    switch-full [firmware] [band] [mac] - Switch with full driver reload and MAC SSID
    scan                               - Scan for available networks
    status                             - Show current WiFi status
    help                               - Show this help

Firmware options:
    compex      - Use Compex firmware
    8devices    - Use 8devices firmware

Band options:
    2g          - 2.4GHz only
    5g          - 5GHz only  
    both        - Dual-band

MAC Address (optional):
    MAC address to use for SSID naming (format: 00:d0:93:65:64:37 or 00d093656437)

Network Configuration:
    SSID: Moment (default) or [MAC]-2.4GHz/[MAC]-5GHz (if MAC provided)
    Password: 33viv42leg!
    Encryption: WPA2-PSK

Examples:
    $0 switch compex 2g                          - Switch to Compex 2.4GHz (default SSID)
    $0 switch 8devices 5g 00:d0:93:65:64:37     - Switch to 8devices 5GHz with MAC SSID
    $0 status                                    - Show current status

EOF
}

# Runtime board calibration switch
runtime_switch_board() {
    local target=$1
    case "$target" in
        2g|5g) ;;
        *) echo "Usage: $0 board-switch <2g|5g>"; return 1;;
    esac
    local phy_list=$(ls /sys/class/ieee80211/ 2>/dev/null)
    echo "[board-switch] Target calibration: $target"
    # Bring wifi down cleanly
    wifi down 2>/dev/null
    for iface in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
        iw dev "$iface" disconnect 2>/dev/null
        ip link set "$iface" down 2>/dev/null
    done
    sleep 1
    # Unload driver
    unload_driver_stack
    local src
    if [ "$target" = "2g" ]; then src="$BOARD_CAL_DIR/$BOARD_2G_FILE"; else src="$BOARD_CAL_DIR/$BOARD_5G_FILE"; fi
    if [ ! -f "$src" ]; then
        echo "❌ Missing calibration file: $src"; return 1
    fi
    if [ ! -f "$BOARD_CAL_DIR/$BOARD_ACTIVE" ]; then
        echo "⚠️ Active board file missing; creating new one from $src"
    fi
    # Backup existing active board
    if [ -f "$BOARD_CAL_DIR/$BOARD_ACTIVE" ]; then
        cp "$BOARD_CAL_DIR/$BOARD_ACTIVE" "$BOARD_CAL_DIR/$BOARD_ACTIVE.bak_$(date +%s)" 2>/dev/null || true
    fi
    cp "$src" "$BOARD_CAL_DIR/$BOARD_ACTIVE" || { echo "❌ Failed to copy $src"; return 1; }
    sync
    echo "[board-switch] Installed $src as $BOARD_ACTIVE"
    # Reload driver
    load_driver || return 1
    sleep 1
    # Verify load
    if dmesg | tail -120 | grep -q "invalid board magic"; then
        echo "❌ Board magic invalid after switch. Reverting."
        local revert=$(ls -t $BOARD_CAL_DIR/$BOARD_ACTIVE.bak_* 2>/dev/null | head -1)
        if [ -n "$revert" ]; then
            cp "$revert" "$BOARD_CAL_DIR/$BOARD_ACTIVE" && echo "Reverted to $revert"
            unload_driver_stack
            load_driver || return 1
            sleep 2
        fi
    else
        echo "✅ Board file accepted (no invalid board magic detected)"
    fi
    # Reconfigure band (UCI) to match target if requested
    local phy=$(ls /sys/class/ieee80211/ 2>/dev/null | head -1)
    [ -n "$phy" ] && configure_wireless_for_band "$target" "$phy" 2>/dev/null
    wifi up 2>/dev/null || true
    sleep 3
    local iface=$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
    if [ -n "$iface" ]; then
        iw dev "$iface" scan trigger >/dev/null 2>&1; sleep 4
        iw dev "$iface" scan dump 2>/dev/null | awk 'BEGIN{c=0}/freq:/{f=$2;if(("$target"=="2g" && f<3000) || ("$target"=="5g" && f>3000)){c++}}END{print "[board-switch] Band scan match count="c}'
    fi
    echo "[board-switch] Done"
}

# Main execution
case $1 in
    "switch")
        if [ $# -lt 3 ] || [ $# -gt 4 ]; then
            echo "Error: switch command requires firmware and band arguments, optional MAC address"
            show_help
            exit 1
        fi
        simple_firmware_switch "$2" "$3"
        if [ -n "$4" ]; then
            configure_ssid_from_mac "$4"
            wifi reload
        fi
        ;;
    "switch-full")
        if [ $# -lt 3 ] || [ $# -gt 4 ]; then
            echo "Error: switch-full command requires firmware and band arguments, optional MAC address"
            show_help
            exit 1
        fi
        switch_firmware "$2" "$3"
        if [ -n "$4" ]; then
            configure_ssid_from_mac "$4"
            wifi reload
        fi
        ;;
    "scan")
        scan_networks
        ;;
    "status")
        show_status
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    board-switch)
        runtime_switch_board "$2" || exit 1
        ;;
    *)
        if [ $# -eq 2 ]; then
            # Backward compatibility: ./script firmware band
            simple_firmware_switch "$1" "$2"
        elif [ $# -eq 3 ]; then
            # Backward compatibility with MAC: ./script firmware band mac
            simple_firmware_switch "$1" "$2"
            configure_ssid_from_mac "$3"
            wifi reload
        else
            echo "Error: Invalid command or arguments"
            show_help
            exit 1
        fi
        ;;
esac