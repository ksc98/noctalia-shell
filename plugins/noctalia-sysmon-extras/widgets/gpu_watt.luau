-- GPU utilization % + power (watts) bar widget ("5% · 55W"), via `nvidia-smi`.
--
-- The discrete GPU's power isn't in `sensors -j` (the nvidia driver doesn't export a
-- hwmon power channel), so query nvidia-smi directly. `power.draw` is instantaneous
-- board power in watts. For a multi-GPU box, the first reported GPU is used.
--
-- The icon is an original graphics-card SVG (the shipped Tabler set has no GPU icon):
-- PCIe bracket, card body with gold fingers, two fans punched out via evenodd with
-- hubs filled back in. Theme-tinted via theme_icon.luau.

local themeIcon = require("./widgets/theme_icon.luau")

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 300
local crit = noctalia.getConfig("critThreshold") or 400

noctalia.setUpdateInterval(interval)
barWidget.setTextMinWidth(68) -- fits "99% · 450W"; keeps the centered bar from shifting

local refreshIcon = themeIcon.make({
  file = "noctalia-sysmon-gpu.svg",
  colorKey = "mTertiary",
  fallback = "#9ece6a",
  viewW = 24,
  viewH = 20,
  width = 22,
  height = 18,
  pathData = table.concat({
    "M1,2 H3 V18 H1 Z", -- PCIe bracket
    "M4,5 H23 V15 H4 Z", -- card body
    "M6,15 H11 V17 H6 Z", -- gold fingers
    "M13,15 H19 V17 H13 Z",
    "M6.3,10 a3.2,3.2 0 1 0 6.4,0 a3.2,3.2 0 1 0 -6.4,0 Z", -- fan cutouts
    "M14.3,10 a3.2,3.2 0 1 0 6.4,0 a3.2,3.2 0 1 0 -6.4,0 Z",
    "M8.4,10 a1.1,1.1 0 1 0 2.2,0 a1.1,1.1 0 1 0 -2.2,0 Z", -- fan hubs
    "M16.4,10 a1.1,1.1 0 1 0 2.2,0 a1.1,1.1 0 1 0 -2.2,0 Z",
  }, " "),
})

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
    barWidget.setText(lastText)
  end)
end

function update()
  refreshIcon()
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

refreshIcon()
refresh()
