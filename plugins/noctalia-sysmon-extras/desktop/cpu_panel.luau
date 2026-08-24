-- Desktop panel: per-core CPU bars + a CPU/RAM history graph.
-- This is the closest v5 equivalent to v4's per-core stacked chart with the RAM
-- overlay. Bar widgets can't draw; desktop widgets can, via the `ui.*` tree
-- (ui.graph is available here). Per-core load -> a column of ui.progress bars;
-- CPU and RAM history -> ui.graph values / values2 (the RAM overlay).
--
-- Graph series are normalised to 0..1 to match ui.progress's domain.

local interval = noctalia.getConfig("pollIntervalMs") or 1000
local HIST = noctalia.getConfig("historySamples") or 60

noctalia.setUpdateInterval(interval)

local prevCores = nil     -- per-core { total, idle }
local prevTotal = nil     -- aggregate { total, idle }
local cpuHist = {}        -- aggregate CPU load, 0..1
local ramHist = {}        -- RAM used fraction, 0..1

local function pushCapped(t, v)
  t[#t + 1] = v
  while #t > HIST do table.remove(t, 1) end
end

-- Reads /proc/stat: returns (perCore table idx->{total,idle}, aggregate {total,idle}).
local function readCpu()
  local txt = noctalia.readFile("/proc/stat")
  if not txt or txt == "" then return nil, nil end
  local cores, agg = {}, nil
  for line in txt:gmatch("[^\n]+") do
    local tag = line:match("^(cpu%d*)%s")
    if tag then
      local nums = {}
      for n in line:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
      local idle = (nums[4] or 0) + (nums[5] or 0)
      local total = 0
      for _, x in ipairs(nums) do total = total + x end
      if tag == "cpu" then
        agg = { total = total, idle = idle }
      else
        cores[tonumber(tag:match("%d+"))] = { total = total, idle = idle }
      end
    end
  end
  return cores, agg
end

local function busyFraction(cur, prev)
  if not (cur and prev) then return 0 end
  local dt = cur.total - prev.total
  local di = cur.idle - prev.idle
  if dt <= 0 then return 0 end
  local f = 1 - di / dt
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f
end

-- RAM used fraction from /proc/meminfo (MemTotal - MemAvailable) / MemTotal.
local function readRam()
  local txt = noctalia.readFile("/proc/meminfo")
  if not txt or txt == "" then return nil end
  local total = tonumber(txt:match("MemTotal:%s*(%d+)"))
  local avail = tonumber(txt:match("MemAvailable:%s*(%d+)"))
  if not total or not avail or total == 0 then return nil end
  local f = (total - avail) / total
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f
end

local function sortedKeys(t)
  local k = {}
  for key in pairs(t) do k[#k + 1] = key end
  table.sort(k)
  return k
end

function update()
  local cores, agg = readCpu()
  if not cores then
    desktopWidget.render(ui.column({ padding = 10 }, { ui.label({ text = "no /proc/stat" }) }))
    return
  end
  local ram = readRam()

  pushCapped(cpuHist, busyFraction(agg, prevTotal))
  if ram then pushCapped(ramHist, ram) end

  local rows = {}
  for _, i in ipairs(sortedKeys(cores)) do
    local f = busyFraction(cores[i], prevCores and prevCores[i] or nil)
    rows[#rows + 1] = ui.row({ gap = 6, align = "center", key = "core" .. i }, {
      ui.label({ text = "c" .. i, fontSize = 11, width = 30, color = "on_surface_variant" }),
      ui.progress({
        progress = f,
        fill = (f >= 0.90) and "error" or "primary",
        track = "surface_variant",
        flexGrow = 1, height = 10, radius = 4,
      }),
      ui.label({ text = string.format("%d%%", math.floor(f * 100 + 0.5)), fontSize = 11, width = 38, textAlign = "right", color = "on_surface" }),
    })
  end

  prevCores = cores
  prevTotal = agg

  local tree = ui.column({ gap = 8, padding = 10 }, {
    ui.label({ text = "CPU per-core", fontSize = 13, fontWeight = "semibold", color = "on_surface" }),
    ui.column({ gap = 4 }, rows),
    ui.label({ text = "History — CPU / RAM", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
    ui.graph({
      values = cpuHist, values2 = ramHist,
      color = "primary", color2 = "tertiary",
      lineWidth = 2, fillOpacity = 0.15, height = 70,
    }),
  })
  desktopWidget.render(tree)
end
