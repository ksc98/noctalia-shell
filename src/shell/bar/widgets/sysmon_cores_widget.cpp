#include "shell/bar/widgets/sysmon_cores_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/visuals/graph.h"
#include "system/sensor_history.h"
#include "system/system_monitor_service.h"
#include "ui/builders.h"
#include "ui/controls/box.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <string>
#include <utility>

namespace {

  // Graph hides its first two samples (cubic lead-in) and needs at least four to draw.
  constexpr std::size_t kGraphMinSamples = 4;

} // namespace

SysmonCoresWidget::SysmonCoresWidget(
    SystemMonitorService* monitor, int barWidth, int gap, int vPadding, ColorSpec systemColor, ColorSpec borderColor,
    bool showBorder, bool showSystem, bool smoothing, TempLine tempLine
)
    : m_monitor(monitor), m_barWidth(barWidth), m_gap(gap), m_vPadding(vPadding), m_systemColor(systemColor),
      m_borderColor(borderColor), m_showBorder(showBorder), m_showSystem(showSystem), m_smoothing(smoothing),
      m_tempLine(std::move(tempLine)) {
  m_tempLine.windowSeconds = std::max(60, m_tempLine.windowSeconds);
  m_tempLine.intervalSeconds = std::clamp(m_tempLine.intervalSeconds, 1, m_tempLine.windowSeconds / 4);
  m_tempSlots = static_cast<std::size_t>(m_tempLine.windowSeconds / m_tempLine.intervalSeconds);
  // Per-core sampling is opt-in: without a reference the service leaves cpuCoreUsagePercent empty.
  if (m_monitor != nullptr) {
    m_monitor->retainCpuCores();
  }
}

SysmonCoresWidget::~SysmonCoresWidget() {
  if (m_animations != nullptr) {
    m_animations->cancelForOwner(this);
  }
  if (m_monitor != nullptr) {
    m_monitor->releaseCpuCores();
  }
}

void SysmonCoresWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) { requestPanelToggle("sysmon-processes"); });
  setRoot(std::move(area));
  // Poll the (slowly-sampled) service; the animation smooths between samples.
  m_updateTimer.startRepeating(std::chrono::milliseconds(250), [this]() { requestUpdate(); });
}

void SysmonCoresWidget::ensureBars(std::size_t n) {
  if (n == 0 || !m_userBars.empty()) {
    return; // logical core count is fixed at boot — build the bars once
  }
  auto* container = root();
  if (container == nullptr) {
    return;
  }
  if (m_showBorder) {
    container->addChild(ui::box({.out = &m_borderBox}));
    m_borderBox->setBorder(m_borderColor, 1.0f);
  }
  for (std::size_t i = 0; i < n; ++i) {
    Box* user = nullptr;
    container->addChild(ui::box({.out = &user, .fill = colorSpecFromRole(ColorRole::Primary)}));
    m_userBars.push_back(user);

    Box* sys = nullptr;
    container->addChild(ui::box({.out = &sys, .fill = m_systemColor, .visible = m_showSystem}));
    m_sysBars.push_back(sys);
  }
  if (!m_tempLine.sensor.empty()) {
    // Added after the bars so the line draws on top of them.
    auto graph = std::make_unique<Graph>();
    graph->setColor(m_tempLine.color);
    graph->setFillOpacity(0.0f);
    graph->setAaSize(0.25f); // hairline: the default 0.5 band smears a thin stroke over two pixel rows
    m_tempGraph = static_cast<Graph*>(container->addChild(std::move(graph)));
    m_tempGraph->setVisible(false);
  }
  m_prevUser.assign(n, 0.0f);
  m_targetUser.assign(n, 0.0f);
  m_curUser.assign(n, 0.0f);
  m_prevSys.assign(n, 0.0f);
  m_targetSys.assign(n, 0.0f);
  m_curSys.assign(n, 0.0f);
}

