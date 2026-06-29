#!/usr/bin/env bash
# Postman local config (collections sync via Postman account when signed in).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

BACKUP_ROOT="$(resolve_backup_root)"
POSTMAN_SRC="$HOME/Library/Application Support/Postman"
DEST="$BACKUP_ROOT/configs/postman"

if [[ ! -d "$POSTMAN_SRC" ]]; then
    log_skip "Postman not installed"
    exit 0
fi

mkdir -p "$DEST/Postman_Config" "$DEST/storage"

if [[ -d "$POSTMAN_SRC/Postman_Config" ]]; then
    rm -rf "$DEST/Postman_Config"
    cp -R "$POSTMAN_SRC/Postman_Config" "$DEST/Postman_Config"
    find "$DEST/Postman_Config" -name '.DS_Store' -delete 2>/dev/null || true
    log_ok "Postman_Config"
else
    log_skip "Postman_Config missing"
fi

for f in settings.json userPartitionData.json; do
    if [[ -f "$POSTMAN_SRC/storage/$f" ]]; then
        cp "$POSTMAN_SRC/storage/$f" "$DEST/storage/$f"
        log_ok "storage/$f"
    fi
done

cat >"$DEST/README.txt" <<'EOF'
Postman backup scope (local only)
=================================
- Postman_Config/: user feature flags and partition configs
- storage/: app settings and partition metadata

Collections, environments, and history sync via your Postman account after sign-in.
On a new Mac: install Postman → sign in with the same account.
EOF

log_ok "configs/postman/ (local prefs; collections via cloud sign-in)"
