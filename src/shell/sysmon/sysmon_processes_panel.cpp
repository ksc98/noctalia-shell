#include "shell/sysmon/sysmon_processes_panel.h"

#include "shell/panel/panel_manager.h"
#include "ui/builders.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {

  constexpr std::chrono::milliseconds kRefreshInterval{1500};

  // Sum of all fields on the aggregate "cpu " line — total jiffies across every core.
  unsigned long long readTotalJiffies() {
    std::ifstream stat("/proc/stat");
    std::string label;
    if (!stat || !(stat >> label) || label != "cpu") {
      return 0;
    }
    unsigned long long total = 0;
    unsigned long long field = 0;
    while (stat >> field) {
      total += field;
    }
    return total;
  }

  double readUptimeSeconds() {
    std::ifstream uptime("/proc/uptime");
    double seconds = 0.0;
    if (uptime) {
      uptime >> seconds;
    }
    return seconds;
  }

} // namespace

void SysmonProcessesPanel::create() {
  const float scale = contentScale();

  auto rootLayout = ui::column({
      .out = &m_rootLayout,
      .align = FlexAlign::Stretch,
      .gap = Style::spaceXs * scale,
  });

  rootLayout->addChild(ui::label({
      .text = "Top processes",
      .fontSize = Style::fontSizeTitle * scale,
      .fontWeight = FontWeight::Bold,
      .color = colorSpecFromRole(ColorRole::Primary),
  }));

  for (std::size_t i = 0; i < kRowCount; ++i) {
    auto row = ui::row({
        .align = FlexAlign::Center,
        .gap = Style::spaceSm * scale,
        .minHeight = kRowHeight * scale,
    });
    row->addChild(ui::label({
        .out = &m_nameLabels[i],
        .text = "",
        .fontSize = Style::fontSizeBody * scale,
        .color = colorSpecFromRole(ColorRole::OnSurface),
        .ellipsize = TextEllipsize::End,
        .flexGrow = 1.0f,
    }));
    row->addChild(ui::label({
        .out = &m_cpuLabels[i],
        .text = "",
        .fontSize = Style::fontSizeBody * scale,
        .color = colorSpecFromRole(ColorRole::Secondary),
        .minWidth = kCpuColumnWidth * scale,
        .textAlign = TextAlign::End,
    }));
    rootLayout->addChild(std::move(row));
  }

  setRoot(std::move(rootLayout));
}

void SysmonProcessesPanel::onOpen(std::string_view /*context*/) {
  m_prevProcs.clear();
  m_prevTotalJiffies = 0;
  m_hasPrevSample = false;
  resample();
  m_refreshTimer.startRepeating(kRefreshInterval, [this]() {
    resample();
    PanelManager::instance().requestLayout();
  });
}

void SysmonProcessesPanel::onClose() {
  m_refreshTimer.stop();
  m_prevProcs.clear();
  m_hasPrevSample = false;
  m_rootLayout = nullptr;
  m_nameLabels.fill(nullptr);
  m_cpuLabels.fill(nullptr);
}

float SysmonProcessesPanel::preferredWidth() const {
  return std::ceil(scaled(kPanelWidth + Style::panelPadding * 2.0f));
}

float SysmonProcessesPanel::preferredHeight() const {
  const float rows = kRowHeight * static_cast<float>(kRowCount);
  const float gaps = Style::spaceXs * static_cast<float>(kRowCount); // title→rows + between rows
  return std::ceil(scaled(Style::fontSizeTitle + rows + gaps + Style::panelPadding * 2.0f));
}

void SysmonProcessesPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
}

