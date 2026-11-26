#pragma once

#include "render/core/render_styles.h"
#include "render/scene/custom_draw_node.h"

// Paints RingStyle centred in its bounds. Shell code uses the Ring control instead.
class RingNode : public CustomDrawNode {
public:
  void setStyle(const RingStyle& style) {
    if (m_style.fill == style.fill
        && m_style.track == style.track
        && m_style.thickness == style.thickness
        && m_style.progress == style.progress
        && m_style.segmentCount == style.segmentCount
        && m_style.segmentEnds == style.segmentEnds
        && m_style.segmentFills == style.segmentFills) {
      return;
    }
    m_style = style;
    markPaintDirty();
  }

  const RingStyle& style() const noexcept { return m_style; }

  void draw(RenderBackend& backend, const CustomDrawContext& context) const override;

private:
  RingStyle m_style;
};
