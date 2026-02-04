local json = require "luci.jsonc"

local function exec(cmd)
  local handle = io.popen(cmd .. " 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result
end

local function get_client_info(mac)
  local info = {ip = "unknown", hostname = "unknown"}

  -- Robust DHCP lease parsing
  local leases = exec("grep -i " .. mac .. " /tmp/dhcp.leases 2>/dev/null")
  if leases ~= "" then
    -- Split by whitespace/tabs
    local fields = {}
    for field in leases:gmatch("%S+") do
      table.insert(fields, field)
    end

    if #fields >= 4 then
      info.ip = fields[3]
      info.hostname = fields[4] or "unknown"
      -- Clean hostname
      info.hostname = info.hostname:gsub("[*?]", ""):gsub("%.lan$", "")
      info.hostname = info.hostname:match("^([^%s]+)") or info.hostname
    end
  end

  -- Fallbacks
  if info.ip == "unknown" then
    local arp = exec("arp -a | grep -i " .. mac .. " 2>/dev/null")
    info.ip = arp:match("%(([0-9%.]+)%)") or "unknown"
  end

  -- Final cleanup
  if info.hostname == "*" or info.hostname == "unknown" or info.hostname:match("^%x%x:") then
    info.hostname = mac:gsub(":", "-"):lower()
  end
  
  return info
end

local function scrape()
  local clients_metric = metric("node_wireless_clients", "gauge")
  local clients_authorized_metric = metric("node_wireless_client_authorized", "gauge")
  local clients_tx_metric = metric("node_wireless_client_tx_mbps", "gauge")
  local clients_rx_metric = metric("node_wireless_client_rx_mbps", "gauge")
  local clients_signal_metric = metric("node_wireless_client_signal_dbm", "gauge")
  local clients_noise_metric = metric("node_wireless_client_noise_dbm", "gauge")
  local interfaces = {}
  local handle = io.popen("iw dev | grep Interface | awk '{print $2}' 2>/dev/null")

  for line in handle:lines() do
    table.insert(interfaces, line)
  end
  handle:close()

  for _, iface in ipairs(interfaces) do
    local data = exec('ubus call iwinfo assoclist "{\\"device\\":\\"' .. iface .. '\\"}" 2>/dev/null')

    if data ~= "" and data ~= "{}" then
      local ok, assoc = pcall(json.parse, data)
      if ok and assoc and assoc.results then
        for _, client in ipairs(assoc.results) do
          if client.mac and client.mac ~= "" then
            local client_info = get_client_info(client.mac)
            local channel_width = (client.rx and client.rx.mhz) or (client.tx and client.tx.mhz) or 0

            local labels = {
              interface = iface,
              mac = client.mac,
              ip = client_info.ip,
              hostname = client_info.hostname,
              channel_width = tostring(channel_width)
            }

            clients_metric(labels, 1)
            clients_authorized_metric(labels, client.authorized == true and 1 or 0)

            if client.tx and client.tx.rate then
              clients_tx_metric(labels, math.floor(client.tx.rate / 1000))
            end
            if client.rx and client.rx.rate then
              clients_rx_metric(labels, math.floor(client.rx.rate / 1000))
            end

            if client.signal then
              clients_signal_metric(labels, client.signal)
            end
            if client.noise then
              clients_noise_metric(labels, client.noise)
            end
          end
        end
      end
    end
  end
end

return {scrape = scrape}
