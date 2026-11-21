-- EcoFlow power station bar widget ("󰂄 100% 󱐋462W 󰚥265W"), from the homelab ecoflow
-- service's Server-Sent Events stream (`/v1/stream`: the full /v1/status JSON on connect,
-- then one event per change, a `: keepalive` comment every 15 s).
--
-- Rules and glyphs follow tmux-status-rs `src/segments/ecoflow/mod.rs`:
-- * battery glyph 󰂄 while charging, else 󰁹, then the % rounded;
-- * watts in from the wall after a solid bolt (U+F140B), out to the load after a solid
--   plug (U+F06A5), each only when nonzero;
-- * shown while power flows either way, on battery (ac_plugged == false), or while the
--   battery charges or moves at least `batteryWatts`; hidden when plugged in with nothing
--   flowing, when the service is unreachable or stale, and when the reading is older than
--   `maxAgeSeconds` (the event's age_s plus the time since the stream last delivered an
--   event or keepalive).
--
-- One native HTTP stream (noctalia.httpStream) per widget instance: no process spawns and
-- no polling. The 1 s update tick only re-evaluates the age, restarts a stream that went
-- silent (gateway or pod hang, or a suspend: nowMs is wall clock, so a wake shows up as a
-- long silence) and reconnects with backoff after a close.

local url = noctalia.getConfig("url") or "https://ecoflow.kych.cloud/v1/stream"
local maxAge = noctalia.getConfig("maxAgeSeconds") or 60
local batteryWatts = noctalia.getConfig("batteryWatts") or 10

local CHARGING_GLYPH = "\u{F0084}" -- nf-md-battery_charging
local BATTERY_GLYPH = "\u{F0079}" -- nf-md-battery
local WALL_IN = "\u{F140B}" -- nf-md-lightning_bolt
local LOAD_OUT = "\u{F06A5}" -- nf-md-power_plug

-- One missed keepalive plus margin (the gateway itself cuts a stream after 20 s of silence).
local IDLE_MS = 25000
local BACKOFF_MIN_MS, BACKOFF_MAX_MS = 1000, 60000

local stream = nil -- live httpStream handle
local status = nil -- last decoded event
local lastAliveMs = 0 -- last event or keepalive, wall clock
local nextConnectMs = 0
local backoffMs = BACKOFF_MIN_MS
local shown = nil -- last setVisible value

noctalia.setUpdateInterval(1000)
barWidget.setVisible(false)

local function setShown(v)
  if shown ~= v then
    shown = v
    barWidget.setVisible(v)
  end
end

local function num(v)
  return type(v) == "number" and v or nil
end

-- Bands as the tmux segment's (<20, <50, <80, rest) in theme roles.
local function levelColor(soc)
  if soc < 20 then
    return "error"
  elseif soc < 50 then
    return "secondary"
  elseif soc < 80 then
    return "on_surface"
  end
  return "tertiary"
end

local function fmtMinutes(m)
  m = math.floor(m + 0.5)
  if m < 60 then
    return string.format("%d min", m)
  end
  return string.format("%dh %02dm", m // 60, m % 60)
end

local function tooltipRows(s, soc, ageS)
  local rows = {}
  local max = num(s.max_chg_soc)
  table.insert(rows, { "Battery", string.format("%d%%%s", soc, max and string.format(" (max %d%%)", max) or "") })

  local limit = num(s.chg_limit_w)
  if limit then
    local v = string.format("%d W", limit)
    if type(s.curve_band) == "string" then
      v = v .. " · band " .. s.curve_band
    end
    if s.thermal_capped == true then
      v = v .. " (thermal cap)"
    end
    table.insert(rows, { "Charge limit", v })
  end
  local o = s.rate_override
  if type(o) == "table" and num(o.watts) then
    local untilText = "until full"
    if num(o.expires_ms) then
      untilText = "until " .. noctalia.formatTime("%-I:%M %p", math.floor(o.expires_ms / 1000))
    end
    table.insert(rows, { "Override", string.format("%d W %s", o.watts, untilText) })
  end
  if type(s.curve_idle) == "string" then
    table.insert(rows, { "Curve", "idle (" .. s.curve_idle .. ")" })
  end

  local cell = num(s.cell_temp_max_c)
  if cell then
    table.insert(rows, { "Cell temp", string.format("%d °C", cell) })
  end

  local batt = num(s.batt_w) or 0
  if s.charging == true and num(s.chg_remain_min) then
    table.insert(rows, { "To full", fmtMinutes(s.chg_remain_min) })
  elseif batt <= -batteryWatts and num(s.dsg_remain_min) then
    table.insert(rows, { "To empty", fmtMinutes(s.dsg_remain_min) })
  end

  table.insert(rows, { "Data age", string.format("%d s", math.floor(ageS + 0.5)) })
  return rows
end

local function paint()
  local s = status
  if not s or s.stale ~= false or not num(s.soc) or not num(s.age_s) then
    setShown(false)
    return
  end
  local ageS = math.max(s.age_s, 0) + math.max(noctalia.nowMs() - lastAliveMs, 0) / 1000
  if ageS > maxAge then
    setShown(false)
    return
  end

  local soc = math.clamp(math.floor(s.soc + 0.5), 0, 100)
  -- Negatives read as no flow, as in the reference.
  local inW = math.max(math.floor((num(s.in_w) or 0) + 0.5), 0)
  local outW = math.max(math.floor((num(s.out_w) or 0) + 0.5), 0)
  local charging = s.charging == true
  local flowing = inW > 0 or outW > 0
  local batteryActive = charging or math.abs(num(s.batt_w) or 0) >= batteryWatts
  if not (flowing or s.ac_plugged == false or batteryActive) then
    setShown(false)
    return
  end

  local text = string.format("%s %d%%", charging and CHARGING_GLYPH or BATTERY_GLYPH, soc)
  if inW > 0 then
    text = text .. string.format(" %s%dW", WALL_IN, inW)
  end
  if outW > 0 then
    text = text .. string.format(" %s%dW", LOAD_OUT, outW)
  end
  barWidget.setText(text)
  barWidget.setColor(levelColor(soc), "script")
  barWidget.setTooltip(tooltipRows(s, soc, ageS))
  setShown(true)
end

local function scheduleReconnect()
  nextConnectMs = noctalia.nowMs() + backoffMs
  backoffMs = math.min(backoffMs * 2, BACKOFF_MAX_MS)
end

local function onLine(line)
  lastAliveMs = noctalia.nowMs()
  local body = line:match("^data:%s?(.*)$")
  if not body then
    return -- keepalive comment, blank separator, or a non-SSE error body
  end
  local decoded = noctalia.json.decode(body)
  if type(decoded) == "table" then
    status = decoded
    backoffMs = BACKOFF_MIN_MS
    paint()
  end
end

local function connect()
  lastAliveMs = noctalia.nowMs() -- bounds a connect that hangs by the idle watchdog
  stream = noctalia.httpStream({ url = url, headers = { "Accept: text/event-stream" } }, onLine, function(_result)
    -- Server close, network error or an HTTP error (a 503 arrives as ok = true, status = 503):
    -- every close reconnects from the update tick, never straight from here.
    stream = nil
    scheduleReconnect()
  end)
  if not stream then
    scheduleReconnect()
  end
end

function update()
  local now = noctalia.nowMs()
  if stream and now - lastAliveMs > IDLE_MS then
    stream.stop() -- suppresses onClose
    stream = nil
    scheduleReconnect()
  end
  if not stream and now >= nextConnectMs then
    connect()
  end
  paint()
end

connect()
