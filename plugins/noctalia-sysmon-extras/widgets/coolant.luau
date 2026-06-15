-- Coolant temperature bar widget.
-- Ports the v4 SystemMonitor coolant readout: reads `sensors -j` and extracts
-- <chip>/<label>/<valueKey>, exactly the three knobs the v4 widget exposed.
--
-- Pattern: sensors is an external command, so the read is async. We cache the
-- last good value and paint it on every update() tick (which always flushes a
-- patch), so the bar stays populated between polls regardless of async timing.

local chip = noctalia.getConfig("coolantSensorChip") or ""
local label = noctalia.getConfig("coolantSensorLabel") or ""
local valueKey = noctalia.getConfig("coolantSensorValueKey") or ""
local warn = noctalia.getConfig("warnThreshold") or 45
local crit = noctalia.getConfig("critThreshold") or 55
local interval = noctalia.getConfig("pollIntervalMs") or 2000

noctalia.setUpdateInterval(interval)
barWidget.setGlyph("droplet")

local lastText = "—"
local lastValue = nil

-- lm-sensors appends a bus suffix to chip names (e.g. "quadro-hid-3" -> the JSON
-- key is "quadro-hid-3-d"), so match the configured chip as an exact key first,
-- then as a prefix.
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
    lastText = string.format("%d°C", math.floor(v + 0.5))
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
