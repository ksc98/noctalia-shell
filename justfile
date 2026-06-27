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
    args=(--buildtype={{ if m == "release" { "release" } else { "debug" } }} -Dcpp_std={{cpp-std}})
    [[ "{{m}}" == "release" ]] && args+=(-Db_lto=true)
    [[ "{{m}}" == "asan"    ]] && args+=(-Db_sanitize=address,undefined)
    if [[ -d "build-{{m}}" ]]; then
        meson setup "build-{{m}}" "${args[@]}" --prefix "{{install_prefix}}" --reconfigure
    else
        meson setup "build-{{m}}" "${args[@]}" --prefix "{{install_prefix}}"
    fi
    ln -sfn "build-{{m}}/compile_commands.json" compile_commands.json

build m=mode: (_ensure-configured m)
    meson compile -C build-{{m}}

_ensure-configured m=mode:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f "build-{{m}}/build.ninja" ]]; then
        just configure {{m}}
        exit 0
    fi
    current_cpp_std="$(meson configure "build-{{m}}" | awk '$1 == "cpp_std" { print $2; exit }')"
    if [[ "$current_cpp_std" != "{{cpp-std}}" ]]; then
        meson configure "build-{{m}}" -Dcpp_std={{cpp-std}}
    fi

run m=mode: (build m)
    ./build-{{m}}/noctalia

# Build (forcing tests on, even for release) and run the unit tests.
test m=mode *args: (_ensure-configured m)
    #!/usr/bin/env bash
    set -euo pipefail
    # Plain reconfigure first so build dirs predating the 'tests' option learn it,
    # then force it on (covers release, where it defaults off).
    meson setup "build-{{m}}" --reconfigure >/dev/null
    meson setup "build-{{m}}" -Dtests=enabled --reconfigure >/dev/null
    meson test -C build-{{m}} {{args}}

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
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 clang-format -i
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 grep -ZlP '\s+$' | xargs -0 -r sed -i 's/[[:space:]]*$//'

_clang_tidy m=mode *args:
    #!/usr/bin/env bash
    set -euo pipefail
    src_root="$(realpath src)"
    # meson emits one compile_commands.json entry per (file, target); sources shared with
    # unit-test executables appear many times (core/log.cpp 14x), so clang-tidy re-lints
    # them once per entry. Dedupe to one entry per file (preferring the main app target)
    # so each file is linted once — faster, and clang-tidy's per-file progress spam
    # disappears (it only prints that when a file has multiple compile commands).
    cdb_dir="$(mktemp -d)"
    trap 'rm -rf "$cdb_dir"' EXIT
    # sort main-app (noctalia.p) entries first, then keep the first entry per file
    python3 -c "import json, sys; e = sorted(json.load(open(sys.argv[1])), key=lambda x: not x.get('output', '').startswith('noctalia.p/')); b = {}; [b.setdefault(x['file'], x) for x in e]; json.dump(list(b.values()), open(sys.argv[2], 'w'))" "build-{{m}}/compile_commands.json" "$cdb_dir/compile_commands.json"
    # compile_commands.json stores build-relative paths, so clang-tidy emits header
    # diagnostics as ../src/...; the header-filter must match that form (an absolute
    # ^${src_root} anchor never matches, silently dropping every header diagnostic).
    # ../src/ also excludes vendored third_party/*/src/* headers.
    run-clang-tidy -quiet -use-color -p "$cdb_dir" -j "$(nproc)" -header-filter='\.\./src/.*' {{args}} "^${src_root}/.*"

lint m=mode: (configure m)
    just _clang_tidy {{m}} '-warnings-as-errors=*'

fix m=mode: (configure m)
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
    pkill -x noctalia || true
    sleep 1
    nohup noctalia -d >/dev/null 2>&1 &
    sleep 1
    if pgrep -x noctalia >/dev/null; then echo "noctalia restarted (pid $(pgrep -x noctalia))"; else echo "noctalia failed to start" >&2; exit 1; fi

# Make Luau plugin edits take effect: ensure the symlink, then restart the shell.
# Run this after editing anything under plugins/.
plugin: link-plugins restart
