# backup-run

Git-integrated macOS backup orchestrator. Fork of [shallow-backup](https://github.com/alichtman/shallow-backup), trimmed for a single-machine workflow.

## Layout

| Path | Role |
|------|------|
| `~/dev/repos/zzz/backup-run` | This repo — tool, manifest, shell extras |
| `~/dev/repos/zzz/backup` | Data repo — dotfiles, configs, packages, `manual/` (private git) |

## Install

**Runtime (recommended):**

```bash
pipx install -e ~/dev/repos/zzz/backup-run
chmod +x ~/dev/repos/zzz/backup-run/backup
```

After dependency changes: `pipx reinstall backup-run`.

**Development:**

```bash
cd ~/dev/repos/zzz/backup-run
uv sync
uv run backup-run --version
```

## Usage

```bash
backup          # alias → ~/dev/repos/zzz/backup-run/backup
backup -s       # include sudo sfltool login-item dump (prompts if needed)
backup-run --backup-all --skip-git   # sync only (no git)
```

`backup` runs: sync → `scripts/backup_extras.sh` → one git commit/push in the data repo.

## Config

`manifest/backup-run.conf` — JSON manifest: `backup_path`, `dotfiles`, `config_mapping`, gitignore rules. Edit in the tool repo; no copy under `~/.config`.

**Inventory:** [docs/BACKUP-INVENTORY.md](docs/BACKUP-INVENTORY.md) — human-readable list of what is backed up, excluded, and manual.

**Restore:** `~/dev/repos/zzz/bootstrap/skills/migrate-mac/SKILL.md` — canonical, agent-driven restore procedure. It audits the current manifest and backup contents on every run so new backup coverage is surfaced before restore.

> **`--reinstall-*` is deprecated and disabled.** Every reinstall flag prints a deprecation notice and exits 1 without touching the filesystem. Restore never worked end to end, and writing into a live `$HOME`/`Library` is too dangerous to leave reachable. The implementations stay in `src/backup_run/reinstall.py` for reference only. Use the `migrate-mac` skill instead.

## Extras (not in Python sync)

Shell orchestration under `scripts/`; Python helpers under `src/backup_run/extras/`. Runtime deps: `git`, Python 3.11+, **PyYAML** (via `uv sync` or `pipx install -e .`), and `manifest/backup-run.conf`.

`scripts/backup_extras.sh`: pnpm/mise/pipx/uv/fnm lists, Cursor + VS Code extension lists, macOS plists, Chrome bookmarks/inventory, dev layout, Postman prefs. Homebrew `Brewfile` is written by the Python sync (`--no-vscode`).

Manual reference docs (`manual/apps.md`) live in the **backup data repo** only — edit there, not in backup-run.

## Dev

```bash
uv run ruff check .
uv run ruff format .
uv build
```

## Weekly cron

`zsh-env/tasks/crontab/weekly.sh` calls `backup`.

## Related repos

- `bootstrap` — owns the canonical `migrate-mac` restore skill
- `kb/agents` — Cursor hooks/rules/skills (separate git push via `init.sh`)
- `zsh-env` — shell config (separate git push)
