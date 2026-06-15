#include "shell/bar/widgets/sysmon_cores_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "system/system_monitor_service.h"
#include "ui/builders.h"
#include "ui/controls/box.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <string>

SysmonCoresWidget::SysmonCoresWidget(
    SystemMonitorService* monitor, int barWidth, int gap, ColorSpec systemColor, bool showSystem, bool smoothing
)
    : m_monitor(monitor), m_barWidth(barWidth), m_gap(gap), m_systemColor(systemColor), m_showSystem(showSystem),
      m_smoothing(smoothing) {}

SysmonCoresWidget::~SysmonCoresWidget() {
  if (m_animations != nullptr) {
    m_animations->cancelForOwner(this);
  }
}

void SysmonCoresWidget::create() {
  setRoot(std::make_unique<InputArea>());
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
  for (std::size_t i = 0; i < n; ++i) {
    Box* user = nullptr;
    container->addChild(ui::box({.out = &user, .fill = colorSpecFromRole(ColorRole::Primary)}));
    m_userBars.push_back(user);

    Box* sys = nullptr;
    container->addChild(ui::box({.out = &sys, .fill = m_systemColor, .visible = m_showSystem}));
    m_sysBars.push_back(sys);
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

    const float x = static_cast<float>(i) * (m_barWpx + m_gapPx);
    float userH = std::clamp(user, 0.0f, 1.0f) * H;
    float sysH = std::clamp(sys, 0.0f, 1.0f) * H;
    if (userH + sysH > H) {
      sysH = std::max(0.0f, H - userH);
    }
    if (m_userBars[i] != nullptr) {
      m_userBars[i]->setPosition(x, H - userH);
      m_userBars[i]->setSize(m_barWpx, userH);
    }
    if (m_sysBars[i] != nullptr) {
      m_sysBars[i]->setPosition(x, H - userH - sysH);
      m_sysBars[i]->setSize(m_barWpx, sysH);
    }
  }
}

void SysmonCoresWidget::doLayout(Renderer& /*renderer*/, float /*containerWidth*/, float containerHeight) {
  m_barWpx = std::max(1.0f, static_cast<float>(m_barWidth) * m_contentScale);
  m_gapPx = std::max(0.0f, static_cast<float>(m_gap) * m_contentScale);
  m_heightPx = containerHeight;
  updateBars();

  auto* rootNode = root();
  if (rootNode != nullptr) {
    const std::size_t n = m_userBars.size();
    const float w = n > 0 ? static_cast<float>(n) * (m_barWpx + m_gapPx) - m_gapPx : 0.0f;
    rootNode->setSize(std::max(0.0f, w), containerHeight);
  }
}

void SysmonCoresWidget::doUpdate(Renderer& /*renderer*/) {
  if (m_monitor == nullptr) {
    return;
  }
  const auto stats = m_monitor->latest();
  const std::size_t n = stats.perCoreUsagePercent.size();
  if (n == 0) {
    return; // not sampled yet; the repeating timer will retry
  }
  ensureBars(n);
  if (stats.sampledAt == m_lastSampleAt) {
    return; // no new sample
  }
  m_lastSampleAt = stats.sampledAt;

  const std::size_t count = std::min(n, m_userBars.size());
  for (std::size_t i = 0; i < count; ++i) {
    const double busy = std::clamp(stats.perCoreUsagePercent[i], 0.0, 100.0);
    const double sys = i < stats.perCoreSystemPercent.size()
        ? std::clamp(stats.perCoreSystemPercent[i], 0.0, busy)
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
    sum += stats.perCoreUsagePercent[i];
    mx = std::max(mx, stats.perCoreUsagePercent[i]);
  }
  const int avg = static_cast<int>(sum / static_cast<double>(n) + 0.5);
  static_cast<InputArea*>(root())->setTooltip(
      "CPU " + std::to_string(n) + " threads — avg " + std::to_string(avg) + "%, max "
      + std::to_string(static_cast<int>(mx + 0.5)) + "%"
  );

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
