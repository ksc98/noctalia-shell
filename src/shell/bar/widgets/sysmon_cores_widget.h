#pragma once

#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "shell/bar/widget.h"
#include "ui/palette.h"

#include <chrono>
#include <cstddef>
#include <vector>

class Box;
class SystemMonitorService;
struct wl_output;

// Per-core CPU bar chart: one vertical bar per logical core, height = busy %, with
// the system-time portion stacked on top in a second color. Heights are eased toward
// each new sample via the AnimationManager (vsync 60fps), unlike the SVG plugin which
// was capped at ~30fps by image reloads.
class SysmonCoresWidget : public Widget {
public:
  SysmonCoresWidget(
      SystemMonitorService* monitor, int barWidth, int gap, int vPadding, ColorSpec systemColor, ColorSpec borderColor,
      bool showBorder, bool showSystem, bool smoothing
  );
  ~SysmonCoresWidget() override;

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void onFrameTick(float deltaMs) override;
  [[nodiscard]] bool needsFrameTick() const override;

  void ensureBars(std::size_t n);
  void updateBars();

  SystemMonitorService* m_monitor;
  int m_barWidth;
  int m_gap;
  int m_vPadding;
  ColorSpec m_systemColor;
  ColorSpec m_borderColor;
  bool m_showBorder;
  bool m_showSystem;
  bool m_smoothing;

  Box* m_borderBox = nullptr;
  std::vector<Box*> m_userBars;
  std::vector<Box*> m_sysBars;
  std::vector<float> m_prevUser, m_targetUser, m_curUser;
  std::vector<float> m_prevSys, m_targetSys, m_curSys;

  float m_phase = 1.0f;
  AnimationManager::Id m_phaseAnim = 0;
  std::chrono::steady_clock::time_point m_lastSampleAt{};

  float m_barWpx = 3.0f;
  float m_gapPx = 1.0f;
  float m_padPx = 0.0f;
  float m_chartX = 0.0f;
  float m_heightPx = 0.0f;

  Timer m_updateTimer;
};
