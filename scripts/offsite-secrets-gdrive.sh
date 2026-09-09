#!/usr/bin/env bash
# Encrypted offsite bundle of local secrets → Google Drive Documents/Backup.
#
# Gap-fill only: gitignored home secrets + gitignored repo secret trees.
# Does NOT duplicate kube/aws config or allowed_signers (those live in bsgrigorov/backup).
#
# Usage:
#   ./scripts/offsite-secrets-gdrive.sh --dry-run
#   ./scripts/offsite-secrets-gdrive.sh --verify
#   ./scripts/offsite-secrets-gdrive.sh --with-gpg --verify
#   BACKUP_OFFSITE_OP_REF='op://…/password' ./scripts/offsite-secrets-gdrive.sh --verify
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_RUN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_ROOT="${REPOS_ROOT:-$HOME/dev/repos}"
# Canonical clone path — do not use $ZSHENV from the shell (Cursor may point elsewhere).
ZSHENV_ROOT="$REPOS_ROOT/zzz/zsh-env"
GDRIVE_BACKUP="${GDRIVE_BACKUP:-$HOME/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/My Drive/Documents/Backup}"
ALLOWLIST="${ALLOWLIST:-$BACKUP_RUN_ROOT/manifest/secrets-offsite-allowlist.conf}"
NAME="mac-secrets"
DRY_RUN=0
VERIFY=0
WITH_GPG=0
BACKUP_GPG_KEY="${BACKUP_GPG_KEY:-35D8EF1D6E95634C63425CC8B25BFCD53CFAE412}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--verify] [--dry-run] [--with-gpg] [-h]

Collect gitignored secrets into a zip, encrypt with age, write:
  $GDRIVE_BACKUP/${NAME}.zip.age

  --verify    decrypt + unzip test in a temp dir (no secret contents printed)
  --dry-run   list sources that would be included; do not write
  --with-gpg  export GPG secret key (BACKUP_GPG_KEY)
  -h, --help  this help

Passphrase (same as offsite-gdrive.sh):
  BACKUP_OFFSITE_PASSPHRASE, BACKUP_OFFSITE_OP_REF, GUI prompt, or tty

Restore: backup/manual/secrets.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --with-gpg) WITH_GPG=1; shift ;;
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
if [[ "$DRY_RUN" -eq 0 && ! -d "$GDRIVE_BACKUP" ]]; then
  echo "ERROR: Google Drive Backup folder missing: $GDRIVE_BACKUP" >&2
  exit 1
fi
if [[ ! -f "$ALLOWLIST" ]]; then
  echo "ERROR: allowlist missing: $ALLOWLIST" >&2
  exit 1
fi

# dest_relative_in_zip|source_absolute
FILE_ENTRIES=(
  "zsh-env/shell/secret/core.sh|$ZSHENV_ROOT/shell/secret/core.sh"
  "zsh-env/shell/secret/home.sh|$ZSHENV_ROOT/shell/secret/home.sh"
  "zsh-env/shell/secret/work.sh|$ZSHENV_ROOT/shell/secret/work.sh"
  "ssh/id_ed25519|$HOME/.ssh/id_ed25519"
  "ssh/id_ed25519.pub|$HOME/.ssh/id_ed25519.pub"
  "ssh/id_ed25519_signing|$HOME/.ssh/id_ed25519_signing"
  "ssh/id_ed25519_signing.pub|$HOME/.ssh/id_ed25519_signing.pub"
  "ssh/config|$HOME/.ssh/config"
  "dotfiles/npmrc|$HOME/.npmrc"
  "dotfiles/netrc|$HOME/.netrc"
  "codex/auth.json|$HOME/.codex/auth.json"
  "pi/agent/auth.json|$HOME/.pi/agent/auth.json"
  "repos/personal/agent/synkube-agents/agent-runtime/compose/.env|$REPOS_ROOT/personal/agent/synkube-agents/agent-runtime/compose/.env"
)

# dest_relative_dir_in_zip|source_absolute_dir
DIR_ENTRIES=(
  "repos/personal/agent/agent-fleet/live/k8s-cody/secrets|$REPOS_ROOT/personal/agent/agent-fleet/live/k8s-cody/secrets"
  "repos/personal/agent/agent-fleet/live/mac-docker/secrets|$REPOS_ROOT/personal/agent/agent-fleet/live/mac-docker/secrets"
  "repos/personal/agent/synkube-agents/agent-runtime/compose/secrets|$REPOS_ROOT/personal/agent/synkube-agents/agent-runtime/compose/secrets"
)

