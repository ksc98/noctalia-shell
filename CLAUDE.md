# noctalia (personal fork)

Personal fork of Noctalia v5 (`noctalia-dev/noctalia`). Two kinds of customization live here:

1. **Native C++ widgets** compiled into the shell (e.g. `sysmon_cores`) — installed via meson.
2. **Luau plugins** under `plugins/noctalia-sysmon-extras/` (coolant / cpu_watt / gpu_watt / ram / ecoflow /
   cpu_cores / cpu_panel) — loaded at runtime, no build step.

Branch `kyle` = our stuff; `main` mirrors upstream. Remotes: `origin` = `ksc98/noctalia-shell` (fork),
`upstream` = `noctalia-dev` (fetch only). See `FORK-NOTES*` for the native-widget specifics.

## Making changes take effect

### Luau plugin edits (plugins/)

noctalia loads local dev plugins from a **path source**, configured in `~/.config/noctalia/config.toml`:

```toml
[[plugins.source]]
name = "kyle-dev"
kind = "path"
location = "~/.local/share/noctalia-dev-plugins"
```

That dir's `sysmon-extras` entry is a **symlink to this repo's `plugins/noctalia-sysmon-extras/`**, so the
repo is the single source of truth (don't replace it with a copy).

**`require` in entry scripts resolves from the plugin ROOT, not the requiring file's dir** — write
`require("./widgets/sensors_json.luau")`, never `require("./sensors_json.luau")` from inside `widgets/`.
(Modules loaded via require do resolve file-relative; only entry chunks use the root.)

- **Widget `.luau` edits hot-reload live.** The shell watches every loaded script and its `require`d
  modules; an in-place write re-runs that widget's VM (log: `[plugin-widget] hot reload: reloaded ...`).
  The reload resets widget state, so it briefly shows `—` until its next poll.
- **Everything else needs `just plugin`** (symlink check + full restart): `plugin.toml` manifest changes,
  translations, added/removed entries (`PluginManager::refresh()` early-returns unless the `[plugins]`
  config section changed; `noctalia msg config-reload` never reloads plugin VMs), and files **replaced
  rather than written in place** — git checkout/rebase breaks the inotify watch, so no hot reload fires.

### Native C++ widget edits (src/) — meson build + install + restart

```sh
just build release && sudo "$(mise which just)" install release && just restart
```

(`just install` shadows the AUR `/usr/bin/noctalia` at `/usr/local/bin/noctalia`; needs sudo.)

### Verifying a change is live

The bar is a niri/Wayland surface — screenshot it with grim and read the image:

```sh
grim -g "1200,0 700x44" /tmp/bar.png   # center region (clock/coolant/watt); adjust to your output
```

## Upstream PRs

Cut PR branches from `upstream/main` in a worktree (never from `kyle`) and run what CI runs before every
push: `clang-format --dry-run -Werror` on the changed files, `just build`, `just test debug --print-errorlogs`
and `just lint`. `just lint` is clang-tidy with `-warnings-as-errors=*` over all of `src/`, and CI's Build
job fails on any diagnostic (e.g. `modernize-use-ranges`), so build + test + format passing is not enough.
Keep the `.github/PULL_REQUEST_TEMPLATE.md` headings and checklist; a bot re-drafts PRs missing them.

## Code map

- `plugins/noctalia-sysmon-extras/` — the Luau plugin (symlinked into the path-source dir by `just plugin`).
  - `widgets/sensors_json.luau` — shared async `sensors -j` chip/label/value reader (used by coolant + watt).
  - `widgets/coolant.luau` — coolant temp, threshold-coloured. Fast path reads the hwmon sysfs attribute
    directly (~1ms vs ~150ms for a full `sensors -j` scan plus a process spawn), `sensors -j` fallback.
  - `widgets/cpu_watt.luau` — CPU usage % + package power ("3% · 42W") via `noctalia.readFileAsync` on
    /proc/stat and the RAPL energy counter (AMD Zen has no power in `sensors -j`); no shell spawns.
    Needs `energy_uj` user-readable — see `contrib/99-rapl-readable.rules` (udev rule; installed to
    `/etc/udev/rules.d/`, re-applies on boot). Shows `perm?` if the rule is missing. No icon:
    it sits right after the cpu_cores chart. The label sits in a `minWidth` row (`ui.label` ignores
    `width`) and is coloured by the power thresholds.
  - `widgets/gpu_watt.luau` — GPU utilization % + power ("33% · 57W") via `nvidia-smi
    power.draw,utilization.gpu` (the discrete card; not in `sensors -j`). Icon: a graphics card (ui.*
    nodes via `barWidget.render`: flush bracket, board, gold fingers) whose one fan is
    a `ui.ring` gauge with a `tertiary` arc sweeping with utilization; label in a `minWidth` row like cpu_watt.
  - `widgets/ram.luau` — RAM % as a `ui.ring` donut via `barWidget.render`, + "NN%" label coloured by
    the warn/crit thresholds; data from `noctalia.systemStats().ram`.
  - `widgets/ecoflow.luau` — EcoFlow power station ("󰂄 100% 󱐋462W 󰚥265W"), last in the bar's center
    group, right of `net_up`. Holds one `noctalia.httpStream` on the homelab service's SSE endpoint
    (`https://ecoflow.kych.cloud/v1/stream`, setting `url`): no spawns, no polling. The 1 s update tick
    only re-checks the age, restarts a stream silent for 25 s (keepalives come every 15 s) and
    reconnects with backoff (1 s doubling to 60 s). Data age counts from the last SSE event or
    keepalive; a connection that ends before sending one SSE line drops the reading, so an
    unreachable service hides at once. Display rules and glyphs mirror tmux-status-rs
    `src/segments/ecoflow/mod.rs`; hidden (`barWidget.setVisible(false)`, which collapses the slot)
    when plugged in with nothing flowing, stale, unreachable or older than `maxAgeSeconds`. Colour by
    SoC: <20 `error`, <50 `secondary`, <80 `on_surface`, else `tertiary`. Tooltip: limit/band,
    override, cell temp, time to full/empty, data age. To exercise the hide paths, point the
    instance's `url` at a local SSE server (a dead port hides it).
  - `widgets/watt.luau` — generic `sensors -j` watt readout (chip/label/value); unused on this box (kept
    for any `power*_input` sensor, e.g. the amdgpu iGPU PPT).
  - `widgets/cpu_cores.luau` — per-core load block sparkline.
  - `desktop/cpu_panel.luau` — desktop per-core bars + CPU/RAM history graph.
  - `plugin.toml` — manifest: `plugin_api = 55` (host's current level; `clip` on rows/columns needs ≥ 52), widget ids + their config `[[widget.setting]]`
    schema. Setting labels/descriptions are translation keys (`label_key`/`description_key`) resolved
    against `translations/en.json`; literal `label`/`description` are rejected by the manifest parser.
- `src/scripting/` — plugin host (Luau VM, bindings, manager, registry). Path sources are read directly
  from disk; only git sources get "materialized" under the state dir.
- `src/shell/bar/widgets/sysmon_cores_widget.{h,cpp}` — native per-core CPU bar chart, plus the optional
  `temp_line_*` overlay: a temperature line (coolant on this box) over a sliding window, x = time.
- `src/system/sensor_history.{h,cpp}` — process-lifetime hwmon sample history for that line (outlives
  widget rebuilds; mirrored to `$XDG_RUNTIME_DIR/noctalia/sensor-history/` so restarts keep the window).
- `src/system/system_monitor_service.{h,cpp}` — native per-core CPU sampling (`sysmon_cores`).
- `src/util/file_utils.h` — data/state dir resolution (`~/.local/share/noctalia`, etc.).
- `justfile` — `configure/build/install` (native, meson) + `link-plugins/restart/plugin` (Luau plugins).

## Runtime config (not in this repo)

- `~/.config/noctalia/config.toml` — widget instances, bar layout, `[[plugins.source]]` entries. Not
  chezmoi-managed (`.chezmoiignore` excludes `.config/noctalia/**`): edit the deployed file, then
  `noctalia config validate`.
- Widget instance config (e.g. the coolant sensor chip/label/key) lives in config.toml under
  `[widget.<name>]`, NOT in the plugin. Current coolant sensor: `quadro-hid-3` / `Sensor 3` / `temp3_input`.
