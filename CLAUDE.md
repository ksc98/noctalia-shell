# noctalia (personal fork)

Personal fork of Noctalia v5 (`noctalia-dev/noctalia-shell`). Two kinds of customization live here:

1. **Native C++ widgets** compiled into the shell (e.g. `sysmon_cores`) — installed via meson.
2. **Luau plugins** under `plugins/noctalia-sysmon-extras/` (coolant / watt / cpu_cores / cpu_panel) —
   loaded at runtime, no build step.

Branch `kyle` = our stuff; `main` mirrors upstream. Remotes: `origin` = `ksc98/noctalia-shell` (fork),
`upstream` = `noctalia-dev` (fetch only). See `FORK-NOTES*` for the native-widget specifics.

## Making changes take effect

### Luau plugin edits (plugins/) — ALWAYS run `just plugin` after editing

noctalia loads local dev plugins from a **path source**, configured in `~/.config/noctalia/config.toml`:

```toml
[[plugins.source]]
name = "kyle-dev"
kind = "path"
location = "/home/kchang/.local/share/noctalia-dev-plugins"
```

That dir's `sysmon-extras` entry is a **symlink to this repo's `plugins/noctalia-sysmon-extras/`**, so the
repo is the single source of truth (it used to be a stale *copy*, which silently swallowed edits — don't
recreate that). After editing any plugin file:

```sh
just plugin     # ensures the symlink + restarts noctalia
```

A full **restart** is required for plugin code — `noctalia msg config-reload` does NOT reload plugin Luau
VMs when only plugin files changed (`PluginManager::refresh()` early-returns unless the `[plugins]` config
section itself changed). `just plugin` handles this. Don't rely on config-reload for plugin edits.

### Native C++ widget edits (src/) — meson build + install + restart

```sh
just build release && sudo just install release && just restart
```

(`just install` shadows the AUR `/usr/bin/noctalia` at `/usr/local/bin/noctalia`; needs sudo.)

### Verifying a change is live

The bar is a niri/Wayland surface — screenshot it with grim and read the image:

```sh
grim -g "1200,0 700x44" /tmp/bar.png   # center region (clock/coolant/watt); adjust to your output
```

## Code map

- `plugins/noctalia-sysmon-extras/` — the Luau plugin (symlinked into the path-source dir by `just plugin`).
  - `widgets/coolant.luau` — coolant temp from `sensors -j`, keyed by chip/label/value; threshold-coloured.
  - `widgets/cpu_watt.luau` — CPU usage % + package power ("3% · 42W") via /proc/stat and the RAPL energy
    counter (AMD Zen has no power in `sensors -j`). Needs `energy_uj` user-readable — see
    `contrib/99-rapl-readable.rules` (udev rule; installed to `/etc/udev/rules.d/`, re-applies on boot).
    Shows `perm?` if the rule is missing.
  - `widgets/gpu_watt.luau` — GPU utilization % + power ("33% · 57W") via `nvidia-smi
    power.draw,utilization.gpu` (the discrete card; not in `sensors -j`).
  - `widgets/watt.luau` — generic `sensors -j` watt readout (chip/label/value); unused on this box (kept
    for any `power*_input` sensor, e.g. the amdgpu iGPU PPT).
  - `widgets/cpu_cores.luau` — per-core load block sparkline.
  - `desktop/cpu_panel.luau` — desktop per-core bars + CPU/RAM history graph.
  - `plugin.toml` — manifest: widget ids + their config `[[widget.setting]]` schema.
- `src/scripting/` — plugin host (Luau VM, bindings, manager, registry). Path sources are read directly
  from disk; only git sources get "materialized" under the state dir.
- `src/system/system_monitor_service.{h,cpp}` — native per-core CPU sampling (`sysmon_cores`).
- `src/util/file_utils.h` — data/state dir resolution (`~/.local/share/noctalia`, etc.).
- `justfile` — `configure/build/install` (native, meson) + `link-plugins/restart/plugin` (Luau plugins).

## Runtime config (not in this repo)

- `~/.config/noctalia/config.toml` — widget instances, bar layout, `[[plugins.source]]` entries.
- Widget instance config (e.g. the coolant sensor chip/label/key) lives in config.toml under
  `[widget.<name>]`, NOT in the plugin. Current coolant sensor: `quadro-hid-3` / `Sensor 2` / `temp2_input`.
