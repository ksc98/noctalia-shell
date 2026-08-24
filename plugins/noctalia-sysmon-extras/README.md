# SystemMonitor Extras (Noctalia v5 plugin)

A Luau plugin that ports the **gap** between Noctalia v5's native sysmon and the v4
`SystemMonitor` fork. v5 already covers CPU%, CPU temp, GPU temp/usage/VRAM, RAM, swap,
network, and disk natively (use the built-in sysmon widget for those). This plugin adds only
what v5 lacks:

| Widget | Surface | What it does |
|---|---|---|
| `coolant` | bar | Coolant temp from `sensors -j`, keyed by chip/label/value (v4 parity), threshold-coloured |
| `cpu_watt` | bar | CPU package power (W) from the RAPL energy counter — for AMD Zen, which has no power channel in `sensors -j`. Needs a udev rule (below) |
| `gpu_watt` | bar | GPU power (W) from `nvidia-smi --query-gpu=power.draw` |
| `watt` | bar | Generic power (W) from `sensors -j`, keyed by chip/label/value. Use for any sensor that exposes `power*_input` (e.g. an amdgpu iGPU's PPT) |
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
coolantSensorLabel = "Sensor 2"
coolantSensorValueKey = "temp2_input"

[widget.cpu_watt]
type = "kyle/sysmon-extras:cpu_watt"
glyph = "cpu"

[widget.gpu_watt]
type = "kyle/sysmon-extras:gpu_watt"
glyph = "bolt"
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

## What did NOT port (the gap to revisit after v5 is live)

1. **The per-core stacked bar chart *inside the bar*.** v5's bar-widget API is text/glyph/
   colour/tooltip only — there is no drawing surface. Mitigations shipped: the block sparkline
   in the bar, and the `cpu_panel` desktop widget for the real visual. A true in-bar chart would
   need either a native C++ bar widget or an upstream change exposing `ui.graph` to bar widgets.
2. **The exact user-vs-system stacked overlay per core.** The bar sparkline encodes total load
   per core only; the desktop bars show total load (system-time tinting was not reproduced —
   `/proc/stat` split is available, but the progress control is single-fill). Candidate for the
   desktop panel in the next pass.
3. **RAM history line *overlaid on the per-core bars*** as drawn in v4 — here it's a separate
   `ui.graph` series (`values2`) in the desktop panel, not overlaid on the core bars.
4. **Everything is unrun.** No v5 runtime existed to execute against, so none of this is
   behaviourally verified (see below).

## Not yet verified (do these on the live pass)

- `noctalia.readFile` reads absolute `/proc/*` paths (assumed; the binding is a general file
  reader). If it's sandboxed to the plugin dir, swap to `noctalia.runAsync("cat /proc/stat")`.
- `ui.graph` value domain — series are normalised to `0..1` here; confirm the graph expects
  fractions (not 0..100) and that `values2`/`color2` render as a second line.
- `barWidget.setColor` role tokens (`error`/`tertiary`/`on_surface`) recolour as expected.
- `setText` inside a `runAsync` callback flushes; if not, the cache-and-paint pattern already
  used means the value still lands on the next `update()` tick.
- Glyph names (`water_drop`, `bolt`) exist in v5's glyph set; substitute if not.

## Source notes

Built against `upstream/main` (`noctalia-dev/noctalia-shell`, the v5 rewrite):
`src/scripting/plugin_bindings.cpp` (bar/desktop API), `src/scripting/luau_host.cpp`
(`noctalia.*`), `src/scripting/ui_prelude.h` + `src/ui/ui_tree_reconciler.cpp` (desktop `ui.*`
props), `src/scripting/plugin_manifest.cpp` (manifest schema), `src/ui/palette.h` (colour
role tokens).