void SysmonCoresWidget::updateBars() {
  const float H = m_heightPx;
  const std::size_t n = m_userBars.size();
  for (std::size_t i = 0; i < n; ++i) {
    const float user = m_prevUser[i] + (m_targetUser[i] - m_prevUser[i]) * m_phase;
    const float sys = m_prevSys[i] + (m_targetSys[i] - m_prevSys[i]) * m_phase;
    m_curUser[i] = user;
    m_curSys[i] = sys;

    const float x = m_chartX + static_cast<float>(i) * (m_barWpx + m_gapPx);
    float userH = std::clamp(user, 0.0f, 1.0f) * H;
    float sysH = std::clamp(sys, 0.0f, 1.0f) * H;
    if (userH + sysH > H) {
      userH = std::max(0.0f, H - sysH);
    }
    if (m_sysBars[i] != nullptr) {
      m_sysBars[i]->setPosition(x, m_padPx + H - sysH);
      m_sysBars[i]->setSize(m_barWpx, sysH);
    }
    if (m_userBars[i] != nullptr) {
      m_userBars[i]->setPosition(x, m_padPx + H - sysH - userH);
      m_userBars[i]->setSize(m_barWpx, userH);
    }
  }
}

void SysmonCoresWidget::doLayout(Renderer& /*renderer*/, float /*containerWidth*/, float containerHeight) {
  m_barWpx = std::max(1.0f, static_cast<float>(m_barWidth) * m_contentScale);
  m_gapPx = std::max(0.0f, static_cast<float>(m_gap) * m_contentScale);
  m_padPx = std::max(0.0f, static_cast<float>(m_vPadding) * m_contentScale);
  m_heightPx = std::max(1.0f, containerHeight - 2.0f * m_padPx);
  m_chartX = m_showBorder ? std::round(3.0f * m_contentScale) : 0.0f;
  updateBars();

  auto* rootNode = root();
  if (rootNode != nullptr) {
    const std::size_t n = m_userBars.size();
    const float barsW = n > 0 ? static_cast<float>(n) * (m_barWpx + m_gapPx) - m_gapPx : 0.0f;
    m_barsW = barsW;
    const float w = barsW > 0.0f ? barsW + 2.0f * m_chartX : 0.0f;
    rootNode->setSize(std::max(0.0f, w), containerHeight);

    if (m_borderBox != nullptr) {
      // Frame the 0-100% chart area: full bars touch the top edge, with a little air on the sides.
      const float inset = std::min(std::round(3.0f * m_contentScale), m_padPx);
      m_borderBox->setPosition(0.0f, m_padPx - inset);
      m_borderBox->setSize(w, m_heightPx + 2.0f * inset);
      m_borderBox->setRadius(std::round(3.0f * m_contentScale));
      m_borderBox->setVisible(n > 0);
    }
  }
  layoutTempLine();
}

void SysmonCoresWidget::layoutTempLine() {
  if (m_tempGraph == nullptr) {
    return;
  }
  const bool drawable = m_tempCount >= kGraphMinSamples && m_barsW > 0.0f;
  m_tempGraph->setVisible(drawable);
  if (!drawable) {
    return;
  }
  // Right-anchored: the right edge is now, and a partial window only spans its share of the
  // chart, so x stays proportional to time while the first window fills.
  const float drawnSegs = static_cast<float>(std::min(m_tempCount, m_tempSlots) - 3);
  const float frac = std::clamp(drawnSegs / static_cast<float>(m_tempSlots - 3), 0.0f, 1.0f);
  const float w = std::max(1.0f, m_barsW * frac);
  const float x = m_chartX + m_barsW - w;
  m_tempGraph->setPosition(x, m_padPx);
  m_tempGraph->setSize(w, m_heightPx);
  m_tempGraph->setLineWidth(static_cast<float>(m_tempLine.width) * m_contentScale);
}