void SysmonProcessesPanel::resample() {
  const unsigned long long totalJiffies = readTotalJiffies();

  std::unordered_map<int, ProcTimes> procs;
  std::error_code ec;
  for (const auto& entry : std::filesystem::directory_iterator("/proc", ec)) {
    const std::string name = entry.path().filename().string();
    if (name.empty() || !std::all_of(name.begin(), name.end(), [](unsigned char c) { return std::isdigit(c); })) {
      continue;
    }
    std::ifstream stat(entry.path() / "stat");
    std::string line;
    if (!stat || !std::getline(stat, line)) {
      continue; // process exited between listing and read
    }
    // pid (comm) state ... — comm may contain spaces/parens, so bracket on the last ')'.
    const std::size_t open = line.find('(');
    const std::size_t close = line.rfind(')');
    if (open == std::string::npos || close == std::string::npos || close < open) {
      continue;
    }
    ProcTimes times;
    times.comm = line.substr(open + 1, close - open - 1);
    std::istringstream rest(line.substr(close + 1));
    // Post-comm fields (stat fields 3..): state=3 ... utime=14 stime=15 ... starttime=22.
    std::string token;
    unsigned long long utime = 0;
    unsigned long long stime = 0;
    for (int field = 3; field <= 22 && (rest >> token); ++field) {
      if (field == 14) {
        utime = std::strtoull(token.c_str(), nullptr, 10);
      } else if (field == 15) {
        stime = std::strtoull(token.c_str(), nullptr, 10);
      } else if (field == 22) {
        times.startTime = std::strtoull(token.c_str(), nullptr, 10);
      }
    }
    times.jiffies = utime + stime;
    procs.emplace(std::stoi(name), std::move(times));
  }

  const auto nCpu = static_cast<double>(std::max(1L, sysconf(_SC_NPROCESSORS_ONLN)));

  std::vector<TopEntry> top;
  top.reserve(procs.size());
  if (m_hasPrevSample && totalJiffies > m_prevTotalJiffies) {
    const auto totalDelta = static_cast<double>(totalJiffies - m_prevTotalJiffies);
    for (const auto& [pid, cur] : procs) {
      const auto prev = m_prevProcs.find(pid);
      if (prev == m_prevProcs.end() || prev->second.startTime != cur.startTime
          || cur.jiffies < prev->second.jiffies) {
        continue; // new process (or reused pid) — no interval delta yet
      }
      const auto delta = static_cast<double>(cur.jiffies - prev->second.jiffies);
      if (delta > 0.0) {
        top.push_back({.percent = delta / totalDelta * nCpu * 100.0, .comm = cur.comm});
      }
    }
  } else {
    // First sample: since-boot average so the dropdown opens populated.
    const double uptimeJiffies = readUptimeSeconds() * static_cast<double>(std::max(1L, sysconf(_SC_CLK_TCK)));
    for (const auto& [pid, cur] : procs) {
      const double aliveJiffies = uptimeJiffies - static_cast<double>(cur.startTime);
      if (aliveJiffies > 0.0 && cur.jiffies > 0) {
        top.push_back({.percent = static_cast<double>(cur.jiffies) / aliveJiffies * 100.0, .comm = cur.comm});
      }
    }
  }

  const std::size_t count = std::min(top.size(), kRowCount);
  std::partial_sort(top.begin(), top.begin() + static_cast<std::ptrdiff_t>(count), top.end(), [](const TopEntry& a, const TopEntry& b) {
    return a.percent > b.percent;
  });
  top.resize(count);

  m_prevProcs = std::move(procs);
  m_prevTotalJiffies = totalJiffies;
  m_hasPrevSample = true;

  renderRows(top);
}

void SysmonProcessesPanel::renderRows(const std::vector<TopEntry>& top) {
  for (std::size_t i = 0; i < kRowCount; ++i) {
    if (m_nameLabels[i] == nullptr || m_cpuLabels[i] == nullptr) {
      continue;
    }
    if (i < top.size()) {
      char pct[16];
      std::snprintf(pct, sizeof(pct), "%.1f%%", top[i].percent);
      (void)m_nameLabels[i]->setText(top[i].comm);
      (void)m_cpuLabels[i]->setText(pct);
    } else {
      (void)m_nameLabels[i]->setText("");
      (void)m_cpuLabels[i]->setText("");
    }
  }
}
