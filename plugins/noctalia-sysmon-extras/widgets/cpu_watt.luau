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
-- The icon is a CPU package drawn natively from ui.* nodes via barWidget.render (no SVG;
-- theme roles throughout), in the RAM DIMM's visual language: an outlined package with
-- stubby side pins around a 3x3 grid of cells that light in `secondary` as a usage meter.
-- The "NN% · NNW" label follows the power warn/crit thresholds.

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 140
local crit = noctalia.getConfig("critThreshold") or 180
local rapl = noctalia.getConfig("raplPath") or "/sys/class/powercap/intel-rapl:0"

noctalia.setUpdateInterval(interval)

-- Geometry in logical px, matching ram.luau's DIMM (1px outline, radius 2, 1.5 padding).
-- The die is a 3x3 grid of cells that light like the DIMM's chips: bottom row first,
-- left to right, the current cell filling bottom-up, so each cell is ~11% and even a
-- few % of load shows as a sliver in the first cell.
local GRID, CELL, CELL_GAP = 3, 3, 1
local PAD, BORDER = 1.5, 1
local INNER = GRID * CELL + (GRID - 1) * CELL_GAP
local PKG = INNER + 2 * (PAD + BORDER)
local PIN_LEN, PIN_W = 2, 2 -- stubby DIP-style pins on the left/right edges, one per cell row

local FILL = "secondary"
local OUTLINE = "on_surface/0.55"
local UNLIT = "on_surface/0.14"

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

local function cell(i, level)
  local f = math.clamp(level * GRID * GRID - (i - 1), 0, 1)
  local h = math.floor(f * CELL * 10 + 0.5) / 10
  return ui.column({
    key = "cell" .. i,
    width = CELL,
    height = CELL,
    radius = 0.6,
    fill = UNLIT,
    justify = "end",
    clip = true,
  }, {
    ui.box({ key = "lvl", width = CELL, height = h, radius = 0.6, fill = FILL, visible = h > 0 }),
  })
end

local function pins(key)
  local boxes = {}
  for r = 1, GRID do
    boxes[r] = ui.box({ key = key .. r, width = PIN_LEN, height = PIN_W, fill = OUTLINE })
  end
  return ui.column({ key = key, gap = CELL + CELL_GAP - PIN_W }, boxes)
end

local function chip(level)
  local rows = {}
  for r = GRID, 1, -1 do -- top row first in layout; row 1 (bottom) lights first
    local cells = {}
    for c = 1, GRID do
      cells[c] = cell((r - 1) * GRID + c, level)
    end
    rows[#rows + 1] = ui.row({ key = "row" .. r, gap = CELL_GAP }, cells)
  end
  return ui.row({ key = "chip", gap = 0, align = "center" }, {
    pins("pinL"),
    ui.column({
      key = "pkg",
      width = PKG,
      height = PKG,
      padding = PAD,
      gap = CELL_GAP,
      align = "center",
      justify = "center",
      radius = 2,
      border = OUTLINE,
      borderWidth = BORDER,
    }, rows),
    pins("pinR"),
  })
end

local function paint()
  local text = lastPct and string.format("%d%% · %s", math.floor(lastPct + 0.5), lastWatt) or lastWatt
  local level = lastPct and math.clamp(lastPct / 100, 0, 1) or 0

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
  barWidget.render(container({ gap = 5, align = "center", tooltip = tooltip }, {
    chip(level),
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
