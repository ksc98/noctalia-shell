# Fork notes — native `sysmon_cores` widget

Personal fork of Noctalia v5 (`noctalia-dev/noctalia-shell`, branch `main`). Adds one native bar
widget: **`sysmon_cores`** — a per-core CPU bar chart (one vertical bar per logical core, user time
in primary, system time stacked in error color), height-animated via the `AnimationManager` at
vsync. Replaces the Luau-plugin SVG chart (which was capped ~30fps by image reloads).

Branch: **`kyle`** (our stuff; `main` mirrors upstream). Remotes: `origin` = `ksc98/noctalia-shell`
(your fork — push here: `git push origin kyle`), `upstream` = noctalia-dev (fetch to sync, never push).

## Build / install / run

```sh
cd ~/dev/noctalia-v5
meson compile -C build-release            # fast incremental rebuild
sudo meson install -C build-release       # installs to /usr/local (shadows AUR /usr/bin/noctalia)
pkill -x noctalia; nohup noctalia -d &    # restart the shell on the live niri session
```
- `which noctalia` should be `/usr/local/bin/noctalia`. The niri autostart (`spawn-at-startup
  "noctalia" "-d"`) then runs this fork.
- First-time configure (already done): `meson setup build-release --buildtype=release
  -Dcpp_std=c++23 --prefix=/usr/local`.
- Validate config: `noctalia config validate`. Live reload: `noctalia msg config-reload`.
- For logs, run `noctalia` WITHOUT `-d` to a logfile (`-d` daemonizes via re-exec).

## What the widget needs in config

```toml
[widget.cpu_cores]
type = "sysmon_cores"
bar_width = 3        # px per bar (scales with content scale)
gap = 1              # px between bars
show_system = true   # stack the system-time segment
smoothing = true     # false = snap, no animation
system_color = "error"
```
Then put `cpu_cores` in a bar section (`start`/`center`/`end`).

## Files changed vs upstream (re-apply on rebase)

- `src/system/system_monitor_service.{h,cpp}` — `readPerCoreCpuTotals()`, `perCoreUsagePercent` +
  `perCoreSystemPercent` in `SystemStats`, per-core delta in the sampling loop.
- `src/shell/bar/widgets/sysmon_cores_widget.{h,cpp}` — NEW widget (N `Box` bars, eased phase anim).
- `src/shell/bar/widget_factory.cpp` — include + `if (type == "sysmon_cores")` branch.
- `src/shell/settings/widget_settings_registry.cpp` — `kWidgetTypeSpecs` entry + `widgetSettingSpecs`
  branch (required or `config validate` rejects the keys).
- `meson.build` — add `sysmon_cores_widget.cpp` to `_noctalia_sources`.
- `assets/translations/en.json` — `settings.widgets.types.sysmon-cores` label.

## Rebase on upstream (when v5 / noctalia-git updates)

```sh
git fetch upstream
git checkout main && git merge --ff-only upstream/main && git push origin main  # mirror upstream -> fork
git checkout kyle && git rebase upstream/main   # re-apply our commits; fix conflicts in the files listed
git push origin kyle --force-with-lease
meson compile -C build-release && sudo meson install -C build-release
```
Cleanest long-term: upstream the widget as a PR to noctalia-dev so there's no fork to maintain.
