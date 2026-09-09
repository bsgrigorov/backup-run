#!/usr/bin/env bash
# Shared secrets staging, zip, age encrypt, verify. Source from scripts/*.sh — do not execute.
set -euo pipefail

secrets_bundle_init() {
  : "${BACKUP_RUN_ROOT:?}"
  : "${REPOS_ROOT:?}"
  : "${ZSHENV_ROOT:?}"
  : "${MACHINE_ROOT:?}"
  : "${ALLOWLIST:?}"

  SECRETS_DIR="$MACHINE_ROOT/secrets"
  STAGE_ROOT="$SECRETS_DIR/.stage"
  STAGE_WORK="$STAGE_ROOT/workspace"
  PLAIN_ZIP="$STAGE_ROOT/bundle.zip"
  OUT_AGE="$SECRETS_DIR/bundle.zip.age"
  OUT_AGE_TMP="$STAGE_ROOT/bundle.zip.age.tmp"
}

secrets_profile_work_enabled() {
  case "${PROFILE_WORK_ENABLED:-}" in
    1 | true | yes | on) return 0 ;;
  esac
  local local_sh="${HOME}/.zsh/local.sh"
  [[ -f "$local_sh" ]] && grep -qE '^[[:space:]]*export[[:space:]]+PROFILE_WORK_ENABLED=(true|1|yes|on)' "$local_sh"
}

