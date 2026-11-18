#pragma once

#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "shell/bar/widget.h"
#include "ui/palette.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

class Box;
class Graph;
class SystemMonitorService;
struct wl_output;

// Per-core CPU bar chart: one vertical bar per logical core, height = busy %, with
// the system-time portion stacked on top in a second color. Heights are eased toward
// each new sample via the AnimationManager (vsync 60fps), unlike the SVG plugin which
// was capped at ~30fps by image reloads.
//
// Optionally overlays a temperature line (e.g. coolant) across the chart: x is time over a
// sliding window (right edge = now), y is a fixed temperature range. Its history lives in the
// process-lifetime SensorHistory, so it survives widget rebuilds and shell restarts.
class SysmonCoresWidget : public Widget {
public:
  struct TempLine {
    std::string sensor; // "" = off; "<hwmon name>/<attribute>" or an absolute path
    std::string label = "Temp";
    int windowSeconds = 3600;
    int intervalSeconds = 15; // sample cadence; window / interval points span the chart
    double minC = 20.0;
    double maxC = 45.0;
    double width = 0.3; // stroke width in logical px (a hairline with the 0.25 px AA band)
    ColorSpec color;
  };

  SysmonCoresWidget(
      SystemMonitorService* monitor, int barWidth, int gap, int vPadding, ColorSpec systemColor, ColorSpec borderColor,
      bool showBorder, bool showSystem, bool smoothing, TempLine tempLine
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
  void pollTempLine(Renderer& renderer);
  void layoutTempLine();

  SystemMonitorService* m_monitor;
  int m_barWidth;
  int m_gap;
  int m_vPadding;
  ColorSpec m_systemColor;
  ColorSpec m_borderColor;
  bool m_showBorder;
  bool m_showSystem;
  bool m_smoothing;
  TempLine m_tempLine;

  Box* m_borderBox = nullptr;
  std::vector<Box*> m_userBars;
  std::vector<Box*> m_sysBars;
  Graph* m_tempGraph = nullptr;
  std::size_t m_tempCount = 0;
  std::size_t m_tempSlots = 0; // samples in a full window
  std::int64_t m_tempLastMs = 0;
  std::string m_tempTooltip;
  std::vector<float> m_prevUser, m_targetUser, m_curUser;
  std::vector<float> m_prevSys, m_targetSys, m_curSys;

  float m_phase = 1.0f;
  AnimationManager::Id m_phaseAnim = 0;
  std::chrono::steady_clock::time_point m_lastSampleAt{};

  float m_barWpx = 3.0f;
  float m_gapPx = 1.0f;
  float m_padPx = 0.0f;
  float m_chartX = 0.0f;
  float m_barsW = 0.0f;
  float m_heightPx = 0.0f;

  Timer m_updateTimer;
};