void SysmonCoresWidget::pollTempLine(Renderer& renderer) {
  if (m_tempGraph == nullptr) {
    return;
  }
  const std::chrono::milliseconds window = std::chrono::seconds(m_tempLine.windowSeconds);
  const std::chrono::milliseconds interval = std::chrono::seconds(m_tempLine.intervalSeconds);
  const auto& samples = SensorHistory::instance().poll(m_tempLine.sensor, window, interval, 1000.0);
  const std::int64_t lastMs = samples.empty() ? 0 : samples.back().wallMs;
  if (samples.size() == m_tempCount && lastMs == m_tempLastMs) {
    return;
  }
  m_tempCount = samples.size();
  m_tempLastMs = lastMs;

  if (samples.empty()) {
    m_tempTooltip.clear();
  } else {
    float lo = samples.front().value;
    float hi = lo;
    for (const auto& sample : samples) {
      lo = std::min(lo, sample.value);
      hi = std::max(hi, sample.value);
    }
    const auto spanMin = (samples.back().wallMs - samples.front().wallMs + 30'000) / 60'000;
    m_tempTooltip = std::format(
        "{} {:.1f}°C — last {} min {:.1f}–{:.1f}°C", m_tempLine.label, samples.back().value, spanMin, lo, hi
    );
  }

  if (samples.size() >= kGraphMinSamples) {
    const double range = std::max(0.1, m_tempLine.maxC - m_tempLine.minC);
    std::vector<float> values;
    values.reserve(samples.size());
    for (const auto& sample : samples) {
      values.push_back(static_cast<float>(std::clamp((sample.value - m_tempLine.minC) / range, 0.0, 1.0)));
    }
    m_tempGraph->setValues(std::move(values));
    m_tempGraph->sync(renderer);
  }
  layoutTempLine();
  requestRedraw();
}

void SysmonCoresWidget::doUpdate(Renderer& renderer) {
  if (m_monitor == nullptr) {
    return;
  }
  const auto stats = m_monitor->latest();
  const std::size_t n = stats.cpuCoreUsagePercent.size();
  if (n == 0) {
    return; // not sampled yet; the repeating timer will retry
  }
  ensureBars(n);
  pollTempLine(renderer);
  if (stats.sampledAt == m_lastSampleAt) {
    return; // no new sample
  }
  m_lastSampleAt = stats.sampledAt;

  const std::size_t count = std::min(n, m_userBars.size());
  for (std::size_t i = 0; i < count; ++i) {
    const double busy = std::clamp(stats.cpuCoreUsagePercent[i], 0.0, 100.0);
    const double sys = i < stats.cpuCoreSystemPercent.size()
        ? std::clamp(stats.cpuCoreSystemPercent[i], 0.0, busy)
        : 0.0;
    const double user = busy - sys;
    m_prevUser[i] = m_curUser[i];
    m_prevSys[i] = m_curSys[i];
    m_targetUser[i] = static_cast<float>(user / 100.0);
    m_targetSys[i] = static_cast<float>(sys / 100.0);
  }

  double sum = 0.0;
  double mx = 0.0;
  for (std::size_t i = 0; i < n; ++i) {
    sum += stats.cpuCoreUsagePercent[i];
    mx = std::max(mx, stats.cpuCoreUsagePercent[i]);
  }
  const int avg = static_cast<int>(sum / static_cast<double>(n) + 0.5);
  std::string tooltip = "CPU " + std::to_string(n) + " threads — avg " + std::to_string(avg) + "%, max "
      + std::to_string(static_cast<int>(mx + 0.5)) + "%";
  if (!m_tempTooltip.empty()) {
    tooltip += "\n" + m_tempTooltip;
  }
  static_cast<InputArea*>(root())->setTooltip(tooltip);

  if (m_smoothing && m_animations != nullptr) {
    m_animations->cancel(m_phaseAnim);
    m_phase = 0.0f;
    m_phaseAnim = m_animations->animate(
        0.0f, 1.0f, static_cast<float>(Style::animNormal), Easing::EaseOutCubic,
        [this](float v) {
          m_phase = v;
          updateBars();
          requestRedraw();
        },
        [this]() { m_phaseAnim = 0; }, this
    );
    requestFrameTick();
  } else {
    m_phase = 1.0f;
    updateBars();
    requestRedraw();
  }
}

void SysmonCoresWidget::onFrameTick(float /*deltaMs*/) { requestRedraw(); }

bool SysmonCoresWidget::needsFrameTick() const { return m_phaseAnim != 0; }
