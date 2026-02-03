local function rtrim(s)
  return string.gsub(s, "\n$", "")
end

-- Read a single sysfs file
local function read_sysfs_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end

  local content = f:read("*line")
  f:close()

  return content
end

-- Get list of hwmon devices
local function get_hwmon_devices()
  local devices = {}
  local handle = io.popen("ls -d /sys/class/hwmon/hwmon* 2>/dev/null")

  if not handle then
    return devices
  end

  for line in handle:lines() do
    table.insert(devices, line)
  end
  handle:close()

  return devices
end

-- Get chip identifier (similar to hwmon.lua)
local function get_chip_info(hwmon_path)
  local chip_name = read_sysfs_file(hwmon_path .. "/name")
  if not chip_name then
    chip_name = hwmon_path:match("hwmon(%d+)$") or "unknown"
  else
    chip_name = rtrim(chip_name)
  end

  -- Try to get device path info
  local device_path = hwmon_path .. "/device"
  local real_path = io.popen("readlink -f " .. device_path .. " 2>/dev/null"):read("*line")

  local chip = chip_name
  if real_path then
    local dev_name = real_path:match("([^/]+)$")
    local dev_type = real_path:match("/([^/]+)/[^/]+$")
    if dev_name and dev_type then
      chip = dev_type .. "_" .. dev_name
    end
  end

  return chip, chip_name
end

-- Check if device has ADC channels
local function has_adc_channels(hwmon_path)
  local input_file = hwmon_path .. "/in0_input"
  local f = io.open(input_file, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function scrape()
  local voltage_metric = metric("node_adc_voltage_millivolts", "gauge")

  for _, hwmon_path in ipairs(get_hwmon_devices()) do
    -- Only process devices with ADC channels
    if has_adc_channels(hwmon_path) then
      local chip, chip_name = get_chip_info(hwmon_path)
      local label = read_sysfs_file(hwmon_path .. "/label")
      if label then
        label = rtrim(label)
      end

      -- Scan for in0_input through in31_input
      for i = 0, 31 do
        local input_file = hwmon_path .. "/in" .. i .. "_input"
        local value_str

        if label == "db-sensor-adc" and i == 6 then
          -- Channel 6 uses adcen-edlc
          os.execute('echo 1 > /sys/class/leds/adcen-edlc/brightness')
          value_str = read_sysfs_file(input_file)
          os.execute('echo 0 > /sys/class/leds/adcen-edlc/brightness')

        elseif label == "db-sensor-adc" and i == 7 then
          -- Channel 7 uses adcen-bat
          os.execute('echo 1 > /sys/class/leds/adcen-bat/brightness')
          value_str = read_sysfs_file(input_file)
          os.execute('echo 0 > /sys/class/leds/adcen-bat/brightness')

        else
          -- All other channels/devices
          value_str = read_sysfs_file(input_file)
        end

        if value_str then
          local millivolts = tonumber(value_str)
          if millivolts then
            local labels = {
              chip = chip,
              chip_name = chip_name,
              channel = tostring(i)
            }

            -- Add label if available from DTS
            if label and label ~= "" then
              labels.label = label
            end

            -- Get channel-specific label if available
            local channel_label = read_sysfs_file(hwmon_path .. "/in" .. i .. "_label")
            if channel_label then
              labels.input = rtrim(channel_label)
            end

            voltage_metric(labels, millivolts)
          end
        end
      end
    end
  end
end

return {scrape = scrape}
