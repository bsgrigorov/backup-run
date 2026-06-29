#!/usr/bin/env bash
# Snapshot ~/dev layout: git repo index + umbrella skeleton (YAML), workspaces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

BACKUP_ROOT="$(resolve_backup_root)"
DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
REPOS_ROOT="${REPOS_ROOT:-$DEV_ROOT/repos}"
LAYOUTS="$BACKUP_ROOT/layouts"
WORKSPACES="$BACKUP_ROOT/configs/workspaces"

mkdir -p "$LAYOUTS" "$WORKSPACES"

echo "🔄 snapshot_dev_layout: repo clone map (org/name → https url → path)"
run_tool_python -m backup_run.extras.dev_layout repos-map \
    "$REPOS_ROOT" \
    "$LAYOUTS/repos_map.yaml"
log_ok "layouts/repos_map.yaml"

echo "🔄 snapshot_dev_layout: dev layout"
run_tool_python -m backup_run.extras.dev_layout layout \
    "$DEV_ROOT" \
    "$REPOS_ROOT" \
    "$LAYOUTS/dev_layout.yaml"
log_ok "layouts/dev_layout.yaml"

echo "🔄 snapshot_dev_layout: workspaces"
ws_count=0
if [[ -d "$REPOS_ROOT" ]]; then
    shopt -s nullglob
    for ws in "$REPOS_ROOT"/*.code-workspace; do
        cp "$ws" "$WORKSPACES/"
        ws_count=$((ws_count + 1))
    done
    shopt -u nullglob
fi
if [[ "$ws_count" -gt 0 ]]; then
    log_ok "$ws_count workspace file(s) → configs/workspaces/"
else
    log_skip "no .code-workspace files under $REPOS_ROOT"
fi

echo "✅ snapshot_dev_layout done"
