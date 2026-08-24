set positional-arguments

mode := "debug"
build-dir := "build-" + mode
prefix := "/usr/local"
cpp-std := "c++23"

default:
    @just --list

configure m=mode install_prefix=prefix:
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--buildtype={{ if m == "release" { "release" } else { "debug" } }} -Dcpp_std={{cpp-std}} -Dtests=auto)
    [[ "{{m}}" == "release" ]] && args+=(-Db_lto=true)
    [[ "{{m}}" == "asan"    ]] && args+=(-Db_sanitize=address,undefined)
    if [[ -d "build-{{m}}" ]]; then
        meson setup "build-{{m}}" "${args[@]}" --prefix "{{install_prefix}}" --reconfigure
    else
        meson setup "build-{{m}}" "${args[@]}" --prefix "{{install_prefix}}"
    fi
    ln -sfn "build-{{m}}/compile_commands.json" compile_commands.json

build m=mode: (_ensure-configured m)
    meson compile -C build-{{m}} noctalia

_ensure-configured m=mode:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f "build-{{m}}/build.ninja" ]]; then
        just configure {{m}}
        exit 0
    fi
    configure_output="$(meson configure "build-{{m}}")"
    current_cpp_std="$(awk '$1 == "cpp_std" { print $2; found=1 } END { if (!found) exit 1 }' <<<"$configure_output")"
    current_tests="$(awk '$1 == "tests" { print $2; found=1 } END { if (!found) exit 1 }' <<<"$configure_output")"
    args=()
    [[ "$current_cpp_std" != "{{cpp-std}}" ]] && args+=(-Dcpp_std={{cpp-std}})
    [[ "$current_tests" != "auto" ]] && args+=(-Dtests=auto)
    if (( ${#args[@]} > 0 )); then
        meson configure "build-{{m}}" "${args[@]}"
    fi

run m=mode: (build m)
    ./build-{{m}}/noctalia

# Build and run the unit tests, enabling their targets when auto mode omits them.
test m=mode *args: (_ensure-configured m)
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{m}}" == "release" || "{{m}}" == "asan" ]]; then
        meson setup "build-{{m}}" -Dtests=enabled --reconfigure >/dev/null
    fi
    meson test -C build-{{m}} {{args}}

# Regressions for the GitHub workflow scripts. Pure Python, builds nothing.
test-workflows:
    python3 -m unittest discover -s .github/workflows/scripts -p 'test_*.py'

install m:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -x "build-{{m}}/noctalia" ]]; then
        echo "error: build-{{m}}/noctalia is missing; run 'just build {{m}}' before installing" >&2
        exit 1
    fi
    meson install --no-rebuild -C build-{{m}}

uninstall m:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f "build-{{m}}/build.ninja" ]]; then
        echo "error: build-{{m}} is missing or was not configured with the Ninja backend; nothing to uninstall" >&2
        exit 1
    fi
    ninja -C build-{{m}} uninstall

format:
    find src tests \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 clang-format -i
    find src tests \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 grep -ZlP '\s+$' | xargs -0 -r sed -i 's/[[:space:]]*$//'

_clang_tidy m=mode *args:
    #!/usr/bin/env bash
    set -euo pipefail
    src_root="$(realpath src)"
    # compile_commands.json stores build-relative paths, so clang-tidy emits header
    # diagnostics as ../src/...; the header-filter must match that form (an absolute
    # ^${src_root} anchor never matches, silently dropping every header diagnostic).
    # ../src/ also excludes vendored third_party/*/src/* headers.
    run-clang-tidy -quiet -use-color -p "build-{{m}}" -j "$(nproc)" -header-filter='\.\./src/.*' {{args}} "^${src_root}/.*"

lint m=mode: (_ensure-configured m)
    just _clang_tidy {{m}} '-warnings-as-errors=*'

fix m=mode: (_ensure-configured m)
    just _clang_tidy {{m}} -fix
    just format

clean m=mode:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -L compile_commands.json && "$(readlink compile_commands.json)" == "build-{{m}}/compile_commands.json" ]]; then
        rm -f compile_commands.json
    fi
    rm -rf build-{{m}}

rebuild m=mode: (clean m) (build m)

# ── Luau plugins (plugins/noctalia-sysmon-extras: coolant / watt / cpu_cores / cpu_panel) ──
# noctalia loads local dev plugins from a path-source dir (config.toml [[plugins.source]]
# kind=path). We symlink the in-repo plugin there so repo == live with zero copy-drift.
plugins-src  := justfile_directory() / "plugins/noctalia-sysmon-extras"
plugins-link := env_var('HOME') / ".local/share/noctalia-dev-plugins/sysmon-extras"

# Ensure the path-source dir is a symlink to the in-repo plugin (idempotent, self-healing).
link-plugins:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$(dirname '{{plugins-link}}')"
    if [[ -L '{{plugins-link}}' && "$(readlink -f '{{plugins-link}}')" == "$(readlink -f '{{plugins-src}}')" ]]; then
        echo "plugin symlink ok: {{plugins-link}} -> {{plugins-src}}"
    else
        rm -rf '{{plugins-link}}'
        ln -s '{{plugins-src}}' '{{plugins-link}}'
        echo "linked {{plugins-link}} -> {{plugins-src}}"
    fi

# Restart the running noctalia shell. Required to load plugin Luau changes:
# `noctalia msg config-reload` does NOT reload plugin VMs when only plugin files changed.
restart:
    #!/usr/bin/env bash
    set -euo pipefail
    # A stale HYPRLAND_INSTANCE_SIGNATURE (shell older than the compositor) makes the new
    # instance silently fall back from the hyprland IPC backend to ext-workspace.
    hypr_dir="/run/user/$(id -u)/hypr"
    if [[ -d "$hypr_dir" ]]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$hypr_dir" | head -1)"
    fi
    pkill -x noctalia || true
    # Graceful shutdown takes >1s; starting too early exits "noctalia is already running".
    for _ in $(seq 1 40); do pgrep -x noctalia >/dev/null || break; sleep 0.25; done
    setsid -f nohup noctalia -d >/dev/null 2>&1
    sleep 1
    if pgrep -x noctalia >/dev/null; then echo "noctalia restarted (pid $(pgrep -x noctalia))"; else echo "noctalia failed to start" >&2; exit 1; fi

# Make Luau plugin edits take effect: ensure the symlink, then restart the shell.
# Run this after editing anything under plugins/.
plugin: link-plugins restart
