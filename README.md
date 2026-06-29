# backup-run

Git-integrated macOS backup orchestrator. Fork of [shallow-backup](https://github.com/alichtman/shallow-backup), trimmed for a single-machine workflow.

## Layout

| Path | Role |
|------|------|
| `~/dev/repos/zzz/backup-run` | This repo — tool + manifest |
| `~/dev/repos/zzz/backup` | Data repo — dotfiles, configs, packages (private git) |

## Install

**Runtime (recommended):**

```bash
pipx install -e ~/dev/repos/zzz/backup-run
chmod +x ~/dev/repos/zzz/backup-run/backup
```

**Development:**

```bash
cd ~/dev/repos/zzz/backup-run
uv sync
uv run backup-run --version
```

## Usage

```bash
backup          # alias → ~/dev/repos/zzz/backup-run/backup
backup -s       # include sudo sfltool login-item dump (run sudo -v first)
backup-run --backup-all --skip-git   # sync only (no git)
```

`backup` runs: sync → `scripts/backup_extras.sh` → one git commit/push in the data repo.

## Config

`manifest/backup-run.conf` — JSON manifest: `backup_path`, `dotfiles`, `config_mapping`, gitignore rules. Edit in the tool repo; no copy under `~/.config`.

**Inventory:** [docs/BACKUP-INVENTORY.md](docs/BACKUP-INVENTORY.md) — human-readable list of what is backed up, excluded, and manual.

## Extras (not in Python sync)

`scripts/backup_extras.sh`: brew casks/taps/Brewfile, pnpm/mise/asdf/pipx/uv/fnm, Cursor extensions, macOS defaults plists, Chrome bookmarks HTML.

## Dev

```bash
uv run ruff check .
uv run ruff format .
uv build
```

## Weekly cron

`zsh-env/tasks/crontab/weekly.sh` calls `backup`.

## Related repos

- `kb/agents` — Cursor hooks/rules/skills (separate git push via `init.sh`)
- `zsh-env` — shell config (separate git push)
