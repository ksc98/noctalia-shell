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

local interval = noctalia.getConfig("pollIntervalMs") or 2000
local warn = noctalia.getConfig("warnThreshold") or 140
local crit = noctalia.getConfig("critThreshold") or 180
local rapl = noctalia.getConfig("raplPath") or "/sys/class/powercap/intel-rapl:0"
local glyph = noctalia.getConfig("glyph") or "cpu"

noctalia.setUpdateInterval(interval)
barWidget.setGlyph(glyph)

local lastWatt = "—"
local lastPct = nil -- "3%" once /proc/stat has two samples
local lastValue = nil
local prevE = nil -- µJ
local prevU = nil -- s (uptime)
local prevBusy = nil -- /proc/stat jiffies
local prevTotal = nil

-- One shell read, atomic-ish: energy | wrap-range | monotonic uptime seconds | cpu stat line.
local cmd = string.format(
  "printf '%%s|%%s|%%s|%%s\\n' \"$(cat %s/energy_uj 2>/dev/null)\" \"$(cat %s/max_energy_range_uj 2>/dev/null)\" \"$(cut -d' ' -f1 /proc/uptime)\" \"$(head -1 /proc/stat)\"",
  rapl, rapl)

local function refresh()
  noctalia.runAsync(cmd, function(res)
    if res.exitCode ~= 0 or res.stdout == "" then return end
    local e, rng, u, stat = res.stdout:match("(%d*)|(%d*)|([%d%.]+)|(.*)")
    if not u then return end

    -- Aggregate usage %: busy/total jiffy deltas from the "cpu " line
    -- (user nice system idle iowait irq softirq steal ...).
    if stat then
      local f = {}
      for n in stat:gmatch("%d+") do table.insert(f, tonumber(n)) end
      if #f >= 8 then
        local busy = f[1] + f[2] + f[3] + f[6] + f[7] + f[8]
        local total = busy + f[4] + f[5]
        if prevBusy and total > prevTotal then
          local pct = (busy - prevBusy) / (total - prevTotal) * 100
          lastPct = string.format("%d%%", math.floor(pct + 0.5))
        end
        prevBusy = busy; prevTotal = total
      end
    end

    if e == "" then -- energy_uj unreadable: udev rule not applied yet
      lastWatt = "perm?"
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
        lastWatt = string.format("%dW", math.floor(lastValue + 0.5))
      end
    end
    prevE = e; prevU = u
  end)
end

function update()
  barWidget.setText(lastPct and (lastPct .. " · " .. lastWatt) or lastWatt)
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
