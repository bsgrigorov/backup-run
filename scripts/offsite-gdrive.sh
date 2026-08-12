#!/usr/bin/env bash
# Encrypted offsite snapshot of the backup data → Google Drive Documents/Backup.
#
# Zips the current working tree (~2 MB), excluding .git and dotfiles/.ssh.
# Current files only, no git history: GitHub already holds the history, and this
# repo's .git carries ~136 MB of long-since-removed binaries (minikube, krew
# plugins, kube caches) that are worthless offsite.
#
# Usage:
#   ./scripts/offsite-gdrive.sh                 # GUI/tty passphrase prompt
#   ./scripts/offsite-gdrive.sh --verify        # then decrypt+check in a temp dir
#   ./scripts/offsite-gdrive.sh --dry-run
#   BACKUP_OFFSITE_PASSPHRASE='…' ./scripts/offsite-gdrive.sh   # non-interactive
#   BACKUP_OFFSITE_OP_REF='op://Personal/…/password' ./scripts/offsite-gdrive.sh
#
# Restore into a throwaway temp dir:
#   work="$(mktemp -d "${TMPDIR:-/tmp}/backup-restore.XXXXXX")"
#   openssl enc -d -aes-256-cbc -pbkdf2 -in backup-tree-YYYYMMDD.zip.enc -out "$work/backup.zip"
#   unzip "$work/backup.zip" -d "$work"    # inspect, then remove "$work"
# Or run with --verify to prove the artifact and clean up automatically.
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/dev/repos/zzz/backup}"
GDRIVE_BACKUP="${GDRIVE_BACKUP:-$HOME/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/My Drive/Documents/Backup}"
STAMP="$(date +%Y%m%d)"
DRY_RUN=0
KEEP_PLAIN=0
VERIFY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--verify] [--dry-run] [--keep-plain] [-h]

Write an encrypted zip of the backup data into:
  $GDRIVE_BACKUP

  --verify      after writing, decrypt into a temp dir, check, and remove it
  --dry-run     print plan; do not write
  --keep-plain  leave the unencrypted intermediate in \$TMPDIR (debug only)
  -h, --help    this help

Passphrase (first match wins):
  1) BACKUP_OFFSITE_PASSPHRASE
  2) BACKUP_OFFSITE_OP_REF via: op read "\$BACKUP_OFFSITE_OP_REF"
  3) macOS GUI prompt (osascript, hidden answer) when no TTY
  4) interactive terminal prompt (tty)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --keep-plain) KEEP_PLAIN=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# .git must exist: cheap guard that BACKUP_ROOT really is the backup repo and
# not a stray path we'd silently archive instead.
if [[ ! -d "$BACKUP_ROOT/.git" ]]; then
  echo "ERROR: not the backup repo: $BACKUP_ROOT" >&2
  exit 1
fi
if [[ ! -d "$GDRIVE_BACKUP" ]]; then
  echo "ERROR: Google Drive Backup folder missing: $GDRIVE_BACKUP" >&2
  echo "Is Drive for desktop signed in and syncing?" >&2
  exit 1
fi

PLAIN="${TMPDIR:-/tmp}/backup-tree-${STAMP}.zip"
OUT="$GDRIVE_BACKUP/backup-tree-${STAMP}.zip.enc"

echo "==> offsite-gdrive"
echo "    source: $BACKUP_ROOT"
echo "    dest:   $OUT"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: would create $PLAIN then encrypt to $OUT"
  exit 0
fi

# macOS GUI passphrase prompt. Keeps the secret out of argv/ps and the chat log.
gui_prompt() {
  osascript <<OSA 2>/dev/null
    try
      set answer to text returned of (display dialog "$1" with title "offsite-gdrive" default answer "" with hidden answer)
      return answer
    on error
      return "__CANCELLED__"
    end try
OSA
}

resolve_passphrase() {
  if [[ -n "${BACKUP_OFFSITE_PASSPHRASE:-}" ]]; then
    printf '%s' "$BACKUP_OFFSITE_PASSPHRASE"
    return 0
  fi
  if [[ -n "${BACKUP_OFFSITE_OP_REF:-}" ]]; then
    if ! command -v op >/dev/null 2>&1; then
      echo "ERROR: op CLI required for BACKUP_OFFSITE_OP_REF" >&2
      exit 1
    fi
    op read "$BACKUP_OFFSITE_OP_REF"
    return 0
  fi

  local p1 p2
  if [[ ! -t 0 ]] && command -v osascript >/dev/null 2>&1; then
    p1="$(gui_prompt "Offsite encryption passphrase:")"
    p2="$(gui_prompt "Confirm passphrase:")"
  elif [[ -t 0 ]]; then
    read -r -s -p "Offsite encrypt passphrase: " p1
    echo >&2
    read -r -s -p "Confirm passphrase: " p2
    echo >&2
  else
    echo "ERROR: no passphrase (set BACKUP_OFFSITE_PASSPHRASE or BACKUP_OFFSITE_OP_REF)" >&2
    exit 1
  fi

  if [[ "$p1" == "__CANCELLED__" || "$p2" == "__CANCELLED__" ]]; then
    echo "ERROR: passphrase prompt cancelled" >&2
    exit 1
  fi
  if [[ "$p1" != "$p2" || -z "$p1" ]]; then
    echo "ERROR: passphrases empty or do not match" >&2
    exit 1
  fi
  printf '%s' "$p1"
}

echo "==> creating zip"
(
  cd "$(dirname "$BACKUP_ROOT")"
  zip -r -q "$PLAIN" "$(basename "$BACKUP_ROOT")" \
    -x '*/.DS_Store' \
    -x 'backup/.git/*' \
    -x 'backup/dotfiles/.ssh/*' \
    -x 'backup/dotfiles/.ssh'
)
ls -lh "$PLAIN"

PASS="$(resolve_passphrase)"
echo "==> encrypting → $OUT"
# Pass passphrase via fd so it never appears in `ps`
openssl enc -aes-256-cbc -pbkdf2 -salt \
  -in "$PLAIN" \
  -out "$OUT" \
  -pass "fd:3" \
  3<<<"$PASS"

if [[ "$KEEP_PLAIN" -eq 0 ]]; then
  rm -f "$PLAIN"
else
  echo "kept plain: $PLAIN"
fi

ls -lh "$OUT"

if [[ "$VERIFY" -eq 1 ]]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/backup-offsite-verify.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  echo "==> verifying → $WORK (auto-removed)"
  DEC="$WORK/artifact"
  openssl enc -d -aes-256-cbc -pbkdf2 -in "$OUT" -out "$DEC" -pass "fd:3" 3<<<"$PASS"
  unzip -t -q "$DEC"
  unzip -q "$DEC" -d "$WORK/tree"
  # Prove real files came back, not just a well-formed zip.
  for f in README.md packages/Brewfile manual/apps.md; do
    test -s "$WORK/tree/backup/$f" || { echo "ERROR: missing $f in restore" >&2; exit 1; }
  done
  echo "restored $(find "$WORK/tree" -type f | wc -l | tr -d ' ') files"
  echo "==> verify passed"
fi
unset PASS

echo "==> done"
echo "    verify next time: $(basename "$0") --verify"
echo "    manual restore into a throwaway dir:"
echo "      work=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/backup-restore.XXXXXX\")\""
echo "      openssl enc -d -aes-256-cbc -pbkdf2 -in \"$OUT\" -out \"\$work/backup.zip\""
echo "      unzip \"\$work/backup.zip\" -d \"\$work\"    # inspect, then remove \"\$work\""
