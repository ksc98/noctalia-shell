-- Shared `sensors -j` reader for the chip/label/valueKey widgets (coolant, watt).
-- Async: runs lm-sensors, decodes its JSON, and extracts <chip>/<label>/<key>.
-- Calls cb(value) on success, cb(nil) on any failure, exactly once per read.

local M = {}

-- lm-sensors appends a bus suffix to chip names (e.g. "quadro-hid-3" -> the JSON
-- key is "quadro-hid-3-d"), so match the configured chip as an exact key first,
-- then as a prefix.
local function findChip(data, name)
  if type(data[name]) == "table" then return data[name] end
  for k, v in pairs(data) do
    if type(k) == "string" and type(v) == "table" and k:sub(1, #name) == name then
      return v
    end
  end
  return nil
end

function M.read(chip, label, valueKey, cb)
  noctalia.runAsync("sensors -j 2>/dev/null", function(res)
    if res.exitCode ~= 0 or res.stdout == "" then return cb(nil) end
    local ok, data = pcall(noctalia.json.decode, res.stdout)
    if not ok or type(data) ~= "table" then return cb(nil) end
    local c = findChip(data, chip)
    if type(c) ~= "table" then return cb(nil) end
    local l = c[label]
    if type(l) ~= "table" then return cb(nil) end
    local v = l[valueKey]
    if type(v) ~= "number" then return cb(nil) end
    cb(v)
  end)
end

return M
