#!/usr/bin/env bash
# One-time: move legacy flat backup layout into <repo>/<BACKUP_TARGET>/.
# Requires BACKUP_TARGET in ~/.zsh/local.sh (or env). Idempotent if already migrated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ROOT="$(resolve_backup_repo_root)"
MACHINE_ROOT="$(resolve_backup_root)"
TARGET="$(run_tool_python -c 'from backup_run.config import get_backup_target; print(get_backup_target())')"

DIRS=(dotfiles configs packages layouts custom_backups fonts)

if [[ "$MACHINE_ROOT" == "$REPO_ROOT" ]]; then
  echo "ERROR: machine path equals repo root — set BACKUP_TARGET in ~/.zsh/local.sh" >&2
  exit 1
fi

if [[ -d "$MACHINE_ROOT/dotfiles" ]]; then
  echo "OK  already migrated → $MACHINE_ROOT"
  exit 0
fi

mkdir -p "$MACHINE_ROOT"
moved=0
for name in "${DIRS[@]}"; do
  src="$REPO_ROOT/$name"
  [[ -e "$src" ]] || continue
  echo "move $name → $TARGET/"
  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO_ROOT" mv "$name" "$TARGET/"
  else
    mv "$src" "$MACHINE_ROOT/"
  fi
  moved=1
done

if [[ "$moved" == 0 ]]; then
  echo "nothing to migrate under $REPO_ROOT"
else
  echo "done: $MACHINE_ROOT"
fi
