-- GPU power (watts) bar widget, via `nvidia-smi`.
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

local cmd = "nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null"

local function refresh()
  noctalia.runAsync(cmd, function(res)
    if res.exitCode ~= 0 or res.stdout == "" then
      lastText = "n/a"
      lastValue = nil
      return
    end
    local w = tonumber(res.stdout:match("([%d%.]+)"))
    if not w then return end
    lastValue = w
    lastText = string.format("%dW", math.floor(w + 0.5))
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