secrets_build_file_entries() {
  FILE_ENTRIES=(
    "zsh-env/shell/secret/core.sh|$ZSHENV_ROOT/shell/secret/core.sh"
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
  [[ -f "$ZSHENV_ROOT/shell/secret/home.sh" ]] &&
    FILE_ENTRIES+=("zsh-env/shell/secret/home.sh|$ZSHENV_ROOT/shell/secret/home.sh")
  if secrets_profile_work_enabled && [[ -f "$ZSHENV_ROOT/shell/secret/work.sh" ]]; then
    FILE_ENTRIES+=("zsh-env/shell/secret/work.sh|$ZSHENV_ROOT/shell/secret/work.sh")
  fi

  DIR_ENTRIES=(
    "repos/personal/agent/agent-fleet/live/k8s-cody/secrets|$REPOS_ROOT/personal/agent/agent-fleet/live/k8s-cody/secrets"
    "repos/personal/agent/agent-fleet/live/mac-docker/secrets|$REPOS_ROOT/personal/agent/agent-fleet/live/mac-docker/secrets"
    "repos/personal/agent/synkube-agents/agent-runtime/compose/secrets|$REPOS_ROOT/personal/agent/synkube-agents/agent-runtime/compose/secrets"
  )
}

secrets_resolve_allowlist() {
  local target="$1"
  local candidate="$BACKUP_RUN_ROOT/manifest/secrets-allowlist-${target}.conf"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  if [[ -f "$BACKUP_RUN_ROOT/manifest/secrets-offsite-allowlist.conf" ]]; then
    printf '%s' "$BACKUP_RUN_ROOT/manifest/secrets-offsite-allowlist.conf"
    return 0
  fi
  echo "ERROR: no secrets allowlist for BACKUP_TARGET=$target" >&2
  return 1
}

secrets_gui_prompt() {
  osascript <<OSA 2>/dev/null
    try
      set answer to text returned of (display dialog "$1" with title "offsite-secrets" default answer "" with hidden answer)
      return answer
    on error
      return "__CANCELLED__"
    end try
OSA
}

secrets_resolve_passphrase() {
  local pass=""
  local op_ref="${BACKUP_OFFSITE_OP_REF:-op://Personal/drive-backup/password}"
  local op_explicit=0
  [[ -n "${BACKUP_OFFSITE_OP_REF:-}" ]] && op_explicit=1

  if [[ -n "${BACKUP_OFFSITE_PASSPHRASE:-}" ]]; then
    printf '%s' "$BACKUP_OFFSITE_PASSPHRASE"
    return 0
  fi
  if command -v op >/dev/null 2>&1; then
    if pass="$(op read "$op_ref" 2>/dev/null)" && [[ -n "$pass" ]]; then
      printf '%s' "$pass"
      return 0
    fi
    if [[ "$op_explicit" -eq 1 ]]; then
      echo "WARN: op read failed for BACKUP_OFFSITE_OP_REF — using passphrase prompt" >&2
    fi
  elif [[ "$op_explicit" -eq 1 ]]; then
    echo "WARN: op not found — using passphrase prompt" >&2
  fi

  local p1 p2
  if [[ ! -t 0 ]] && command -v osascript >/dev/null 2>&1; then
    p1="$(secrets_gui_prompt "Secrets encryption passphrase:")"
    p2="$(secrets_gui_prompt "Confirm passphrase:")"
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

secrets_filter_aws_credentials() {
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
    sys.exit(2)

Path(dest).parent.mkdir(parents=True, exist_ok=True)
with open(dest, "w", encoding="utf-8") as fh:
    out.write(fh)
print(",".join(included))
PY
}

secrets_stage_file() {
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

secrets_stage_dir() {
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

secrets_stage_bundle() {
  local stage="$1"
  local included=0
  local dest src profiles

  secrets_build_file_entries

  mkdir -p "$stage/secrets"
  : >"$stage/MANIFEST.txt"
  printf 'generated=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$stage/MANIFEST.txt"
  printf 'host=%s\n' "$(hostname -s 2>/dev/null || hostname)" >>"$stage/MANIFEST.txt"
  printf 'backup_target=%s\n' "${BACKUP_TARGET:-unknown}" >>"$stage/MANIFEST.txt"

  for entry in "${FILE_ENTRIES[@]}"; do
    dest="${entry%%|*}"
    src="${entry#*|}"
    if secrets_stage_file "$dest" "$src" "$stage"; then
      included=$((included + 1))
    fi
  done

  for entry in "${DIR_ENTRIES[@]}"; do
    dest="${entry%%|*}"
    src="${entry#*|}"
    if secrets_stage_dir "$dest" "$src" "$stage"; then
      included=$((included + 1))
    fi
  done

  if [[ -f "$HOME/.aws/credentials" ]]; then
    mkdir -p "$stage/secrets/aws"
    if profiles="$(secrets_filter_aws_credentials "$HOME/.aws/credentials" "$stage/secrets/aws/credentials" 2>/dev/null)"; then
      printf 'aws/credentials (profiles: %s)\n' "$profiles" >>"$stage/MANIFEST.txt"
      echo "    include: aws/credentials (profiles: $profiles)"
      included=$((included + 1))
    else
      echo "    skip (no AWS profiles matched allowlist): aws/credentials"
    fi
  else
    echo "    skip (missing): aws/credentials"
  fi

  if [[ "${WITH_GPG:-0}" -eq 1 ]]; then
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

secrets_age_run() {
  local subcmd="$1" pass="$2" out="$3" in="$4"
  local helper="${BACKUP_RUN_ROOT}/scripts/lib/age-passphrase.py"

  [[ -n "$pass" ]] || {
    echo "ERROR: empty passphrase" >&2
    return 1
  }

  if [[ "$subcmd" == "-p" ]]; then
    if printf '%s\n%s\n' "$pass" "$pass" | script -q /dev/null age -p -o "$out" "$in" >/dev/null 2>&1; then
      return 0
    fi
  elif printf '%s\n' "$pass" | script -q /dev/null age -d -o "$out" "$in" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$helper" ]] && python3 "$helper" "$subcmd" "$pass" "$out" "$in" >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: age failed (script and pty helper); run in Terminal" >&2
  return 1
}

secrets_verify_age_zip() {
  local age_file="$1" pass="$2"
  local work dec
  work="$(mktemp -d "${TMPDIR:-/tmp}/secrets-verify.XXXXXX")"
  dec="$work/artifact.zip"
  if ! secrets_age_run -d "$pass" "$dec" "$age_file"; then
    echo "ERROR: age decrypt failed for $age_file" >&2
    rm -rf "$work"
    return 1
  fi
  unzip -t -q "$dec"
  unzip -q "$dec" -d "$work/tree"
  test -s "$work/tree/MANIFEST.txt" || { echo "ERROR: MANIFEST.txt missing" >&2; rm -rf "$work"; return 1; }
  test -d "$work/tree/secrets" || { echo "ERROR: secrets/ missing in zip" >&2; rm -rf "$work"; return 1; }
  local local_count
  local_count="$(find "$work/tree/secrets" -type f | wc -l | tr -d ' ')"
  [[ "$local_count" -gt 0 ]] || { echo "ERROR: empty secrets tree in zip" >&2; rm -rf "$work"; return 1; }
  echo "    verified: $local_count files in bundle"
  rm -rf "$work"
}

secrets_encrypt_zip_to_age() {
  local plain="$1" out="$2" pass="$3"
  if ! secrets_age_run -p "$pass" "$out" "$plain"; then
    echo "ERROR: age encrypt failed → $out" >&2
    return 1
  fi
  [[ -s "$out" ]] || { echo "ERROR: age produced empty output → $out" >&2; return 1; }
  secrets_verify_age_zip "$out" "$pass"
}

secrets_cleanup_stage() {
  [[ -d "${STAGE_ROOT:-}" ]] || return 0
  rm -rf "$STAGE_ROOT"
}

# Fail if plaintext or staging debris remains under secrets/ (only README.md + *.age allowed).
secrets_assert_git_safe() {
  local dir="$1"
  local f base

  local stage_dir
  for stage_dir in "$dir/.stage" "$dir/.stage-cursor-auth"; do
    if [[ -d "$stage_dir" ]]; then
      if find "$stage_dir" -type f -print -quit | grep -q .; then
        echo "ERROR: staging dir not cleaned: $stage_dir" >&2
        return 1
      fi
      echo "ERROR: staging dir still present: $stage_dir" >&2
      return 1
    fi
  done

  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    case "$base" in
      README.md) ;;
      *.age) ;;
      *)
        echo "ERROR: plaintext or unexpected file under secrets/: $f" >&2
        echo "       only README.md and *.age may remain in git" >&2
        return 1
        ;;
    esac
  done < <(find "$dir" -type f -print0)
}
