#!/bin/bash
# Extra snapshots not covered by backup-run sync alone.
# Env: BACKUP_SUDO=1 enables sudo-only steps (set by backup -s).
set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

BACKUP_ROOT="$(resolve_backup_root)"
PKG="$BACKUP_ROOT/packages"
MACOS="$BACKUP_ROOT/configs/macos-system"
CHROME="$BACKUP_ROOT/configs/chrome/bookmarks"
CURSOR="$BACKUP_ROOT/configs/cursor"
VSCODE="$BACKUP_ROOT/configs/vscode"
RAYCAST="$BACKUP_ROOT/configs/raycast"

write_if_cmd() {
    local label=$1 cmd=$2 dest=$3
    if command -v "${cmd%% *}" >/dev/null 2>&1; then
        eval "$cmd" >"$dest" 2>/dev/null || true
        if [[ -s "$dest" ]]; then
            log_ok "$label → $(basename "$dest")"
        else
            rm -f "$dest"
            log_skip "$label (empty output)"
        fi
    else
        log_skip "$label ($cmd not found)"
    fi
}

copy_if_file() {
    local src=$1 dest=$2 label=$3
    if [[ -f "$src" && ! -L "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        log_ok "$label"
    elif [[ -L "$src" ]]; then
        log_skip "$label (symlink — source of truth elsewhere)"
    else
        log_skip "$label (missing)"
    fi
}

mkdir -p "$PKG" "$MACOS" "$CHROME" "$CURSOR/cli" "$VSCODE" "$RAYCAST"

echo "🔄 backup_extras: package manifests"
write_if_cmd "pnpm globals" "pnpm list -g --depth 0" "$PKG/pnpm_list.txt"
write_if_cmd "mise tools" "mise ls" "$PKG/mise_list.txt"
write_if_cmd "asdf versions" "asdf current 2>&1; asdf list 2>&1" "$PKG/asdf_current.txt"
write_if_cmd "pipx apps" "pipx list --short" "$PKG/pipx_list.txt"
write_if_cmd "uv tools" "uv tool list" "$PKG/uv_tools_list.txt"
write_if_cmd "fnm node versions" "fnm list" "$PKG/fnm_list.txt"

FNM_DEFAULT_BIN="$HOME/.local/share/fnm/aliases/default/bin"
if [[ -x "$FNM_DEFAULT_BIN/npm" ]]; then
    if PATH="$FNM_DEFAULT_BIN:$PATH" npm ls -g --depth 0 >"$PKG/fnm_npm_globals.txt" 2>/dev/null \
        && [[ -s "$PKG/fnm_npm_globals.txt" ]]; then
        log_ok "fnm npm globals → fnm_npm_globals.txt"
    else
        rm -f "$PKG/fnm_npm_globals.txt"
        log_skip "fnm npm globals (empty output)"
    fi
fi

if [[ -d "$HOME/go/bin" ]]; then
    if ls -1 "$HOME/go/bin" >"$PKG/go_bin_list.txt" 2>/dev/null && [[ -s "$PKG/go_bin_list.txt" ]]; then
        log_ok "go/bin → go_bin_list.txt"
    else
        rm -f "$PKG/go_bin_list.txt"
        log_skip "go/bin (empty)"
    fi
fi

if [[ -d "$HOME/.local/bin" ]]; then
    : >"$PKG/local_bin_list.txt"
    for entry in "$HOME/.local/bin"/*; do
        [[ -e "$entry" ]] || continue
        rp=$(readlink -f "$entry" 2>/dev/null || printf '%s' "$entry")
        case "$rp" in *pipx*|*uv/tools*) continue ;; esac
        printf '%s -> %s\n' "$(basename "$entry")" "$rp" >>"$PKG/local_bin_list.txt"
    done
    if [[ -s "$PKG/local_bin_list.txt" ]]; then
        log_ok "local bin (non-pipx/uv) → local_bin_list.txt"
    else
        rm -f "$PKG/local_bin_list.txt"
        log_skip "local bin (only pipx/uv entries)"
    fi
fi

echo "🔄 backup_extras: Cursor + VS Code extensions"
if command -v cursor >/dev/null 2>&1; then
    cursor --list-extensions --show-versions >"$CURSOR/extensions.list" 2>/dev/null || true
    if [[ -s "$CURSOR/extensions.list" ]]; then
        log_ok "cursor extensions.list"
    else
        rm -f "$CURSOR/extensions.list"
        log_skip "cursor extensions.list"
    fi
else
    log_skip "cursor CLI"
fi
copy_if_file "$HOME/.cursor/argv.json" "$CURSOR/cli/argv.json" "cursor argv.json"
copy_if_file "$HOME/.cursor/sandbox.json" "$CURSOR/cli/sandbox.json" "cursor sandbox.json"

# Resolve `code` without shell aliases (interactive zsh aliases code→cursor).
# `command -v` in this bash script is unaliased; still reject cursor paths.
VSCODE_BIN="$(command -v code 2>/dev/null || true)"
case "$VSCODE_BIN" in
    *cursor*|"") VSCODE_BIN="" ;;
esac
if [[ -n "$VSCODE_BIN" && -x "$VSCODE_BIN" ]]; then
    "$VSCODE_BIN" --list-extensions --show-versions >"$VSCODE/extensions.list" 2>/dev/null || true
    if [[ -s "$VSCODE/extensions.list" ]]; then
        log_ok "vscode extensions.list"
    else
        rm -f "$VSCODE/extensions.list"
        log_skip "vscode extensions.list"
    fi
    rm -f "$PKG/vscode_list.txt"
else
    log_skip "vscode CLI (code missing or resolves to cursor)"
fi

# Raycast: extension titles only (415MB install tree + encrypted sqlite stay local).
# Full restore = Raycast "Export Settings & Data" → custom_backups/raycast/*.rayconfig
# and/or Raycast Pro Cloud Sync — plist alone is not enough.
if run_tool_python -m backup_run.extras.raycast extensions-list "$RAYCAST/extensions.list"; then
    if [[ -s "$RAYCAST/extensions.list" ]]; then
        log_ok "raycast extensions.list"
    else
        rm -f "$RAYCAST/extensions.list"
        log_skip "raycast extensions.list"
    fi
else
    log_skip "raycast extensions.list"
fi

echo "🔄 backup_extras: macOS system settings"
MACOS_DOMAINS=(
    com.apple.dock
    com.apple.finder
    com.apple.symbolichotkeys
    com.apple.HIToolbox
    com.apple.universalaccess
    com.apple.controlcenter
    com.apple.screensaver
    com.apple.loginwindow
    com.apple.AppleMultitouchTrackpad
    com.apple.driver.AppleBluetoothMultitouch.trackpad
    com.apple.driver.AppleBluetoothMultitouch.mouse
)
for domain in "${MACOS_DOMAINS[@]}"; do
    if defaults export "$domain" "$MACOS/${domain}.plist" 2>/dev/null; then
        log_ok "defaults export $domain"
    else
        rm -f "$MACOS/${domain}.plist"
        log_skip "defaults export $domain"
    fi
done

for pref in .GlobalPreferences.plist com.apple.keyboard.plist; do
    src="$HOME/Library/Preferences/$pref"
    if [[ -f "$src" ]]; then
        cp "$src" "$MACOS/$pref"
        log_ok "preferences $pref"
    fi
done

if osascript -e 'tell application "System Events" to get the name of every login item' >"$MACOS/login-items-osascript.txt" 2>/dev/null; then
    log_ok "login items (osascript)"
else
    rm -f "$MACOS/login-items-osascript.txt"
    log_skip "login items osascript"
fi

if [[ "${BACKUP_SUDO:-0}" == "1" ]]; then
    if command -v sfltool >/dev/null 2>&1; then
        # Do not redirect stderr — sudo password prompt writes to stderr.
        if sudo sfltool dumpbtm >"$MACOS/login-items-sfltool.txt"; then
            log_ok "login items (sudo sfltool dumpbtm)"
        else
            log_skip "sfltool (sudo failed; keeping existing login-items-sfltool.txt if any)"
        fi
    else
        log_skip "sfltool (not installed)"
    fi
else
    log_skip "sfltool (use backup -s; keeping existing login-items-sfltool.txt if any)"
fi

echo "🔄 backup_extras: Chrome bookmarks → HTML"
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome"
LOCAL_STATE="$CHROME_DIR/Local State"
profile_label() {
    run_tool_python -m backup_run.extras.chrome profile-label "$LOCAL_STATE" "$1"
}

if [[ -d "$CHROME_DIR" ]]; then
    while IFS= read -r bookmarks; do
        profile_path="$(dirname "$bookmarks")"
        profile_dir="$(basename "$profile_path")"
        label="$(profile_label "$profile_dir")"
        out="$CHROME/${label}.html"
        run_tool_python -m backup_run.extras.chrome bookmarks "$bookmarks" "$out"
        log_ok "Chrome $profile_dir → $(basename "$out")"
    done < <(find "$CHROME_DIR" -maxdepth 2 -name Bookmarks -type f 2>/dev/null | sort)
else
    log_skip "Chrome profile dir missing"
fi

echo "🔄 backup_extras: Chrome inventory (profiles, extensions, web apps)"
"$SCRIPT_DIR/snapshot_chrome_inventory.sh"

echo "🔄 backup_extras: dev layout (repo index, skeleton, workspaces)"
"$SCRIPT_DIR/snapshot_dev_layout.sh"

echo "🔄 backup_extras: Postman local config"
"$SCRIPT_DIR/snapshot_postman.sh"

echo "✅ backup_extras done → $BACKUP_ROOT"
