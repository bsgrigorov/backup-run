# Shared helpers for backup-run scripts. Source from scripts/*.sh — do not execute directly.
_TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run Python with backup-run deps (PyYAML, etc.).
run_tool_python() {
    if [[ -n "${BACKUP_RUN_PYTHON:-}" ]]; then
        "$BACKUP_RUN_PYTHON" "$@"
        return $?
    fi
    if [[ -x "${_TOOL_ROOT}/.venv/bin/python" ]]; then
        "${_TOOL_ROOT}/.venv/bin/python" "$@"
        return $?
    fi
    local pipx_venv="${HOME}/.local/pipx/venvs/backup-run/bin/python"
    if [[ -x "$pipx_venv" ]] && "$pipx_venv" -c "import yaml" 2>/dev/null; then
        "$pipx_venv" "$@"
        return $?
    fi
    if command -v uv >/dev/null 2>&1 && [[ -f "${_TOOL_ROOT}/pyproject.toml" ]]; then
        uv run --directory "$_TOOL_ROOT" python "$@"
        return $?
    fi
    if python3 -c "import backup_run.config, yaml" 2>/dev/null; then
        python3 "$@"
        return $?
    fi
    echo "backup-run: backup_run + PyYAML not found — run: uv sync (in $_TOOL_ROOT) or pipx reinstall backup-run" >&2
    return 1
}

resolve_backup_root() {
    if [[ -n "${BACKUP_ROOT:-}" ]]; then
        printf '%s' "$BACKUP_ROOT"
        return 0
    fi
    run_tool_python -c 'from backup_run.config import get_config; print(get_config()["backup_path"])'
}

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
log_ok() { echo -e "${GREEN}✓${NC} ${BLUE}$1${NC}"; }
log_skip() { echo "⚠️  skip: $1"; }
