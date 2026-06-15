-- CPU power (watts) bar widget.
-- Ports the v4 SystemMonitor watt readout via `sensors -j`, keyed by
-- <chip>/<label>/<valueKey>. Same cache-and-paint pattern as coolant.luau.

local chip = noctalia.getConfig("cpuWattSensorChip") or ""
local label = noctalia.getConfig("cpuWattSensorLabel") or ""
local valueKey = noctalia.getConfig("cpuWattSensorValueKey") or ""
local warn = noctalia.getConfig("warnThreshold") or 100
local crit = noctalia.getConfig("critThreshold") or 150
local interval = noctalia.getConfig("pollIntervalMs") or 2000

noctalia.setUpdateInterval(interval)
barWidget.setGlyph("bolt")

local lastText = "—"
local lastValue = nil

-- See coolant.luau: match configured chip as exact key, then as a prefix, since
-- lm-sensors appends a bus suffix to the chip name.
local function findChip(data, name)
  if type(data[name]) == "table" then return data[name] end
  for k, v in pairs(data) do
    if type(k) == "string" and type(v) == "table" and k:sub(1, #name) == name then
      return v
    end
  end
  return nil
end

local function refresh()
  if chip == "" or label == "" or valueKey == "" then
    lastText = "cfg?"
    return
  end
  noctalia.runAsync("sensors -j 2>/dev/null", function(res)
    if res.exitCode ~= 0 or res.stdout == "" then return end
    local ok, data = pcall(noctalia.json.decode, res.stdout)
    if not ok or type(data) ~= "table" then return end
    local c = findChip(data, chip); if type(c) ~= "table" then return end
    local l = c[label]; if type(l) ~= "table" then return end
    local v = l[valueKey]; if type(v) ~= "number" then return end
    lastValue = v
    lastText = string.format("%dW", math.floor(v + 0.5))
  end)
end

function update()
  barWidget.setText(lastText)
  if lastValue then
    if lastValue >= crit then
      barWidget.setColor("error")
    elseif lastValue >= warn then
      barWidget.setColor("tertiary")
    else
      barWidget.setColor("on_surface")
    end
  end
  refresh()
end

refresh()
