#pragma once

#include "render/core/color.h"
#include "render/core/renderer.h"

#include <optional>
#include <string>
#include <variant>
#include <vector>

struct TooltipRow {
  std::string key;
  std::string value;
  TextEllipsize valueEllipsize = TextEllipsize::End;
  // A colour dot before the key, e.g. a chart legend entry.
  std::optional<Color> swatch;
};

enum class TooltipPlacement : std::uint8_t {
  Default,
  Above,
  Below,
  Left,
  Right,
};

struct TooltipAnchorInsets {
  float top = 0.0F;
  float right = 0.0F;
  float bottom = 0.0F;
  float left = 0.0F;
};

using TooltipContent = std::variant<std::monostate, std::string, std::vector<TooltipRow>>;
