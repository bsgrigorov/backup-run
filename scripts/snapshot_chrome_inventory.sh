#!/usr/bin/env bash
# Simple Chrome inventory: profiles, extensions dirs, web apps (ls only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

BACKUP_ROOT="$(resolve_backup_root)"
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome"
LOCAL_STATE="$CHROME_DIR/Local State"
INV="$BACKUP_ROOT/configs/chrome/inventory"

profile_label() {
    run_tool_python -m backup_run.extras.chrome profile-label "$LOCAL_STATE" "$1"
}

write_ls() {
    local src=$1 dest=$2
    if [[ -d "$src" ]]; then
        ls -1 "$src" 2>/dev/null | sort >"$dest" || : >"$dest"
    fi
}

if [[ ! -d "$CHROME_DIR" ]]; then
    log_skip "Chrome profile dir missing"
    exit 0
fi

mkdir -p "$INV"

{
    echo "# Chrome profiles under: $CHROME_DIR"
    echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    for entry in "$CHROME_DIR"/*; do
        [[ -d "$entry" ]] || continue
        base="$(basename "$entry")"
        case "$base" in
            Default|Profile\ *) echo "$base" ;;
        esac
    done | sort
} >"$INV/profiles.txt"
log_ok "chrome inventory → profiles.txt"

profile_count=0
shopt -s nullglob
for profile_path in "$CHROME_DIR/Default" "$CHROME_DIR"/Profile\ *; do
    [[ -d "$profile_path" ]] || continue
    profile_dir="$(basename "$profile_path")"
    label="$(profile_label "$profile_dir")"
    dest_dir="$INV/$label"
    mkdir -p "$dest_dir"

    write_ls "$profile_path/Extensions" "$dest_dir/extensions_ls.txt"
    write_ls "$profile_path/Web Applications" "$dest_dir/web_applications_ls.txt"
    write_ls "$profile_path/Web Applications/Manifest Resources" "$dest_dir/web_apps_manifest_resources_ls.txt"

    profile_count=$((profile_count + 1))
done
shopt -u nullglob

if [[ "$profile_count" -gt 0 ]]; then
    log_ok "$profile_count Chrome profile(s) → configs/chrome/inventory/"
else
    log_skip "no Chrome profiles found"
fi
