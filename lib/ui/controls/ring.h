#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

#include <vector>

class RingNode;

// One donut-chart slice: `value` is its share of the circle (0–1).
struct RingSegment {
  float value = 0.0F;
  ColorSpec fill;
};

// Circular progress gauge: a track circle with a round-capped fill arc growing clockwise from
// 12 o'clock. The circle is the largest one centred in the control's bounds. With segments set it
// is a donut chart instead: consecutive flat-joined slices from 12 o'clock over the track.
class Ring : public Node {
public:
  static constexpr float kDefaultThickness = 2.0F;
  static inline const ColorSpec kDefaultFill = colorSpecFromRole(ColorRole::Primary);
  static inline const ColorSpec kDefaultTrack = colorSpecFromRole(ColorRole::SurfaceContainer);

  Ring();

  // Up to RingStyle::kMaxSegments slices (extras are dropped); the running total is capped at a
  // full circle. Non-empty segments replace the fill arc; an empty list returns to it.
  void setSegments(std::vector<RingSegment> segments);

  void setFill(const ColorSpec& color);
  void setFill(const Color& color);
  void setTrack(const ColorSpec& color);
  void setTrack(const Color& color);
  // Stroke width in logical px; hosts apply their content scale, as with setSize().
  void setThickness(float thickness);

  void setProgress(float progress); // 0.0–1.0
  float progress() const noexcept { return m_progress; }
  float thickness() const noexcept { return m_thickness; }

  void setSize(float width, float height) override;

private:
  void syncStyle();

  RingNode* m_ring = nullptr;
  ColorSpec m_fillColor = kDefaultFill;
  ColorSpec m_trackColor = kDefaultTrack;
  float m_thickness = kDefaultThickness;
  float m_progress = 0.0F;
  std::vector<RingSegment> m_segments;
  Signal<>::ScopedConnection m_paletteConn;
};
