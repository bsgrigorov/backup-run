#!/usr/bin/env bash
# Daily LaunchAgent entry: sync backup snapshot → bsgrigorov/backup (no secrets).
set -euo pipefail

LOG_DIR="${HOME}/.local/log"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/backup-mac.log" 2>>"$LOG_DIR/backup-mac.error.log"

echo "==> scheduled-backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"

BACKUP_RUN_ROOT="${BACKUP_RUN_ROOT:-$HOME/dev/repos/zzz/backup-run}"
if [[ -x "$BACKUP_RUN_ROOT/backup" ]]; then
  exec "$BACKUP_RUN_ROOT/backup"
fi

echo "ERROR: backup script missing: $BACKUP_RUN_ROOT/backup" >&2
exit 1
