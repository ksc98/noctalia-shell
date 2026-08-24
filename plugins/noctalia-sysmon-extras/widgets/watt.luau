-- CPU power (watts) bar widget.
-- Ports the v4 SystemMonitor watt readout via `sensors -j`, keyed by
-- <chip>/<label>/<valueKey> (shared reader: sensors_json.luau). Same
-- cache-and-paint pattern as coolant.luau.

local sensors = require("./widgets/sensors_json.luau")

local chip = noctalia.getConfig("cpuWattSensorChip") or ""
local label = noctalia.getConfig("cpuWattSensorLabel") or ""
local valueKey = noctalia.getConfig("cpuWattSensorValueKey") or ""
local warn = noctalia.getConfig("warnThreshold") or 100
local crit = noctalia.getConfig("critThreshold") or 150
local interval = noctalia.getConfig("pollIntervalMs") or 2000
local glyph = noctalia.getConfig("glyph") or "bolt"

noctalia.setUpdateInterval(interval)
barWidget.setGlyph(glyph)
barWidget.setGlyphColor("tertiary")

local lastText = "—"
local lastValue = nil

local function refresh()
  if chip == "" or label == "" or valueKey == "" then
    lastText = "cfg?"
    return
  end
  sensors.read(chip, label, valueKey, function(v)
    if not v then return end
    lastValue = v
    lastText = string.format("%dW", math.floor(v + 0.5))
    barWidget.setText(lastText)
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
