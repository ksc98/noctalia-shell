-- RAM usage bar widget: a donut chart of where memory goes, then "NN%".
--
-- Drawn natively with a segmented ui.ring via barWidget.render (no SVG, theme roles
-- throughout). Clockwise from 12 o'clock:
--   apps     AnonPages + Shmem (process memory and tmpfs/shared memory)     primary
--   kernel   the rest of used: slab, page tables, stacks, driver and zram    secondary
--   cache    MemAvailable - MemFree (page cache the kernel can reclaim)      dim
--   free     MemFree, left as the bare track
-- Every number comes from one /proc/meminfo read, so the slices always sum to the total and
-- apps + kernel equals the shell's own used figure (MemTotal - MemAvailable) behind "NN%".
-- The label follows the warn/crit thresholds; the tooltip is the legend (a colour dot per slice) plus swap.

local interval = noctalia.getConfig("pollIntervalMs") or 1000
local warn = noctalia.getConfig("warnThreshold") or 80
local crit = noctalia.getConfig("critThreshold") or 90

noctalia.setUpdateInterval(interval)

-- Logical px (the host applies the bar's content scale).
local RING, STROKE = 18, 3.5
local APPS, KERNEL, CACHE = "primary", "secondary", "on_surface/0.38"
local TRACK = "on_surface/0.14"

local function fmtKb(kb)
  local gb = kb / 1048576
  if gb >= 1 then
    return string.format("%.1f GB", gb)
  end
  return string.format("%d MB", math.floor(kb / 1024 + 0.5))
end

local function parse(data)
  local m = {}
  for key, kb in data:gmatch("([%w_()]+):%s+(%d+)") do
    m[key] = tonumber(kb)
  end
  return m
end

local function render(slices, pct)
  local text, color = "—", "on_surface"
  if pct then
    text = string.format("%d%%", math.floor(pct + 0.5))
    if pct >= crit then
      color = "error"
    elseif pct >= warn then
      color = "tertiary"
    end
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center" }, {
    ui.ring({
      key = "ring",
      width = RING,
      height = RING,
      thickness = STROKE,
      track = TRACK,
      segments = slices,
      segmentFills = { APPS, KERNEL, CACHE },
    }),
    -- ui.label ignores `width` (it hugs its text), so a minWidth row reserves room for "100%"
    -- and the centered bar doesn't shift as the value changes.
    ui.row({ key = "pctBox", minWidth = 34, align = "center" }, {
      ui.label({ key = "pct", text = text, color = color }),
    }),
  }))
end

local function refresh()
  noctalia.readFileAsync("/proc/meminfo", function(data)
    local m = data and parse(data)
    local total, avail, free = m and m.MemTotal, m and m.MemAvailable, m and m.MemFree
    if not (total and avail and free) or total <= 0 or avail > total then
      render({ 0, 0, 0 }, nil)
      barWidget.setTooltip(nil)
      return
    end

    local used = total - avail
    local apps = math.min((m.AnonPages or 0) + (m.Shmem or 0), used)
    local kernel = used - apps
    local cache = math.max(avail - free, 0)
    render({ apps / total, kernel / total, cache / total }, 100 * used / total)

    local rows = {
      { "Used", string.format("%s / %s (%.1f%%)", fmtKb(used), fmtKb(total), 100 * used / total) },
      -- swatch = the slice's colour, so the tooltip doubles as the ring's legend.
      { key = "Apps", value = fmtKb(apps), swatch = APPS },
      { key = "Kernel & drivers", value = fmtKb(kernel), swatch = KERNEL },
      { key = "Cache", value = fmtKb(cache), swatch = CACHE },
      { key = "Free", value = fmtKb(free), swatch = TRACK },
    }
    if (m.Shmem or 0) > 0 then
      table.insert(rows, 3, { "  of which shared", fmtKb(m.Shmem) })
    end
    local swapTotal = m.SwapTotal or 0
    if swapTotal > 0 then
      table.insert(rows, { "Swap", string.format("%s / %s", fmtKb(swapTotal - (m.SwapFree or 0)), fmtKb(swapTotal)) })
    end
    barWidget.setTooltip(rows)
  end)
end

function update()
  refresh()
end

render({ 0, 0, 0 }, nil)
refresh()
