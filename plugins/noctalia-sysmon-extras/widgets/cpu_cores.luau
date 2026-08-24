-- Per-core CPU chart, drawn as a themed SVG and shown via barWidget.setImage.
-- One bar per thread: user time in the theme primary, system time stacked on top
-- in the error color (the v4 user/system split).
--
-- Animation: the widget ticks fast (frameMs) but only re-samples /proc/stat every
-- pollIntervalMs. Between samples each bar eases toward its latest target value, so
-- the chart glides instead of jumping. Redraws are skipped when nothing is moving,
-- so an idle CPU costs nothing.

local sampleMs = noctalia.getConfig("pollIntervalMs") or 500
local frameMs = noctalia.getConfig("frameMs") or 33
local alpha = noctalia.getConfig("smoothing") or 0.35
if alpha <= 0 or alpha > 1 then alpha = 0.35 end
noctalia.setUpdateInterval(frameMs)

-- Write to tmpfs ($XDG_RUNTIME_DIR) so the per-frame rewrites never touch disk.
local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
local SVG_PATH = (runtimeDir and runtimeDir ~= "" and (runtimeDir .. "/noctalia-sysmon-cpucores.svg"))
  or noctalia.expandPath("~/.cache/noctalia-sysmon-cpucores.svg")
local COLORS_PATH = noctalia.expandPath("~/.config/noctalia/colors.json")
local BAR, GAP, H = 2, 1, 22

local ticksPerSample = math.floor(sampleMs / frameMs + 0.5)
if ticksPerSample < 1 then ticksPerSample = 1 end

local pColor, sColor, trackColor = "#7aa2f7", "#f7768e", "#9aa5ce"
local function refreshTheme()
  local txt = noctalia.readFile(COLORS_PATH)
  if not txt then return end
  local ok, c = pcall(noctalia.json.decode, txt)
  if ok and type(c) == "table" then
    pColor = c.mPrimary or pColor
    sColor = c.mError or sColor
    trackColor = c.mOnSurfaceVariant or trackColor
  end
end

local function readStat()
  local txt = noctalia.readFile("/proc/stat")
  if not txt or txt == "" then return nil end
  local cores = {}
  for line in txt:gmatch("[^\n]+") do
    local cpu = line:match("^(cpu%d+)%s")
    if cpu then
      local n = {}
      for v in line:gmatch("%d+") do n[#n + 1] = tonumber(v) end
      local total = 0
      for _, x in ipairs(n) do total = total + x end
      cores[tonumber(cpu:match("%d+"))] = {
        u = (n[1] or 0) + (n[2] or 0),
        s = (n[3] or 0) + (n[6] or 0) + (n[7] or 0),
        total = total,
      }
    end
  end
  return cores
end

local prev = nil
local target = {} -- per-core {user, sys} latest sampled fractions
local shown = {}  -- per-core {user, sys} eased display values
local tick = 0
local imaged = false

local function sample()
  local cur = readStat()
  if not cur then return end
  local idxs = {}
  for k in pairs(cur) do idxs[#idxs + 1] = k end
  table.sort(idxs)
  local t = {}
  for _, i in ipairs(idxs) do
    local uF, sF = 0, 0
    if prev and prev[i] then
      local dT = cur[i].total - prev[i].total
      if dT > 0 then
        uF = (cur[i].u - prev[i].u) / dT
        sF = (cur[i].s - prev[i].s) / dT
      end
    end
    if uF < 0 then uF = 0 end
    if sF < 0 then sF = 0 end
    t[#t + 1] = { user = uF, sys = sF }
  end
  prev = cur
  target = t
  for i = 1, #target do shown[i] = shown[i] or { user = 0, sys = 0 } end
  refreshTheme()
end

local function buildSvg(list)
  local w = #list * (BAR + GAP)
  local t = { string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', w, H, w, H) }
  for i = 1, #list do
    local c = list[i]
    local x = (i - 1) * (BAR + GAP)
    local uH = c.user * H
    local sH = c.sys * H
    if uH + sH > H then sH = H - uH end
    t[#t + 1] = string.format(
      '<rect x="%d" y="0" width="%d" height="%d" rx="0.5" fill="%s" fill-opacity="0.18"/>', x, BAR, H, trackColor)
    if uH > 0.1 then
      t[#t + 1] = string.format(
        '<rect x="%d" y="%.2f" width="%d" height="%.2f" rx="0.5" fill="%s"/>', x, H - uH, BAR, uH, pColor)
    end
    if sH > 0.1 then
      t[#t + 1] = string.format(
        '<rect x="%d" y="%.2f" width="%d" height="%.2f" rx="0.5" fill="%s"/>', x, H - uH - sH, BAR, sH, sColor)
    end
  end
  t[#t + 1] = "</svg>"
  return table.concat(t)
end

function update()
  if prev == nil or tick % ticksPerSample == 0 then sample() end
  tick = tick + 1
  if #target == 0 then return end

  local maxDelta = 0
  for i = 1, #target do
    local sh = shown[i] or { user = 0, sys = 0 }
    local du = target[i].user - sh.user
    local ds = target[i].sys - sh.sys
    sh.user = sh.user + du * alpha
    sh.sys = sh.sys + ds * alpha
    shown[i] = sh
    local d = math.abs(du) + math.abs(ds)
    if d > maxDelta then maxDelta = d end
  end

  if (not imaged) or maxDelta > 0.002 then
    noctalia.writeFile(SVG_PATH, buildSvg(shown))
  end
  if not imaged then
    barWidget.setImage(SVG_PATH, true, #target * (BAR + GAP), H)
    imaged = true
  end

  if tick % ticksPerSample == 0 then
    local tip = {}
    for i = 1, #target do
      tip[#tip + 1] = string.format("core %d: %d%% (sys %d%%)", i,
        math.floor((target[i].user + target[i].sys) * 100 + 0.5),
        math.floor(target[i].sys * 100 + 0.5))
    end
    barWidget.setTooltip(table.concat(tip, "\n"))
  end
end
