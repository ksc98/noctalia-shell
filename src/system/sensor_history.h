#pragma once

#include <chrono>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <optional>
#include <string>
#include <unordered_map>

// Process-lifetime rolling history of single hwmon readings, keyed by sensor spec.
//
// Bar widgets are rebuilt on every config change and each output's bar has its own instance,
// so a widget-owned buffer would lose the window on every settings tweak. This store outlives
// them and is mirrored to $XDG_RUNTIME_DIR, so a shell restart within the session keeps the
// window too. Samples carry wall-clock stamps: eviction is by age, and a gap longer than a few
// intervals (suspend, shell down) clears the series instead of drawing stale data as
// contiguous. hwmon reads are cached sysfs attributes (~1ms), done on the caller's thread.
class SensorHistory {
public:
  struct Sample {
    std::int64_t wallMs = 0;
    float value = 0.0F;
  };

  static SensorHistory& instance();

  // Takes a new sample of `spec` when `interval` has elapsed since the last one, evicts samples
  // older than `window`, and returns the series (oldest first).
  //
  // `spec` is either an absolute file path or "<hwmon name>/<attribute>" (e.g. "quadro/temp3_input"),
  // resolved by scanning /sys/class/hwmon/*/name, so it survives hwmonN renumbering across boots.
  // `divisor` converts the raw integer (hwmon temps are millidegrees: 1000).
  const std::deque<Sample>&
  poll(const std::string& spec, std::chrono::milliseconds window, std::chrono::milliseconds interval, double divisor);

private:
  struct Entry {
    std::optional<std::filesystem::path> source;
    std::filesystem::path mirror;
    std::deque<Sample> samples;
    std::chrono::steady_clock::time_point nextAttempt{};
  };

  SensorHistory() = default;

  static std::optional<std::filesystem::path> resolve(const std::string& spec);
  static std::optional<double> readNumber(const std::filesystem::path& path);
  static std::filesystem::path mirrorPathFor(const std::string& spec);
  static void load(Entry& entry);
  static void save(const Entry& entry);

  std::unordered_map<std::string, Entry> m_entries;
};
