-- RAM usage bar widget: a memory-stick (DIMM) icon whose chips double as a level meter,
-- then "NN%".
--
-- Drawn natively from ui.row/ui.column/ui.box nodes (no SVG, theme roles throughout), via
-- barWidget.render — a render tree replaces the imperative setText/setImage row. The chips
-- light left to right; the chip at the current level fills bottom-up, so 5 chips give a
-- continuous 0–100% reading. RAM comes from the shell's own monitor
-- (`noctalia.systemStats().ram`, sampled at [system.monitor].memory_poll_seconds).

local interval = noctalia.getConfig("pollIntervalMs") or 1000
local warn = noctalia.getConfig("warnThreshold") or 80
local crit = noctalia.getConfig("critThreshold") or 90

noctalia.setUpdateInterval(interval)

-- Geometry in logical px (the host applies the bar's content scale).
local CHIPS = 5
local CHIP_W, CHIP_H, CHIP_GAP = 3.2, 7, 1
local PAD, BORDER = 1.5, 1
local PCB_W = CHIPS * CHIP_W + (CHIPS - 1) * CHIP_GAP + 2 * (PAD + BORDER)
local PCB_H = CHIP_H + 2 * (PAD + BORDER)
local PIN_H, NOTCH = 2, 1.5
local PIN_LEFT = math.floor((PCB_W - 4) * 0.6 * 10 + 0.5) / 10 -- keying notch off-centre, like a real DIMM
local PIN_RIGHT = PCB_W - 4 - NOTCH - PIN_LEFT

local OUTLINE = "on_surface/0.55"
local CHIP_OFF = "on_surface/0.14"

local function fmtGb(mb)
  return string.format("%.1f GB", mb / 1024)
end

local function chip(i, level, fill)
  local f = math.clamp(level * CHIPS - (i - 1), 0, 1)
  local h = math.floor(f * CHIP_H * 10 + 0.5) / 10
  return ui.column({
    key = "chip" .. i,
    width = CHIP_W,
    height = CHIP_H,
    radius = 0.8,
    fill = CHIP_OFF,
    justify = "end",
    clip = true,
  }, {
    ui.box({ key = "lvl", width = CHIP_W, height = h, radius = 0.8, fill = fill, visible = h > 0 }),
  })
end

local function dimm(level, fill)
  local chips = {}
  for i = 1, CHIPS do
    chips[i] = chip(i, level, fill)
  end
  return ui.column({ key = "dimm", gap = 0.5, align = "center" }, {
    ui.row({
      key = "pcb",
      width = PCB_W,
      height = PCB_H,
      padding = PAD,
      gap = CHIP_GAP,
      align = "center",
      radius = 2,
      border = OUTLINE,
      borderWidth = BORDER,
    }, chips),
    -- Edge connector: two pin strips split by the keying notch.
    ui.row({ key = "pins", gap = NOTCH }, {
      ui.box({ key = "pinL", width = PIN_LEFT, height = PIN_H, radius = 0.5, fill = OUTLINE }),
      ui.box({ key = "pinR", width = PIN_RIGHT, height = PIN_H, radius = 0.5, fill = OUTLINE }),
    }),
  })
end

function update()
  local stats = noctalia.systemStats()
  local ram = stats and stats.ram
  local pct = ram and ram.usagePercent
  local total = ram and ram.totalMb

  local text, level, fill, tooltip = "—", 0, "primary", nil
  if pct and total and total > 0 then
    level = math.clamp(pct / 100, 0, 1)
    text = string.format("%d%%", math.floor(pct + 0.5))
    if pct >= crit then
      fill = "error"
    elseif pct >= warn then
      fill = "tertiary"
    end
    tooltip = string.format("RAM %s / %s (%.1f%%)", fmtGb(ram.usedMb), fmtGb(total), pct)
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center", tooltip = tooltip }, {
    dimm(level, fill),
    -- ui.label ignores `width` (it hugs its text), so a minWidth row reserves room for "100%"
    -- and the centered bar doesn't shift as the value changes.
    ui.row({ key = "pctBox", minWidth = 34, align = "center" }, {
      ui.label({ key = "pct", text = text }),
    }),
  }))
end

update()
