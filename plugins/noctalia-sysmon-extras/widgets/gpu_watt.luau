-- GPU utilization % + power (watts) bar widget ("5% · 55W"), via `nvidia-smi`.
--
-- The discrete GPU's power isn't in `sensors -j` (the nvidia driver doesn't export a
-- hwmon power channel), so query nvidia-smi directly. `power.draw` is instantaneous
-- board power in watts. For a multi-GPU box, the first reported GPU is used.

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 300
local crit = noctalia.getConfig("critThreshold") or 400
local glyph = noctalia.getConfig("glyph") or "bolt"

noctalia.setUpdateInterval(interval)
barWidget.setGlyph(glyph)

local lastText = "—"
local lastValue = nil

local cmd = "nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null"

local function refresh()
  noctalia.runAsync(cmd, function(res)
    if res.exitCode ~= 0 or res.stdout == "" then
      lastText = "n/a"
      lastValue = nil
      return
    end
    local w, util = res.stdout:match("([%d%.]+),%s*([%d%.]+)")
    w = tonumber(w)
    if not w then return end
    lastValue = w
    local watt = string.format("%dW", math.floor(w + 0.5))
    util = tonumber(util)
    lastText = util and string.format("%d%% · %s", math.floor(util + 0.5), watt) or watt
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
