#!/usr/bin/env bash
# Cursor auth backup/restore helpers. Source from scripts/cursor-auth-*.sh — do not execute.
set -euo pipefail

CURSOR_GLOBAL_STORAGE="${HOME}/Library/Application Support/Cursor/User/globalStorage"
CURSOR_STATE_DB="${CURSOR_GLOBAL_STORAGE}/state.vscdb"
CURSOR_STORAGE_JSON="${CURSOR_GLOBAL_STORAGE}/storage.json"
CURSOR_CLI_CONFIG="${HOME}/.cursor/cli-config.json"
CURSOR_CLI_AUTH="${HOME}/.cursor/auth.json"
CURSOR_SDK_AUTH="${HOME}/.cursor/sdk/auth.json"

CURSOR_KEYCHAIN_SERVICES=(
  cursor-access-token
  cursor-refresh-token
  cursor-api-key
  cursorvscode.github-authentication
)

cursor_auth_cursor_running() {
  pgrep -qx Cursor 2>/dev/null || pgrep -f "[/]Cursor\\.app" >/dev/null 2>&1
}

cursor_auth_require_quit() {
  if cursor_auth_cursor_running; then
    echo "ERROR: quit Cursor fully before cursor-auth backup/restore" >&2
    exit 1
  fi
}

cursor_auth_init_paths() {
  : "${MACHINE_ROOT:?}"
  : "${BACKUP_RUN_ROOT:?}"
  CURSOR_AUTH_DIR="$MACHINE_ROOT/cursor-auth"
  STAGE_ROOT="$CURSOR_AUTH_DIR/.stage"
  STAGE_WORK="$STAGE_ROOT/workspace"
  PLAIN_TAR="$STAGE_ROOT/bundle.tar"
  OUT_AGE="$CURSOR_AUTH_DIR/cursor-auth-bundle.tar.age"
  OUT_AGE_TMP="$STAGE_ROOT/cursor-auth-bundle.tar.age.tmp"
  IO_PY="${BACKUP_RUN_ROOT}/scripts/lib/cursor-auth-io.py"
}

cursor_auth_cleanup_stage() {
  [[ -d "${STAGE_ROOT:-}" ]] || return 0
  find "$STAGE_ROOT" -type f -delete 2>/dev/null || true
  find "$STAGE_ROOT" -depth -type d -empty -delete 2>/dev/null || true
  rmdir "$STAGE_ROOT" 2>/dev/null || true
}

cursor_auth_assert_git_safe() {
  local dir="$1" f base
  if [[ -d "$dir/.stage" ]]; then
    echo "ERROR: staging dir still present: $dir/.stage" >&2
    return 1
  fi
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    case "$base" in
      README.md) ;;
      *.age) ;;
      *)
        echo "ERROR: plaintext under cursor-auth/: $f" >&2
        return 1
        ;;
    esac
  done < <(find "$dir" -type f -print0)
}

cursor_auth_export_keychain() {
  local stage="$1" svc account
  mkdir -p "$stage/keychain"
  for svc in "${CURSOR_KEYCHAIN_SERVICES[@]}"; do
    if ! security find-generic-password -s "$svc" >/dev/null 2>&1; then
      echo "    skip keychain: $svc"
      continue
    fi
    account="$(security find-generic-password -s "$svc" 2>/dev/null | awk -F'"' '/"acct"/ {print $4; exit}')"
    [[ -n "$account" ]] || account="cursor-user"
    security find-generic-password -s "$svc" -w >"$stage/keychain/${svc}.secret"
    printf '%s' "$account" >"$stage/keychain/${svc}.account"
    chmod 600 "$stage/keychain/${svc}.secret" "$stage/keychain/${svc}.account"
    echo "    include keychain: $svc ($account)"
  done
}

