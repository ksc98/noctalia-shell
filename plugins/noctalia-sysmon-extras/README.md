# SystemMonitor Extras (Noctalia v5 plugin)

A Luau plugin that ports the **gap** between Noctalia v5's native sysmon and the v4
`SystemMonitor` fork. v5 already covers CPU%, CPU temp, GPU temp/usage/VRAM, RAM, swap,
network, and disk natively (use the built-in sysmon widget for those). This plugin adds only
what v5 lacks:

| Widget | Surface | What it does |
|---|---|---|
| `coolant` | bar | Coolant temp from `sensors -j`, keyed by chip/label/value (v4 parity), threshold-coloured |
| `cpu_watt` | bar | CPU usage % (`/proc/stat`) + package power (W) from the RAPL energy counter — for AMD Zen, which has no power channel in `sensors -j`. Needs a udev rule (below). Icon: a CPU package whose 3x3 cell grid lights up as a usage meter |
| `gpu_watt` | bar | GPU utilization % + power (W) from `nvidia-smi --query-gpu=power.draw,utilization.gpu`. Icon: a graphics card whose fan is a ring gauge sweeping with utilization |
| `watt` | bar | Generic power (W) from `sensors -j`, keyed by chip/label/value. Use for any sensor that exposes `power*_input` (e.g. an amdgpu iGPU's PPT) |
| `ram` | bar | RAM use as a memory-stick icon whose chips fill as a level meter + `NN%`, from `noctalia.systemStats()`; the native sysmon only offers a linear gauge |
| `ecoflow` | bar | EcoFlow power station: battery % (charging glyph while charging), wall-in and load-out watts, from the homelab ecoflow service's SSE stream via `noctalia.httpStream`; hidden while idle on AC, stale or unreachable; details in the tooltip |
| `cpu_cores` | bar | Per-core load as a Unicode block sparkline (`▁▂▃▄▅▆▇█`), exact %s in the tooltip |
| `cpu_panel` | desktop | Per-core bars + a CPU/RAM history graph (the RAM overlay) |

## Install

noctalia loads this plugin from a **path source** (`config.toml [[plugins.source]] kind = "path"`,
location `~/.local/share/noctalia-dev-plugins`). That dir's `sysmon-extras` entry is a **symlink to
this repo dir**, so the repo is the single source of truth. From the repo root, `just plugin` ensures
the symlink and restarts the shell. Then enable the plugin and add the widgets to a bar section.

This machine's config (`~/.config/noctalia/config.toml`):

```toml
[widget.coolant]
type = "kyle/sysmon-extras:coolant"
coolantSensorChip = "quadro-hid-3"   # prefix-matched against the `sensors -j` chip key
coolantSensorLabel = "Sensor 3"
coolantSensorValueKey = "temp3_input"

[widget.cpu_watt]
type = "kyle/sysmon-extras:cpu_watt"
pollIntervalMs = 1000

[widget.gpu_watt]
type = "kyle/sysmon-extras:gpu_watt"
pollIntervalMs = 1000

[widget.ecoflow]
type = "kyle/sysmon-extras:ecoflow"   # url defaults to https://ecoflow.kych.cloud/v1/stream
```

### cpu_watt: RAPL must be user-readable

`cpu_watt` differentiates the powercap energy counter (`W = ΔµJ / Δs`), but `energy_uj` is root-only by
default (the Platypus side-channel mitigation), so the widget shows `perm?` until a udev rule relaxes it.
Install the bundled rule once:

```sh
sudo cp contrib/99-rapl-readable.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap --action=add
sudo chmod a+r /sys/class/powercap/intel-rapl:*/energy_uj   # apply now, no reboot
```

(The rule re-applies on every boot. `intel-rapl` is the powercap driver name on AMD too — RAPL is not
Intel-only.)

## What maps cleanly

- **Coolant temp / watts** — full v4 parity. Same `sensors -j` source, same three config keys.
- **Per-core CPU** — present as a compact in-bar sparkline + exact tooltip, plus a richer
  desktop panel (bars + history graph). Sampled from `/proc/stat` via `noctalia.readFile`.

## Gaps vs v4

1. **The per-core stacked chart in the bar** is the fork's native C++ `sysmon_cores` widget
   (user/system stacked per core, optional coolant-temp line over a sliding window; see
   `FORK-NOTES.md`), not this plugin. The plugin's `cpu_cores` block sparkline is the fallback for
   unpatched builds. Plugin bar widgets can draw shapes via `barWidget.render` (`ram`,
   `cpu_watt` and `gpu_watt` use it), but the per-frame bar easing stays native.
2. **RAM history line overlaid on the per-core bars** (as in v4) is not reproduced: RAM history
   is a separate `ui.graph` series (`values2`) in the `cpu_panel` desktop widget, and the native
   chart's overlay line is a temperature instead.
3. **`cpu_panel` is not configured on this box**, so its desktop `ui.graph` rendering (0..1
   series, `values2`/`color2` as a second line) is not exercised by the live setup.

## Source notes

Built against `upstream/main` (`noctalia-dev/noctalia-shell`, the v5 rewrite):
`src/scripting/plugin_bindings.cpp` (bar/desktop API), `src/scripting/luau_host.cpp`
(`noctalia.*`), `src/scripting/ui_prelude.h` + `src/ui/ui_tree_reconciler.cpp` (desktop `ui.*`
props), `src/scripting/plugin_manifest.cpp` (manifest schema), `src/ui/palette.h` (colour
role tokens).