gui_prompt() {
  osascript <<OSA 2>/dev/null
    try
      set answer to text returned of (display dialog "$1" with title "offsite-secrets" default answer "" with hidden answer)
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
    p1="$(gui_prompt "Secrets encryption passphrase:")"
    p2="$(gui_prompt "Confirm passphrase:")"
  elif [[ -t 0 ]]; then
    read -r -s -p "Secrets encrypt passphrase: " p1
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

filter_aws_credentials() {
  local src="$1" dest="$2"
  python3 - "$src" "$dest" "$ALLOWLIST" <<'PY'
import configparser
import re
import sys
from pathlib import Path

src, dest, allowlist_path = sys.argv[1:4]
exact: set[str] = set()
patterns: list[re.Pattern[str]] = []
for raw in Path(allowlist_path).read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("aws_profile:"):
        exact.add(line.split(":", 1)[1])
    elif line.startswith("aws_profile_pattern:"):
        patterns.append(re.compile(line.split(":", 1)[1]))

def allowed(name: str) -> bool:
    return name in exact or any(p.search(name) for p in patterns)

cp = configparser.ConfigParser()
cp.read(src)
out = configparser.ConfigParser()
included: list[str] = []
for section in cp.sections():
    if allowed(section):
        out[section] = cp[section]
        included.append(section)

if not included:
    print("ERROR: no AWS credential profiles matched allowlist", file=sys.stderr)
    sys.exit(1)

Path(dest).parent.mkdir(parents=True, exist_ok=True)
with open(dest, "w", encoding="utf-8") as fh:
    out.write(fh)
print(",".join(included))
PY
}

stage_file() {
  local dest="$1" src="$2" stage="$3"
  if [[ ! -e "$src" ]]; then
    echo "    skip (missing): $dest"
    return 1
  fi
  mkdir -p "$stage/secrets/$(dirname "$dest")"
  cp -p "$src" "$stage/secrets/$dest"
  chmod 600 "$stage/secrets/$dest" 2>/dev/null || true
  printf '%s\n' "$dest" >>"$stage/MANIFEST.txt"
  echo "    include: $dest"
  return 0
}

stage_dir() {
  local dest="$1" src="$2" stage="$3"
  if [[ ! -d "$src" ]]; then
    echo "    skip (missing dir): $dest"
    return 1
  fi
  local count
  count="$(find "$src" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')"
  if [[ "$count" -eq 0 ]]; then
    echo "    skip (empty dir): $dest"
    return 1
  fi
  mkdir -p "$stage/secrets/$(dirname "$dest")"
  rsync -a --exclude '.DS_Store' "$src/" "$stage/secrets/$dest/"
  while IFS= read -r -d '' f; do chmod 600 "$f"; done < <(find "$stage/secrets/$dest" -type f -print0)
  printf '%s/ (%s files)\n' "$dest" "$count" >>"$stage/MANIFEST.txt"
  echo "    include: $dest/ ($count files)"
  return 0
}

stage_secrets() {
  local stage="$1"
  local included=0
  local dest src profiles

  mkdir -p "$stage/secrets"
  : >"$stage/MANIFEST.txt"
  printf 'generated=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$stage/MANIFEST.txt"
  printf 'host=%s\n' "$(hostname -s 2>/dev/null || hostname)" >>"$stage/MANIFEST.txt"

  for entry in "${FILE_ENTRIES[@]}"; do
    dest="${entry%%|*}"
    src="${entry#*|}"
    if stage_file "$dest" "$src" "$stage"; then
      included=$((included + 1))
    fi
  done

  for entry in "${DIR_ENTRIES[@]}"; do
    dest="${entry%%|*}"
    src="${entry#*|}"
    if stage_dir "$dest" "$src" "$stage"; then
      included=$((included + 1))
    fi
  done

  if [[ -f "$HOME/.aws/credentials" ]]; then
    mkdir -p "$stage/secrets/aws"
    profiles="$(filter_aws_credentials "$HOME/.aws/credentials" "$stage/secrets/aws/credentials")"
    printf 'aws/credentials (profiles: %s)\n' "$profiles" >>"$stage/MANIFEST.txt"
    echo "    include: aws/credentials (profiles: $profiles)"
    included=$((included + 1))
  else
    echo "    skip (missing): aws/credentials"
  fi

  if [[ "$WITH_GPG" -eq 1 ]]; then
    if ! command -v gpg >/dev/null 2>&1; then
      echo "ERROR: gpg not found (--with-gpg)" >&2
      exit 1
    fi
    mkdir -p "$stage/secrets/gpg"
    local asc="$stage/secrets/gpg/secret-${BACKUP_GPG_KEY}.asc"
    if gpg --armor --export-secret-keys "$BACKUP_GPG_KEY" >"$asc"; then
      chmod 600 "$asc"
      printf 'gpg/secret-%s.asc\n' "$BACKUP_GPG_KEY" >>"$stage/MANIFEST.txt"
      echo "    include: gpg/secret-${BACKUP_GPG_KEY}.asc"
      included=$((included + 1))
    else
      echo "ERROR: gpg --export-secret-keys failed for $BACKUP_GPG_KEY" >&2
      exit 1
    fi
  fi

  if [[ "$included" -eq 0 ]]; then
    echo "ERROR: no secret files found to bundle" >&2
    exit 1
  fi
  printf 'bundles=%s\n' "$included" >>"$stage/MANIFEST.txt"
}

PLAIN="${TMPDIR:-/tmp}/${NAME}.zip"
OUT="$GDRIVE_BACKUP/${NAME}.zip.age"

echo "==> offsite-secrets-gdrive"
echo "    dest:   $OUT"
echo "    filter: $ALLOWLIST"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: would stage and zip:"
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/secrets-dry.XXXXXX")"
  trap 'find "$STAGE" -type f -delete 2>/dev/null; rmdir "$STAGE" 2>/dev/null || true' EXIT
  stage_secrets "$STAGE"
  exit 0
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/secrets-stage.XXXXXX")"
cleanup_stage() {
  [[ -d "$STAGE" ]] || return 0
  find "$STAGE" -type f -delete
  find "$STAGE" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup_stage EXIT

echo "==> staging"
stage_secrets "$STAGE"

echo "==> creating zip"
(
  cd "$STAGE"
  zip -r -q "$PLAIN" MANIFEST.txt secrets
)
ls -lh "$PLAIN"

PASS="$(resolve_passphrase)"
echo "==> encrypting → $OUT"
if ! printf '%s\n%s\n' "$PASS" "$PASS" | script -q /dev/null age -p -o "$OUT" "$PLAIN" >/dev/null 2>&1; then
  echo "ERROR: age encrypt failed" >&2
  unset PASS
  exit 1
fi
[[ -s "$OUT" ]] || { echo "ERROR: age produced empty output" >&2; unset PASS; exit 1; }
rm -f "$PLAIN"
ls -lh "$OUT"

if [[ "$VERIFY" -eq 1 ]]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/secrets-verify.XXXXXX")"
  cleanup_verify() {
    [[ -d "$WORK" ]] || return 0
    find "$WORK" -type f -delete
    find "$WORK" -depth -type d -empty -delete 2>/dev/null || true
  }
  trap cleanup_verify EXIT
  echo "==> verifying (auto-removed)"
  DEC="$WORK/artifact.zip"
  if ! printf '%s\n' "$PASS" | script -q /dev/null age -d -o "$DEC" "$OUT" >/dev/null 2>&1; then
    echo "ERROR: age decrypt failed" >&2
    exit 1
  fi
  unzip -t -q "$DEC"
  unzip -q "$DEC" -d "$WORK/tree"
  test -s "$WORK/tree/MANIFEST.txt" || { echo "ERROR: MANIFEST.txt missing" >&2; exit 1; }
  test -d "$WORK/tree/secrets" || { echo "ERROR: secrets/ missing" >&2; exit 1; }
  local_count="$(find "$WORK/tree/secrets" -type f | wc -l | tr -d ' ')"
  [[ "$local_count" -gt 0 ]] || { echo "ERROR: empty secrets tree" >&2; exit 1; }
  echo "    $local_count files in secrets/"
  echo "==> verify passed"
fi
unset PASS

echo "==> done"
echo "    restore: backup/manual/secrets.md"
