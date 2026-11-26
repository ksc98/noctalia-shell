-- RAM usage bar widget: a donut ring whose arc sweeps clockwise with memory use, then "NN%".
--
-- Drawn natively with ui.ring via barWidget.render (no SVG, theme roles throughout). RAM comes
-- from the shell's own monitor (`noctalia.systemStats().ram`, sampled at
-- [system.monitor].memory_poll_seconds). The label follows the warn/crit thresholds.

local interval = noctalia.getConfig("pollIntervalMs") or 1000
local warn = noctalia.getConfig("warnThreshold") or 80
local crit = noctalia.getConfig("critThreshold") or 90

noctalia.setUpdateInterval(interval)

-- Logical px (the host applies the bar's content scale). A thick stroke reads as a pie ring.
local RING, STROKE = 14, 4
local TRACK = "on_surface/0.14"

local function fmtGb(mb)
  return string.format("%.1f GB", mb / 1024)
end

function update()
  local stats = noctalia.systemStats()
  local ram = stats and stats.ram
  local pct = ram and ram.usagePercent
  local total = ram and ram.totalMb

  local text, level, color, tooltip = "—", 0, "on_surface", nil
  if pct and total and total > 0 then
    level = math.clamp(pct / 100, 0, 1)
    text = string.format("%d%%", math.floor(pct + 0.5))
    if pct >= crit then
      color = "error"
    elseif pct >= warn then
      color = "tertiary"
    end
    tooltip = string.format("RAM %s / %s (%.1f%%)", fmtGb(ram.usedMb), fmtGb(total), pct)
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center", tooltip = tooltip }, {
    ui.ring({
      key = "ring",
      width = RING,
      height = RING,
      progress = level,
      thickness = STROKE,
      fill = "primary",
      track = TRACK,
    }),
    -- ui.label ignores `width` (it hugs its text), so a minWidth row reserves room for "100%"
    -- and the centered bar doesn't shift as the value changes.
    ui.row({ key = "pctBox", minWidth = 34, align = "center" }, {
      ui.label({ key = "pct", text = text, color = color }),
    }),
  }))
end

update()
