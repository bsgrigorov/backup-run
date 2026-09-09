#!/usr/bin/env bash
# Restore Cursor auth from cursor-auth-bundle.tar.age (or git path).
#
# Usage:
#   ./scripts/cursor-auth-restore.sh --confirm
#   ./scripts/cursor-auth-restore.sh --confirm /path/to/cursor-auth-bundle.tar.age
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_RUN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
# shellcheck source=lib/secrets-bundle.sh
source "$SCRIPT_DIR/lib/secrets-bundle.sh"
# shellcheck source=lib/cursor-auth.sh
source "$SCRIPT_DIR/lib/cursor-auth.sh"

CONFIRM=0
AGE_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --confirm [bundle.tar.age]

Restore Cursor IDE/CLI auth from age bundle. Default bundle:
  <backup>/<BACKUP_TARGET>/secrets/cursor-auth-bundle.tar.age

Quit Cursor before running. Overwrites existing Cursor auth on this Mac.
Docs: docs/CURSOR-AUTH-BACKUP.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      AGE_FILE="$1"
      shift
      ;;
  esac
done

[[ "$CONFIRM" -eq 1 ]] || {
  echo "ERROR: pass --confirm to restore (overwrites Cursor auth)" >&2
  exit 1
}

if ! command -v age >/dev/null 2>&1; then
  echo "ERROR: age not found" >&2
  exit 1
fi

MACHINE_ROOT="$(resolve_backup_root)"
cursor_auth_init_paths
AGE_FILE="${AGE_FILE:-$OUT_AGE}"

[[ -f "$AGE_FILE" ]] || {
  echo "ERROR: bundle not found: $AGE_FILE" >&2
  exit 1
}

[[ -f "$CURSOR_STATE_DB" ]] || {
  echo "ERROR: open Cursor once on this Mac (creates state.vscdb), quit, then retry" >&2
  exit 1
}

cursor_auth_require_quit

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cursor-auth-restore.XXXXXX")"
TAR="$WORK/bundle.tar"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

PASS="$(secrets_resolve_passphrase)"
[[ -n "$PASS" ]] || { echo "ERROR: empty passphrase" >&2; exit 1; }

echo "==> cursor-auth-restore"
echo "    from: $AGE_FILE"
echo "==> decrypting"
secrets_age_run -d "$PASS" "$TAR" "$AGE_FILE"
unset PASS
cursor_auth_verify_tar "$TAR"

echo "==> extracting"
tar -xf "$TAR" -C "$STAGE"
[[ -f "$STAGE/manifest.json" ]] && echo "    manifest: $(<"$STAGE/manifest.json" | python3 -c 'import json,sys; m=json.load(sys.stdin); print(m.get("hostname","?"), m.get("created","?"))')"

echo "==> importing sqlite rows"
count="$(python3 "$IO_PY" import "$CURSOR_STATE_DB" "$STAGE")"
echo "    imported: $count rows"

cursor_auth_merge_storage_telemetry "$STAGE"
cursor_auth_merge_cli_config "$STAGE"

[[ -f "$STAGE/cli/auth.json" ]] && mkdir -p "$(dirname "$CURSOR_CLI_AUTH")" && install -m 600 "$STAGE/cli/auth.json" "$CURSOR_CLI_AUTH" && echo "    restored cli/auth.json"
[[ -f "$STAGE/sdk/auth.json" ]] && mkdir -p "$(dirname "$CURSOR_SDK_AUTH")" && install -m 600 "$STAGE/sdk/auth.json" "$CURSOR_SDK_AUTH" && echo "    restored sdk/auth.json"

echo "==> keychain"
cursor_auth_restore_keychain "$STAGE"

echo "==> done — open Cursor and verify Settings account, Agent, MCP, GitHub extension"
