#!/usr/bin/env bash
# Cursor IDE/CLI auth → age-encrypted tarball in backup repo (not chat history).
#
# Plaintext only under <machine>/secrets/.stage-cursor-auth/ (gitignored).
# Committed: <machine>/secrets/cursor-auth-bundle.tar.age
#
# Usage:
#   ./scripts/cursor-auth-backup.sh --dry-run
#   ./scripts/cursor-auth-backup.sh --verify
#   ./scripts/cursor-auth-backup.sh --no-drive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_RUN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
# shellcheck source=lib/secrets-bundle.sh
source "$SCRIPT_DIR/lib/secrets-bundle.sh"
# shellcheck source=lib/cursor-auth.sh
source "$SCRIPT_DIR/lib/cursor-auth.sh"

GDRIVE_BACKUP="${GDRIVE_BACKUP:-$HOME/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/My Drive/Documents/Backup}"
DRIVE_NAME="cursor-auth"

DRY_RUN=0
VERIFY=1
WRITE_DRIVE=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [--verify] [--no-verify] [--dry-run] [--no-drive] [-h]

Export Cursor auth (SQLite rows + Keychain + CLI slices), tar, age-encrypt:
  <backup-repo>/<BACKUP_TARGET>/secrets/cursor-auth-bundle.tar.age

  Drive (optional): $GDRIVE_BACKUP/${DRIVE_NAME}-\${BACKUP_TARGET}.tar.age

Quit Cursor before running. Passphrase: same as secrets (op://Personal/drive-backup/password).
Restore: ./scripts/cursor-auth-restore.sh
Docs: docs/CURSOR-AUTH-BACKUP.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY=1; shift ;;
    --no-verify) VERIFY=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-drive) WRITE_DRIVE=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v age >/dev/null 2>&1; then
  echo "ERROR: age not found (brew install age)" >&2
  exit 1
fi

MACHINE_ROOT="$(resolve_backup_root)"
BACKUP_TARGET="$(run_tool_python -c 'from backup_run.config import get_backup_target; print(get_backup_target())')"
cursor_auth_init_paths

echo "==> cursor-auth-backup"
echo "    target:  $BACKUP_TARGET"
echo "    machine: $MACHINE_ROOT"
echo "    git out: $OUT_AGE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  cursor_auth_require_quit
  dry_stage="$(mktemp -d "${TMPDIR:-/tmp}/cursor-auth-dry-run.XXXXXX")"
  cursor_auth_stage_bundle "$dry_stage"
  rm -rf "$dry_stage"
  exit 0
fi

if [[ "$WRITE_DRIVE" -eq 1 && ! -d "$GDRIVE_BACKUP" ]]; then
  echo "WARN: Google Drive Backup folder missing — skipping Drive copy" >&2
  WRITE_DRIVE=0
fi

cursor_auth_require_quit
mkdir -p "$SECRETS_DIR"
cursor_auth_cleanup_stage
mkdir -p "$STAGE_ROOT" "$STAGE_WORK"
trap cursor_auth_cleanup_stage EXIT

echo "==> staging → $STAGE_ROOT (gitignored)"
cursor_auth_stage_bundle "$STAGE_WORK"

echo "==> creating tar"
tar -cf "$PLAIN_TAR" -C "$STAGE_WORK" .
ls -lh "$PLAIN_TAR"

PASS="$(secrets_resolve_passphrase)"
[[ -n "$PASS" ]] || { echo "ERROR: empty passphrase" >&2; exit 1; }

echo "==> encrypting → $OUT_AGE_TMP"
if [[ "$VERIFY" -eq 1 ]]; then
  cursor_auth_encrypt_tar_to_age "$PLAIN_TAR" "$OUT_AGE_TMP" "$PASS"
else
  # shellcheck source=lib/secrets-bundle.sh
  source "$SCRIPT_DIR/lib/secrets-bundle.sh"
  secrets_age_run -p "$PASS" "$OUT_AGE_TMP" "$PLAIN_TAR" || exit 1
fi
mv -f "$OUT_AGE_TMP" "$OUT_AGE"
ls -lh "$OUT_AGE"

if [[ "$WRITE_DRIVE" -eq 1 ]]; then
  DRIVE_OUT="$GDRIVE_BACKUP/${DRIVE_NAME}-${BACKUP_TARGET}.tar.age"
  echo "==> copying → $DRIVE_OUT"
  cp -f "$OUT_AGE" "$DRIVE_OUT"
  if [[ "$VERIFY" -eq 1 ]]; then
    cmp -s "$OUT_AGE" "$DRIVE_OUT" || { echo "ERROR: Drive copy mismatch" >&2; exit 1; }
    echo "    verified: Drive copy matches git artifact"
  fi
fi

unset PASS
cursor_auth_cleanup_stage
trap - EXIT

cursor_auth_assert_git_safe "$SECRETS_DIR"

echo "==> done"
echo "    git:   $OUT_AGE"
if [[ "$WRITE_DRIVE" -eq 1 ]]; then
  echo "    drive: $GDRIVE_BACKUP/${DRIVE_NAME}-${BACKUP_TARGET}.tar.age"
fi
