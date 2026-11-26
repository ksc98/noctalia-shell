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
--
-- No icon: the widget sits right after the cpu_cores chart, which already identifies it.
-- The "NN% · NNW" label follows the power warn/crit thresholds.

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 140
local crit = noctalia.getConfig("critThreshold") or 180
local rapl = noctalia.getConfig("raplPath") or "/sys/class/powercap/intel-rapl:0"

noctalia.setUpdateInterval(interval)

local lastWatt = "—"
local lastPct = nil -- usage % (number) once /proc/stat has two samples
local lastValue = nil -- W (number)
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
      lastPct = (busy - prevBusy) / (total - prevTotal) * 100
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

local function paint()
  local text = lastPct and string.format("%d%% · %s", math.floor(lastPct + 0.5), lastWatt) or lastWatt

  local color = "on_surface"
  if lastValue then
    if lastValue >= crit then
      color = "error"
    elseif lastValue >= warn then
      color = "tertiary"
    end
  end
  local tooltip = nil
  if lastPct or lastValue then
    tooltip = string.format("CPU %s%s",
      lastPct and string.format("%.1f%%", lastPct) or "",
      lastValue and string.format("%s%.1f W package", lastPct and " · " or "", lastValue) or "")
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ align = "center", tooltip = tooltip }, {
    -- ui.label ignores `width` (it hugs its text), so a minWidth row reserves room for
    -- "99% · 99W" and keeps the centered bar from shifting as the value changes.
    ui.row({ key = "txtBox", minWidth = 64, align = "center" }, {
      ui.label({ key = "txt", text = text, color = color }),
    }),
  }))
end

function update()
  paint()
  refreshStat()
  refreshWatt()
end

paint()
refreshStat()
refreshWatt()
