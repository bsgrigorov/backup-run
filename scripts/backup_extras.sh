#!/bin/bash
# Extra snapshots not covered by backup-run sync alone.
# Env: BACKUP_SUDO=1 enables sudo-only steps (set by backup -s).
set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin:${PATH:-}"

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/dev/repos/zzz/backup}"
PKG="$BACKUP_ROOT/packages"
MACOS="$BACKUP_ROOT/configs/macos-system"
CHROME="$BACKUP_ROOT/configs/chrome/bookmarks"
CURSOR="$BACKUP_ROOT/configs/cursor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}✓${NC} ${BLUE}$1${NC}"; }
log_skip() { echo "⚠️  skip: $1"; }

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

mkdir -p "$PKG" "$MACOS" "$CHROME" "$CURSOR/cli"

echo "🔄 backup_extras: package manifests"
if command -v brew >/dev/null 2>&1; then
    brew list --cask >"$PKG/brew_cask_list.txt"
    log_ok "brew casks → brew_cask_list.txt"
    brew tap >"$PKG/brew_tap_list.txt"
    log_ok "brew taps → brew_tap_list.txt"
    brew bundle dump --force --describe --file="$PKG/Brewfile"
    log_ok "brew bundle → Brewfile"
else
    log_skip "brew manifests"
fi

write_if_cmd "pnpm globals" "pnpm list -g --depth 0" "$PKG/pnpm_list.txt"
write_if_cmd "mise tools" "mise ls" "$PKG/mise_list.txt"
write_if_cmd "asdf versions" "asdf current 2>&1; asdf list 2>&1" "$PKG/asdf_current.txt"
write_if_cmd "pipx apps" "pipx list --short" "$PKG/pipx_list.txt"
write_if_cmd "uv tools" "uv tool list" "$PKG/uv_tools_list.txt"
write_if_cmd "fnm node versions" "fnm list" "$PKG/fnm_list.txt"

echo "🔄 backup_extras: Cursor (canonical: configs/cursor/)"
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
        if sudo -n sfltool dumpbtm >"$MACOS/login-items-sfltool.txt" 2>/dev/null; then
            log_ok "login items (sudo sfltool dumpbtm)"
        else
            log_skip "sfltool (sudo failed — run: sudo -v, then backup -s; keeping existing file if any)"
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
    local dir=$1
    python3 - "$LOCAL_STATE" "$dir" <<'PY'
import json, re, sys
from pathlib import Path

local_state, profile_dir = sys.argv[1], sys.argv[2]
name = profile_dir
try:
    data = json.loads(Path(local_state).read_text())
    info = data.get("profile", {}).get("info_cache", {}).get(profile_dir, {})
    if info.get("name"):
        name = info["name"]
except Exception:
    pass
slug = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or profile_dir
print(f"{profile_dir}__{slug}")
PY
}

if [[ -d "$CHROME_DIR" ]]; then
    while IFS= read -r bookmarks; do
        profile_path="$(dirname "$bookmarks")"
        profile_dir="$(basename "$profile_path")"
        label="$(profile_label "$profile_dir")"
        out="$CHROME/${label}.html"
        python3 "$SCRIPT_DIR/chrome_bookmarks_to_html.py" "$bookmarks" "$out"
        log_ok "Chrome $profile_dir → $(basename "$out")"
    done < <(find "$CHROME_DIR" -maxdepth 2 -name Bookmarks -type f 2>/dev/null | sort)
else
    log_skip "Chrome profile dir missing"
fi

echo "✅ backup_extras done → $BACKUP_ROOT"
