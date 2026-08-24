-- Coolant temperature bar widget.
-- Ports the v4 SystemMonitor coolant readout, keyed by <chip>/<label>/<valueKey>.
--
-- Fast path: the configured chip usually maps to a hwmon device, and reading the
-- single sysfs attribute (<hwmon>/<valueKey>, millidegrees) takes ~0.4s on the
-- QUADRO. Fallback: the generic `sensors -j` reader (sensors_json.luau) — a full
-- lm-sensors scan takes ~6.5s on this box because the QUADRO answers each HID
-- sensor report slowly, which is why the fast path exists.
--
-- Values paint straight from the callback (widget patches flush after every script
-- call), so the readout appears as soon as the first read lands instead of waiting
-- for the next update() tick.

local sensors = require("./widgets/sensors_json.luau")

local chip = noctalia.getConfig("coolantSensorChip") or ""
local label = noctalia.getConfig("coolantSensorLabel") or ""
local valueKey = noctalia.getConfig("coolantSensorValueKey") or ""
local warn = noctalia.getConfig("warnThreshold") or 45
local crit = noctalia.getConfig("critThreshold") or 55
local interval = noctalia.getConfig("pollIntervalMs") or 2000

noctalia.setUpdateInterval(interval)
barWidget.setGlyph("droplet")
barWidget.setGlyphColor("primary")

local lastText = "—"
local lastValue = nil
local hwmonFile = nil -- "<hwmon dir>/<valueKey>" once the chip resolves to a hwmon device
local sensorsBusy = false

local function applyColor()
  if lastValue then
    if lastValue >= crit then
      barWidget.setColor("error")
    elseif lastValue >= warn then
      barWidget.setColor("tertiary")
    else
      barWidget.setColor("on_surface")
    end
  end
end

local function paint(v)
  lastValue = v
  lastText = string.format("%.2f°C", v)
  barWidget.setText(lastText)
  applyColor()
end

-- The chip token carries a bus suffix ("quadro-hid-3") while the hwmon name is the
-- bare chip ("quadro"), so probe each hwmon whose name prefixes the configured chip.
-- Probes are chained one at a time: the host caps concurrent async reads at 4.
local function probeHwmon(dirs, i)
  if hwmonFile or i > #dirs then return end
  local base = "/sys/class/hwmon/" .. dirs[i]
  noctalia.readFileAsync(base .. "/name", function(data)
    local name = data and data:match("%S+") or nil
    if name and chip:sub(1, #name) == name then
      hwmonFile = base .. "/" .. valueKey
      return
    end
    probeHwmon(dirs, i + 1)
  end)
end

local function resolveHwmon()
  if chip == "" or valueKey == "" then return end
  local dirs = noctalia.listDir("/sys/class/hwmon")
  if type(dirs) == "table" then probeHwmon(dirs, 1) end
end

local function refresh()
  if chip == "" or label == "" or valueKey == "" then
    lastText = "cfg?"
    return
  end
  if hwmonFile then
    noctalia.readFileAsync(hwmonFile, function(data)
      local v = data and tonumber(data:match("-?%d+")) or nil
      if v then
        paint(v / 1000)
      else -- device re-enumerated: re-resolve, sensors fallback covers meanwhile
        hwmonFile = nil
        resolveHwmon()
      end
    end)
  elseif not sensorsBusy then -- scans outlive the poll interval; never stack them
    sensorsBusy = true
    sensors.read(chip, label, valueKey, function(v)
      sensorsBusy = false
      if v then paint(v) end
    end)
  end
end

function update()
  barWidget.setText(lastText)
  applyColor()
  refresh()
end

resolveHwmon()
refresh()