cursor_auth_stage_bundle() {
  local stage="$1" row_count

  [[ -f "$CURSOR_STATE_DB" ]] || {
    echo "ERROR: Cursor state DB missing: $CURSOR_STATE_DB" >&2
    echo "       open Cursor once on this Mac, then quit and retry" >&2
    exit 1
  }

  mkdir -p "$stage/sqlite" "$stage/cli"
  cursor_auth_export_keychain "$stage"
  row_count="$(python3 "$IO_PY" export "$CURSOR_STATE_DB" "$stage")"
  echo "    include sqlite: $row_count ItemTable rows"

  if [[ -f "$CURSOR_STORAGE_JSON" ]] && command -v jq >/dev/null 2>&1; then
    jq '{
      telemetry: {
        machineId: .telemetry.machineId,
        macMachineId: .telemetry.macMachineId,
        devDeviceId: .telemetry.devDeviceId,
        sqmId: .telemetry.sqmId
      }
    }' "$CURSOR_STORAGE_JSON" >"$stage/storage.telemetry.json"
    echo "    include: storage.telemetry.json"
  fi

  if [[ -f "$CURSOR_CLI_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    jq '{authInfo, statsigBootstrap}' "$CURSOR_CLI_CONFIG" >"$stage/cli-config.slices.json"
    echo "    include: cli-config.slices.json"
  fi

  [[ -f "$CURSOR_CLI_AUTH" ]] && cp -p "$CURSOR_CLI_AUTH" "$stage/cli/auth.json" && echo "    include: cli/auth.json"
  [[ -f "$CURSOR_SDK_AUTH" ]] && mkdir -p "$stage/sdk" && cp -p "$CURSOR_SDK_AUTH" "$stage/sdk/auth.json" && echo "    include: sdk/auth.json"
}

cursor_auth_verify_tar() {
  local tar_file="$1"
  tar -tf "$tar_file" | grep -q '^manifest\.json$' || {
    echo "ERROR: manifest.json missing in bundle" >&2
    return 1
  }
  tar -tf "$tar_file" | grep -q 'sqlite/itemtable\.json$' || {
    echo "ERROR: sqlite/itemtable.json missing in bundle" >&2
    return 1
  }
  echo "    verified: cursor-auth bundle structure"
}

cursor_auth_encrypt_tar_to_age() {
  local plain="$1" out="$2" pass="$3"
  # shellcheck source=secrets-bundle.sh
  source "${BACKUP_RUN_ROOT}/scripts/lib/secrets-bundle.sh"
  if ! secrets_age_run -p "$pass" "$out" "$plain"; then
    echo "ERROR: age encrypt failed → $out" >&2
    return 1
  fi
  [[ -s "$out" ]] || { echo "ERROR: empty age output" >&2; return 1; }
  local work dec
  work="$(mktemp -d "${TMPDIR:-/tmp}/cursor-auth-verify.XXXXXX")"
  dec="$work/bundle.tar"
  if ! secrets_age_run -d "$pass" "$dec" "$out"; then
    rm -rf "$work"
    return 1
  fi
  cursor_auth_verify_tar "$dec"
  rm -rf "$work"
}

cursor_auth_restore_keychain() {
  local stage="$1" svc account secret_file account_file
  for svc in "${CURSOR_KEYCHAIN_SERVICES[@]}"; do
    secret_file="$stage/keychain/${svc}.secret"
    account_file="$stage/keychain/${svc}.account"
    [[ -f "$secret_file" ]] || continue
    account="cursor-user"
    [[ -f "$account_file" ]] && account="$(<"$account_file")"
    security delete-generic-password -s "$svc" -a "$account" >/dev/null 2>&1 || true
    security add-generic-password -s "$svc" -a "$account" -w "$(<"$secret_file")" -U >/dev/null
    echo "    restored keychain: $svc"
  done
}

cursor_auth_merge_cli_config() {
  local stage="$1"
  [[ -f "$stage/cli-config.slices.json" && -f "$CURSOR_CLI_CONFIG" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local merged
  merged="$(jq -s '.[0] * {authInfo: .[1].authInfo, statsigBootstrap: .[1].statsigBootstrap}' \
    "$CURSOR_CLI_CONFIG" "$stage/cli-config.slices.json")"
  printf '%s\n' "$merged" >"$CURSOR_CLI_CONFIG"
  echo "    merged cli-config.json auth slices"
}

cursor_auth_merge_storage_telemetry() {
  local stage="$1"
  [[ -f "$stage/storage.telemetry.json" && -f "$CURSOR_STORAGE_JSON" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local merged
  merged="$(jq -s '.[0] * {telemetry: (.[0].telemetry // {}) * .[1].telemetry}' \
    "$CURSOR_STORAGE_JSON" "$stage/storage.telemetry.json")"
  printf '%s\n' "$merged" >"$CURSOR_STORAGE_JSON"
  echo "    merged storage.json telemetry fields"
}
