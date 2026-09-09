#!/usr/bin/env bash
# Encrypted secrets bundle → backup repo (git) and optionally Google Drive.
#
# Plaintext only under <machine>/secrets/.stage/ (gitignored), never committed.
# Committed artifact: <machine>/secrets/bundle.zip.age
#
# Usage:
#   ./scripts/offsite-secrets.sh --dry-run
#   ./scripts/offsite-secrets.sh --verify
#   ./scripts/offsite-secrets.sh --with-gpg
#   ./scripts/offsite-secrets.sh --no-drive          # git repo only
#   BACKUP_OFFSITE_OP_REF='op://Personal/drive-backup/password' ./scripts/offsite-secrets.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_RUN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
# shellcheck source=lib/secrets-bundle.sh
source "$SCRIPT_DIR/lib/secrets-bundle.sh"

REPOS_ROOT="${REPOS_ROOT:-$HOME/dev/repos}"
ZSHENV_ROOT="$REPOS_ROOT/zzz/zsh-env"
GDRIVE_BACKUP="${GDRIVE_BACKUP:-$HOME/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/My Drive/Documents/Backup}"
BACKUP_GPG_KEY="${BACKUP_GPG_KEY:-35D8EF1D6E95634C63425CC8B25BFCD53CFAE412}"
DRIVE_NAME="mac-secrets"

DRY_RUN=0
VERIFY=1
WITH_GPG=0
WRITE_DRIVE=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [--verify] [--no-verify] [--dry-run] [--with-gpg] [--no-drive] [-h]

Collect secrets, zip, age-encrypt, write:
  <backup-repo>/<BACKUP_TARGET>/secrets/bundle.zip.age  (git; always)

  Google Drive (unless --no-drive):
  $GDRIVE_BACKUP/${DRIVE_NAME}-\${BACKUP_TARGET}.zip.age

Staging (gitignored, removed after run):
  <machine>/secrets/.stage/

  --verify     decrypt + unzip test after encrypt (default: on)
  --no-verify  skip post-encrypt verify (not recommended)
  --dry-run    list sources only
  --with-gpg   include GPG secret key export
  --no-drive   skip Google Drive copy
  -h, --help   this help

BACKUP_TARGET from ~/.zsh/local.sh. Passphrase: BACKUP_OFFSITE_PASSPHRASE,
BACKUP_OFFSITE_OP_REF, GUI prompt, or tty.

Restore: backup/manual/secrets.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY=1; shift ;;
    --no-verify) VERIFY=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --with-gpg) WITH_GPG=1; shift ;;
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

BACKUP_REPO_ROOT="$(resolve_backup_repo_root)"
MACHINE_ROOT="$(resolve_backup_root)"
BACKUP_TARGET="$(run_tool_python -c 'from backup_run.config import get_backup_target; print(get_backup_target())')"
ALLOWLIST="$(secrets_resolve_allowlist "$BACKUP_TARGET")"

secrets_bundle_init

echo "==> offsite-secrets"
echo "    target:  $BACKUP_TARGET"
echo "    machine: $MACHINE_ROOT"
echo "    allowlist: $ALLOWLIST"
echo "    git out: $OUT_AGE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: would stage under $STAGE_ROOT (gitignored), encrypt → $OUT_AGE"
  dry_stage="$(mktemp -d "${TMPDIR:-/tmp}/secrets-dry-run.XXXXXX")"
  secrets_stage_bundle "$dry_stage"
  rm -rf "$dry_stage"
  exit 0
fi

if [[ "$WRITE_DRIVE" -eq 1 && ! -d "$GDRIVE_BACKUP" ]]; then
  echo "WARN: Google Drive Backup folder missing — skipping Drive copy (git bundle still written)" >&2
  echo "       $GDRIVE_BACKUP" >&2
  WRITE_DRIVE=0
fi

mkdir -p "$SECRETS_DIR"
secrets_cleanup_stage
mkdir -p "$STAGE_ROOT"
trap secrets_cleanup_stage EXIT

echo "==> staging → $STAGE_ROOT (gitignored)"
secrets_stage_bundle "$STAGE_WORK"

echo "==> creating zip"
(
  cd "$STAGE_WORK"
  zip -r -q "$PLAIN_ZIP" MANIFEST.txt secrets
)
ls -lh "$PLAIN_ZIP"

PASS="$(secrets_resolve_passphrase)"
if [[ -z "$PASS" ]]; then
  echo "ERROR: empty passphrase" >&2
  exit 1
fi

echo "==> encrypting → $OUT_AGE_TMP"
if [[ "$VERIFY" -eq 1 ]]; then
  secrets_encrypt_zip_to_age "$PLAIN_ZIP" "$OUT_AGE_TMP" "$PASS"
else
  if ! secrets_age_run -p "$PASS" "$OUT_AGE_TMP" "$PLAIN_ZIP"; then
    echo "ERROR: age encrypt failed" >&2
    unset PASS
    exit 1
  fi
  [[ -s "$OUT_AGE_TMP" ]] || { echo "ERROR: empty age output" >&2; unset PASS; exit 1; }
fi
mv -f "$OUT_AGE_TMP" "$OUT_AGE"
ls -lh "$OUT_AGE"

if [[ "$WRITE_DRIVE" -eq 1 ]]; then
  DRIVE_OUT="$GDRIVE_BACKUP/${DRIVE_NAME}-${BACKUP_TARGET}.zip.age"
  echo "==> copying → $DRIVE_OUT"
  cp -f "$OUT_AGE" "$DRIVE_OUT"
  if [[ "$VERIFY" -eq 1 ]]; then
    echo "==> verifying Drive copy"
    cmp -s "$OUT_AGE" "$DRIVE_OUT" || {
      echo "ERROR: Drive copy does not match git artifact" >&2
      exit 1
    }
    echo "    verified: Drive copy matches git artifact"
  fi
fi

unset PASS
secrets_cleanup_stage
trap - EXIT

secrets_assert_git_safe "$SECRETS_DIR"

if [[ ! -f "$SECRETS_DIR/README.md" ]]; then
  cat >"$SECRETS_DIR/README.md" <<EOF
# Encrypted secrets (do not add plaintext here)

- Committed: \`bundle.zip.age\` only (age passphrase; see backup/manual/secrets.md).
- Staging \`.stage/\` is gitignored and must stay empty after a successful run.
- Machine: \`${BACKUP_TARGET}\`
EOF
fi

echo "==> done"
echo "    git:   $OUT_AGE"
[[ "$WRITE_DRIVE" -eq 1 ]] && echo "    drive: $GDRIVE_BACKUP/${DRIVE_NAME}-${BACKUP_TARGET}.zip.age"
echo "    restore: backup/manual/secrets.md"
