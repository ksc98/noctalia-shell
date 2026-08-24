-- Themed single-path SVG icon for bar widgets. The bar's font glyphs are fixed at
-- 16px (Style::baseGlyphSize, no script override), so widgets that want a larger or
-- custom icon render an SVG via setImage instead: tinted with a colors.json role,
-- written to tmpfs, rewritten when the theme changes (setImage watch picks it up).

local M = {}

local COLORS_PATH = noctalia.expandPath("~/.config/noctalia/colors.json")

-- opts: file, pathData, colorKey, fallback, viewW, viewH, width, height
-- Returns a refresh function; call it from update() (cheap: one small file read).
function M.make(opts)
  local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
  local svgPath = (runtimeDir and runtimeDir ~= "" and (runtimeDir .. "/" .. opts.file))
    or noctalia.expandPath("~/.cache/" .. opts.file)
  local current = nil
  local imaged = false
  return function()
    local color = opts.fallback
    local txt = noctalia.readFile(COLORS_PATH)
    if txt then
      local ok, c = pcall(noctalia.json.decode, txt)
      if ok and type(c) == "table" and type(c[opts.colorKey]) == "string" then
        color = c[opts.colorKey]
      end
    end
    if color ~= current then
      current = color
      noctalia.writeFile(svgPath, string.format(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
          .. '<path fill="%s" fill-rule="evenodd" d="%s"/></svg>',
        opts.viewW, opts.viewH, opts.viewW, opts.viewH, color, opts.pathData))
    end
    if not imaged then
      barWidget.setImage(svgPath, true, opts.width, opts.height)
      imaged = true
    end
  end
end

return M
