-- CPU usage % + package power (watts) bar widget ("3% · 40W"), via /proc/stat
-- and the RAPL energy counter.
--
-- AMD Zen exposes no power reading in `sensors -j` (k10temp is temps only), so we
-- read the powercap energy counter and differentiate it: W = ΔµJ / Δs. The counter
-- wraps at max_energy_range_uj, so a negative delta is corrected by adding the range.
--
-- `energy_uj` is root-only by default (the Platypus side-channel mitigation); a udev
-- rule makes it user-readable — see the plugin README / project CLAUDE.md. We clock
-- with /proc/uptime (monotonic, and small enough to stay exact in a Lua double, unlike
-- ns-since-epoch which overflows 2^53).
--
-- All reads go through noctalia.readFileAsync (plugin_api 23) — no shell spawns.
-- energy_uj chains into /proc/uptime so each ΔµJ pairs with its own Δs.

local themeIcon = require("./widgets/theme_icon.luau")

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 140
local crit = noctalia.getConfig("critThreshold") or 180
local rapl = noctalia.getConfig("raplPath") or "/sys/class/powercap/intel-rapl:0"

noctalia.setUpdateInterval(interval)
barWidget.setTextMinWidth(64) -- fits "99% · 99W"; keeps the centered bar from shifting

-- Original CPU-chip SVG (die + pins), drawn larger than the 16px font glyphs allow.
local refreshIcon = themeIcon.make({
  file = "noctalia-sysmon-cpu.svg",
  colorKey = "mSecondary",
  fallback = "#bb9af7",
  viewW = 20,
  viewH = 20,
  width = 18,
  height = 18,
  pathData = table.concat({
    "M3.5,3.5 H16.5 V16.5 H3.5 Z", -- package
    "M6.8,6.8 H13.2 V13.2 H6.8 Z", -- die outline (punched)
    "M8.6,8.6 H11.4 V11.4 H8.6 Z", -- die center (filled back)
    "M5.2,1 H6.8 V3.5 H5.2 Z", -- pins: top
    "M9.2,1 H10.8 V3.5 H9.2 Z",
    "M13.2,1 H14.8 V3.5 H13.2 Z",
    "M5.2,16.5 H6.8 V19 H5.2 Z", -- bottom
    "M9.2,16.5 H10.8 V19 H9.2 Z",
    "M13.2,16.5 H14.8 V19 H13.2 Z",
    "M1,5.2 H3.5 V6.8 H1 Z", -- left
    "M1,9.2 H3.5 V10.8 H1 Z",
    "M1,13.2 H3.5 V14.8 H1 Z",
    "M16.5,5.2 H19 V6.8 H16.5 Z", -- right
    "M16.5,9.2 H19 V10.8 H16.5 Z",
    "M16.5,13.2 H19 V14.8 H16.5 Z",
  }, " "),
})

local lastWatt = "—"
local lastPct = nil -- "3%" once /proc/stat has two samples
local lastValue = nil
local range = nil -- max_energy_range_uj (constant; read once, retried until it lands)
local prevE = nil -- µJ
local prevU = nil -- s (uptime)
local prevBusy = nil -- /proc/stat jiffies
local prevTotal = nil

local function loadRange()
  noctalia.readFileAsync(rapl .. "/max_energy_range_uj", function(data)
    range = data and tonumber(data:match("%d+")) or nil
  end)
end

local function refreshStat()
  noctalia.readFileAsync("/proc/stat", function(data)
    if not data then return end
    -- Aggregate usage %: busy/total jiffy deltas from the "cpu " line
    -- (user nice system idle iowait irq softirq steal ...).
    local line = data:match("^cpu%s[^\n]*")
    if not line then return end
    local f = {}
    for n in line:gmatch("%d+") do f[#f + 1] = tonumber(n) end
    if #f < 8 then return end
    local busy = f[1] + f[2] + f[3] + f[6] + f[7] + f[8]
    local total = busy + f[4] + f[5]
    if prevBusy and total > prevTotal then
      local pct = (busy - prevBusy) / (total - prevTotal) * 100
      lastPct = string.format("%d%%", math.floor(pct + 0.5))
    end
    prevBusy = busy; prevTotal = total
  end)
end

local function refreshWatt()
  if not range then loadRange() end
  noctalia.readFileAsync(rapl .. "/energy_uj", function(edata)
    if not edata then -- unreadable: udev rule not applied yet
      lastWatt = "perm?"
      lastValue = nil
      return
    end
    local e = tonumber(edata:match("%d+"))
    if not e then return end
    noctalia.readFileAsync("/proc/uptime", function(udata)
      if not udata then return end
      local u = tonumber(udata:match("[%d%.]+"))
      if not u then return end
      if prevE and prevU then
        local de = e - prevE
        if de < 0 and range then de = de + range end -- counter wraparound
        local dt = u - prevU
        if dt > 0 then
          lastValue = (de / 1e6) / dt
          lastWatt = string.format("%dW", math.floor(lastValue + 0.5))
        end
      end
      prevE = e; prevU = u
    end)
  end)
end

function update()
  refreshIcon()
  barWidget.setText(lastPct and (lastPct .. " · " .. lastWatt) or lastWatt)
  if lastValue then
    if lastValue >= crit then
      barWidget.setColor("error")
    elseif lastValue >= warn then
      barWidget.setColor("tertiary")
    else
      barWidget.setColor("on_surface")
    end
  end
  refreshStat()
  refreshWatt()
end

refreshIcon()
refreshStat()
refreshWatt()
