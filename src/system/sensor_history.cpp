#include "system/sensor_history.h"

#include <charconv>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <system_error>

namespace {

  // A gap this many intervals long breaks the series (suspend, shell down for a while).
  constexpr int kGapIntervals = 3;
  // Retry cadence after a failed read or an unresolvable spec.
  constexpr auto kRetryDelay = std::chrono::seconds(5);

  std::int64_t nowWallMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch())
        .count();
  }

  std::string trim(std::string s) {
    while (!s.empty() && (s.back() == '\n' || s.back() == ' ' || s.back() == '\t')) {
      s.pop_back();
    }
    return s;
  }

} // namespace

SensorHistory& SensorHistory::instance() {
  static SensorHistory history;
  return history;
}

std::optional<std::filesystem::path> SensorHistory::resolve(const std::string& spec) {
  if (spec.empty()) {
    return std::nullopt;
  }
  if (spec.front() == '/') {
    return std::filesystem::path(spec);
  }
  const auto slash = spec.find('/');
  if (slash == std::string::npos || slash == 0 || slash + 1 == spec.size()) {
    return std::nullopt;
  }
  const std::string name = spec.substr(0, slash);
  const std::string attribute = spec.substr(slash + 1);
  std::error_code ec;
  for (const auto& dir : std::filesystem::directory_iterator("/sys/class/hwmon", ec)) {
    std::ifstream in(dir.path() / "name");
    std::string hwmonName;
    if (in && std::getline(in, hwmonName) && trim(hwmonName) == name) {
      return dir.path() / attribute;
    }
  }
  return std::nullopt;
}

std::optional<double> SensorHistory::readNumber(const std::filesystem::path& path) {
  std::ifstream in(path);
  std::string text;
  if (!in || !std::getline(in, text)) {
    return std::nullopt;
  }
  text = trim(text);
  double value = 0.0;
  const auto* end = text.data() + text.size();
  const auto res = std::from_chars(text.data(), end, value);
  if (res.ec != std::errc{} || res.ptr != end) {
    return std::nullopt;
  }
  return value;
}

std::filesystem::path SensorHistory::mirrorPathFor(const std::string& spec) {
  const char* runtime = std::getenv("XDG_RUNTIME_DIR");
  if (runtime == nullptr || *runtime == '\0') {
    return {};
  }
  std::string file;
  for (const char c : spec) {
    const bool safe =
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_';
    file += safe ? c : '_';
  }
  return std::filesystem::path(runtime) / "noctalia" / "sensor-history" / (file + ".txt");
}

void SensorHistory::load(Entry& entry) {
  if (entry.mirror.empty()) {
    return;
  }
  std::ifstream in(entry.mirror);
  std::string line;
  while (in && std::getline(in, line)) {
    std::istringstream fields(line);
    Sample sample;
    if (fields >> sample.wallMs >> sample.value) {
      entry.samples.push_back(sample);
    }
  }
}

void SensorHistory::save(const Entry& entry) {
  if (entry.mirror.empty()) {
    return;
  }
  std::error_code ec;
  std::filesystem::create_directories(entry.mirror.parent_path(), ec);
  if (ec) {
    return;
  }
  const std::filesystem::path tmp = entry.mirror.string() + ".tmp";
  {
    std::ofstream out(tmp, std::ios::trunc);
    if (!out) {
      return;
    }
    for (const Sample& sample : entry.samples) {
      out << sample.wallMs << ' ' << sample.value << '\n';
    }
    if (!out) {
      return;
    }
  }
  std::filesystem::rename(tmp, entry.mirror, ec); // atomic replace
}

const std::deque<SensorHistory::Sample>& SensorHistory::poll(
    const std::string& spec, std::chrono::milliseconds window, std::chrono::milliseconds interval, double divisor
) {
  auto [it, inserted] = m_entries.try_emplace(spec);
  Entry& entry = it->second;
  if (inserted) {
    entry.mirror = mirrorPathFor(spec);
    load(entry);
  }

  const std::int64_t now = nowWallMs();
  const std::int64_t intervalMs = interval.count();
  const std::int64_t windowMs = window.count();

  const bool due = entry.samples.empty() || now - entry.samples.back().wallMs >= intervalMs;
  const auto steadyNow = std::chrono::steady_clock::now();
  bool changed = false;
  if (due && steadyNow >= entry.nextAttempt) {
    if (!entry.source) {
      entry.source = resolve(spec);
    }
    std::optional<double> raw = entry.source ? readNumber(*entry.source) : std::nullopt;
    if (raw) {
      if (!entry.samples.empty() && now - entry.samples.back().wallMs > kGapIntervals * intervalMs) {
        entry.samples.clear();
      }
      entry.samples.push_back({now, static_cast<float>(*raw / (divisor != 0.0 ? divisor : 1.0))});
      changed = true;
    } else {
      entry.source.reset(); // hwmon renumbered or device gone: re-resolve on the next attempt
      entry.nextAttempt = steadyNow + kRetryDelay;
    }
  }

  while (!entry.samples.empty() && now - entry.samples.front().wallMs > windowMs) {
    entry.samples.pop_front();
    changed = true;
  }
  if (changed) {
    save(entry);
  }
  return entry.samples;
}
