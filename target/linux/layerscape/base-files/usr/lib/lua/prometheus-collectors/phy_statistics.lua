local pattern_device = "^%s*([^%s:]+):"

-- Get list of network devices
local function get_devices()
    local devices = {}
    for line in io.lines("/proc/net/dev") do
        local dev = string.match(line, pattern_device)
        if dev then
            table.insert(devices, dev)
        end
    end
    return devices
end

-- Parse PHY statistics for a given interface
local function get_phy_stats(interface)
    local stats = {}
    local handle = io.popen("ethtool --phy-statistics " .. interface .. " 2>/dev/null")

    if not handle then
        return nil
    end

    local output = handle:read("*a")
    handle:close()

    -- Skip interfaces without PHY statistics
    if output:match("no stats available") or output == "" then
        return nil
    end

    -- Parse all PHY statistics
    for line in output:gmatch("[^\r\n]+") do
        -- Match "key: value" pattern (handles both single and multi-word keys)
        local key, value = line:match("^%s*([^:]+):%s*(%d+)")
        if key and value then
            -- Sanitize key: replace spaces/special chars with underscores, lowercase
            local clean_key = key:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""):lower()

            -- Remove leading "phy_" prefix if present (it's redundant with metric prefix)
            if clean_key:sub(1, 4) == "phy_" then
                clean_key = clean_key:sub(5)
            end

            stats[clean_key] = tonumber(value)
        end
    end

    return stats
end

-- Check if value is valid (not error indicator)
local function is_valid_value(value)
    if not value or type(value) ~= "number" then
        return false
    end

    -- Filter out UINT64_MAX variants (error indicators like 18446744073709551613)
    if value > 10000000000 then
        return false
    end

    return true
end

-- Check if interface has SFP module inserted (VCC > 0 indicates module present)
local function has_sfp_module(stats)
    return stats.vcc and stats.vcc > 0
end

local function scrape()
    local metrics = {}

    -- Iterate through all network devices
    for _, iface in ipairs(get_devices()) do
        local stats = get_phy_stats(iface)

        if stats then
            -- Only export metrics if SFP module is present (VCC > 0)
            if has_sfp_module(stats) then
                for stat_name, stat_value in pairs(stats) do
                    -- Only export valid values
                    if is_valid_value(stat_value) then
                        local metric_name = "node_phy_" .. stat_name

                        -- Create metric if not exists
                        if not metrics[metric_name] then
                            metrics[metric_name] = metric(metric_name, "gauge")
                        end

                        -- Export metric with device label
                        metrics[metric_name]({device = iface}, math.floor(stat_value + 0.5))
                    end
                end
            end
        end
    end
end

return {scrape = scrape}
