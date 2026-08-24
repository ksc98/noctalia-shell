#pragma once

#include "core/timer_manager.h"
#include "shell/panel/panel.h"

#include <array>
#include <cstddef>
#include <string>
#include <unordered_map>
#include <vector>

class Flex;
class Label;
class Renderer;

// Dropdown listing the top-CPU processes, opened by clicking the sysmon_cores
// bar widget. First paint shows since-boot averages; while open, a repeating
// timer resamples /proc and switches to interval-based percentages (top-style:
// 100% = one core).
class SysmonProcessesPanel : public Panel {
public:
  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override;
  [[nodiscard]] float preferredHeight() const override;
  [[nodiscard]] PanelPlacement panelPlacement() const noexcept override { return PanelPlacement::Attached; }

private:
  static constexpr std::size_t kRowCount = 10;
  static constexpr float kPanelWidth = 260.0f;
  static constexpr float kRowHeight = 24.0f;
  static constexpr float kCpuColumnWidth = 56.0f;

  struct ProcTimes {
    unsigned long long jiffies = 0;   // utime + stime
    unsigned long long startTime = 0; // jiffies since boot; guards against pid reuse
    std::string comm;
  };

  struct TopEntry {
    double percent = 0.0;
    std::string comm;
  };

  void doLayout(Renderer& renderer, float width, float height) override;

  void resample();
  void renderRows(const std::vector<TopEntry>& top);

  Flex* m_rootLayout = nullptr;
  std::array<Label*, kRowCount> m_nameLabels{};
  std::array<Label*, kRowCount> m_cpuLabels{};

  Timer m_refreshTimer;
  std::unordered_map<int, ProcTimes> m_prevProcs;
  unsigned long long m_prevTotalJiffies = 0;
  bool m_hasPrevSample = false;
};
