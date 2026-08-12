#!/usr/bin/env bash
# Offline encrypted snapshot of the backup data → Google Drive Documents/Backup.
#
# Default: --zip of the current working tree (~2 MB). Excludes .git, dotfiles/.ssh.
#   The backup repo's .git history is ~136 MB of long-since-removed binaries
#   (minikube, krew plugins, kube caches), so we ship current files, not history.
# Optional: --bundle for a full git bundle (all history; large — ~97 MB).
#
# Usage:
#   ./scripts/offsite-gdrive.sh                 # zip; GUI/tty passphrase prompt
#   ./scripts/offsite-gdrive.sh --verify        # zip, then decrypt+check in a temp dir
#   ./scripts/offsite-gdrive.sh --dry-run
#   BACKUP_OFFSITE_PASSPHRASE='…' ./scripts/offsite-gdrive.sh   # non-interactive
#   BACKUP_OFFSITE_OP_REF='op://Personal/…/password' ./scripts/offsite-gdrive.sh
#
# Decrypt + restore into a throwaway temp dir, e.g.:
#   work="$(mktemp -d "${TMPDIR:-/tmp}/backup-restore.XXXXXX")"
#   openssl enc -d -aes-256-cbc -pbkdf2 -in backup-tree-YYYYMMDD.zip.enc -out "$work/backup.zip"
#   unzip "$work/backup.zip" -d "$work"    # inspect, then remove "$work"
# Or just run with --verify to prove the artifact and clean up automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/dev/repos/zzz/backup}"
GDRIVE_BACKUP="${GDRIVE_BACKUP:-$HOME/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/My Drive/Documents/Backup}"
STAMP="$(date +%Y%m%d)"
MODE=zip   # zip | bundle
DRY_RUN=0
KEEP_PLAIN=0
VERIFY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--zip|--bundle] [--verify] [--dry-run] [--keep-plain] [-h]

Write an encrypted offsite copy of the backup data into:
  $GDRIVE_BACKUP

  --zip         zip current working tree (default; ~2 MB; excludes .git, .ssh)
  --bundle      git bundle --all (full history; large — ~97 MB)
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
    --bundle) MODE=bundle; shift ;;
    --zip) MODE=zip; shift ;;
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

if [[ ! -d "$BACKUP_ROOT/.git" ]]; then
  echo "ERROR: not a git repo: $BACKUP_ROOT" >&2
  exit 1
fi
if [[ ! -d "$GDRIVE_BACKUP" ]]; then
  echo "ERROR: Google Drive Backup folder missing: $GDRIVE_BACKUP" >&2
  echo "Is Drive for desktop signed in and syncing?" >&2
  exit 1
fi

if [[ "$MODE" == bundle ]]; then
  PLAIN="/tmp/backup-git-${STAMP}.bundle"
  OUT="$GDRIVE_BACKUP/backup-git-${STAMP}.bundle.enc"
else
  PLAIN="/tmp/backup-tree-${STAMP}.zip"
  OUT="$GDRIVE_BACKUP/backup-tree-${STAMP}.zip.enc"
fi

echo "==> offsite-gdrive"
echo "    source: $BACKUP_ROOT"
echo "    mode:   $MODE"
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

echo "==> creating $MODE artifact"
if [[ "$MODE" == bundle ]]; then
  git -C "$BACKUP_ROOT" bundle create "$PLAIN" --all
else
  (
    cd "$(dirname "$BACKUP_ROOT")"
    zip -r -q "$PLAIN" "$(basename "$BACKUP_ROOT")" \
      -x '*/.DS_Store' \
      -x 'backup/.git/*' \
      -x 'backup/dotfiles/.ssh/*' \
      -x 'backup/dotfiles/.ssh'
  )
fi
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
  if [[ "$MODE" == bundle ]]; then
    # Clone into the temp dir: proves the bundle decrypts and restores end-to-end.
    git clone --quiet "$DEC" "$WORK/repo"
    echo "bundle OK — cloned $(git -C "$WORK/repo" rev-list --count HEAD) commits"
  else
    unzip -t -q "$DEC" && echo "zip OK"
  fi
  echo "==> verify passed"
fi
unset PASS

echo "==> done"
echo "    verify next time: $(basename "$0") --${MODE} --verify"
echo "    manual decrypt into a throwaway dir (auto-clean):"
echo "      work=\"\$(mktemp -d \"\${TMPDIR:-/tmp}/backup-restore.XXXXXX\")\""
echo "      openssl enc -d -aes-256-cbc -pbkdf2 -in \"$OUT\" -out \"\$work/artifact\""
if [[ "$MODE" == bundle ]]; then
  echo "      git clone \"\$work/artifact\" \"\$work/backup\"   # inspect, then: rm -rf \"\$work\""
else
  echo "      unzip \"\$work/artifact\" -d \"\$work\"           # inspect, then: rm -rf \"\$work\""
fi
