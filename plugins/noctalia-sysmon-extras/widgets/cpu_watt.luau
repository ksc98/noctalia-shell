-- CPU package power (watts) bar widget, via the RAPL energy counter.
--
-- AMD Zen exposes no power reading in `sensors -j` (k10temp is temps only), so we
-- read the powercap energy counter and differentiate it: W = ΔµJ / Δs. The counter
-- wraps at max_energy_range_uj, so a negative delta is corrected by adding the range.
--
-- `energy_uj` is root-only by default (the Platypus side-channel mitigation); a udev
-- rule makes it user-readable — see the plugin README / project CLAUDE.md. We clock
-- with /proc/uptime (monotonic, and small enough to stay exact in a Lua double, unlike
-- ns-since-epoch which overflows 2^53).

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 140
local crit = noctalia.getConfig("critThreshold") or 180
local rapl = noctalia.getConfig("raplPath") or "/sys/class/powercap/intel-rapl:0"
local glyph = noctalia.getConfig("glyph") or "cpu"

noctalia.setUpdateInterval(interval)
barWidget.setGlyph(glyph)

local lastText = "—"
local lastValue = nil
local prevE = nil -- µJ
local prevU = nil -- s (uptime)

-- One shell read, atomic-ish: energy | wrap-range | monotonic uptime seconds.
local cmd = string.format(
  "printf '%%s|%%s|%%s\\n' \"$(cat %s/energy_uj 2>/dev/null)\" \"$(cat %s/max_energy_range_uj 2>/dev/null)\" \"$(cut -d' ' -f1 /proc/uptime)\"",
  rapl, rapl)

local function refresh()
  noctalia.runAsync(cmd, function(res)
    if res.exitCode ~= 0 or res.stdout == "" then return end
    local e, rng, u = res.stdout:match("(%d*)|(%d*)|([%d%.]+)")
    if not u then return end
    if e == "" then -- energy_uj unreadable: udev rule not applied yet
      lastText = "perm?"
      lastValue = nil
      return
    end
    e = tonumber(e); rng = tonumber(rng); u = tonumber(u)
    if prevE and prevU then
      local de = e - prevE
      if de < 0 and rng then de = de + rng end -- counter wraparound
      local dt = u - prevU
      if dt > 0 then
        lastValue = (de / 1e6) / dt
        lastText = string.format("%dW", math.floor(lastValue + 0.5))
      end
    end
    prevE = e; prevU = u
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
