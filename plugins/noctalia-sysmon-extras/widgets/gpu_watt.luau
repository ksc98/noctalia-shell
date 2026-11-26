-- GPU utilization % + power (watts) bar widget ("5% · 55W"), via `nvidia-smi`.
--
-- The discrete GPU's power isn't in `sensors -j` (the nvidia driver doesn't export a
-- hwmon power channel), so query nvidia-smi directly. `power.draw` is instantaneous
-- board power in watts. For a multi-GPU box, the first reported GPU is used.
--
-- The icon is a graphics card drawn natively from ui.* nodes via barWidget.render (no
-- SVG; theme roles throughout): outlined board with a flush PCIe bracket and gold
-- fingers, and one fan that is a ui.ring gauge whose
-- `tertiary` arc sweeps clockwise with GPU utilization.
-- The "NN% · NNW" label follows the power warn/crit thresholds.

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 300
local crit = noctalia.getConfig("critThreshold") or 400

noctalia.setUpdateInterval(interval)

-- Geometry in logical px: a 12px board with a 1px outline and radius 2, and a split strip
-- of PCIe gold fingers under it.
local FAN, FAN_RING = 9, 2
local BORDER, PAD = 1, 0.5
local BODY_W, BODY_H = 19, FAN + 2 * (BORDER + PAD)
local FINGER_H, FINGER_GAP = 2, 0.5
local BRACKET_W = 1.6
local BRACKET_H = BODY_H + FINGER_GAP + FINGER_H + 1.5 -- runs past the fingers, like a real bracket

local FILL = "tertiary"
local OUTLINE = "on_surface/0.55"
local UNLIT = "on_surface/0.14"

local lastUtil = nil -- % (number)
local lastWatt = nil -- W (number)
local status = "—" -- shown while there's no reading: "—" before the first poll, "n/a" without nvidia-smi

local cmd = "nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null"

local function card(level)
  return ui.row({ key = "card", gap = 0, align = "start" }, {
    -- PCIe bracket, flush against the board's left edge.
    ui.box({ key = "bracket", width = BRACKET_W, height = BRACKET_H, radius = 0.5, fill = OUTLINE }),
    ui.column({ key = "pcb", gap = FINGER_GAP, align = "start" }, {
      ui.row({
        key = "body",
        width = BODY_W,
        height = BODY_H,
        padding = PAD,
        align = "center",
        justify = "center",
        radius = 2,
        border = OUTLINE,
        borderWidth = BORDER,
      }, {
        -- The fan is the meter: its arc sweeps clockwise with utilization.
        ui.ring({
          key = "fan",
          width = FAN,
          height = FAN,
          progress = level,
          thickness = FAN_RING,
          fill = FILL,
          track = UNLIT,
        }),
      }),
      -- Gold fingers: two strips split by the key notch.
      ui.row({ key = "fingers", paddingH = 2, gap = 1.5 }, {
        ui.box({ key = "fingerL", width = 4.5, height = FINGER_H, radius = 0.5, fill = OUTLINE }),
        ui.box({ key = "fingerR", width = 9, height = FINGER_H, radius = 0.5, fill = OUTLINE }),
      }),
    }),
  })
end

local function paint()
  local level, text, color, tooltip = 0, status, "on_surface", nil
  if lastWatt then
    local watt = string.format("%dW", math.floor(lastWatt + 0.5))
    text = lastUtil and string.format("%d%% · %s", math.floor(lastUtil + 0.5), watt) or watt
    level = lastUtil and math.clamp(lastUtil / 100, 0, 1) or 0
    if lastWatt >= crit then
      color = "error"
    elseif lastWatt >= warn then
      color = "tertiary"
    end
    tooltip = string.format("GPU %s%.1f W", lastUtil and string.format("%d%% · ", math.floor(lastUtil + 0.5)) or "", lastWatt)
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center", tooltip = tooltip }, {
    card(level),
    -- ui.label ignores `width` (it hugs its text), so a minWidth row reserves room for
    -- "99% · 450W" and keeps the centered bar from shifting as the value changes.
    ui.row({ key = "txtBox", minWidth = 68, align = "center" }, {
      ui.label({ key = "txt", text = text, color = color }),
    }),
  }))
end

local function refresh()
  noctalia.runAsync(cmd, function(res)
    if res.exitCode ~= 0 or res.stdout == "" then
      status = "n/a"
      lastWatt = nil
      lastUtil = nil
      return
    end
    local w, util = res.stdout:match("([%d%.]+),%s*([%d%.]+)")
    w = tonumber(w)
    if not w then return end
    lastWatt = w
    lastUtil = tonumber(util)
  end)
end

function update()
  paint()
  refresh()
end

paint()
refresh()
