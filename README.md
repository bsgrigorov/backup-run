# backup-run

Git-integrated macOS backup orchestrator. Fork of [shallow-backup](https://github.com/alichtman/shallow-backup), trimmed for a single-machine workflow.

## Layout

| Path | Role |
|------|------|
| `~/dev/repos/zzz/backup-run` | This repo — tool + manifest |
| `~/dev/repos/zzz/backup` | Data repo — dotfiles, configs, packages (private git) |

## Install

```bash
pipx install -e ~/dev/repos/zzz/backup-run
chmod +x ~/dev/repos/zzz/backup-run/bin/backup
```

Copy or symlink config:

```bash
cp manifest/backup-run.conf ~/.config/backup-run.conf
# legacy shallow-backup.conf still works
```

## Usage

```bash
backup          # alias → bin/backup
backup -s       # include sudo sfltool login-item dump (run sudo -v first)
backup-run --backup-all --skip-git   # sync only (no git)
```

`bin/backup` runs: sync → `scripts/backup_extras.sh` → one git commit/push in the data repo.

## Config

`~/.config/backup-run.conf` — JSON manifest: `backup_path`, `dotfiles`, `config_mapping`, gitignore rules.

Canonical manifest copy: `manifest/backup-run.conf`.

## Extras (not in Python sync)

`scripts/backup_extras.sh`: brew casks/taps/Brewfile, pnpm/mise/asdf/pipx/uv/fnm, Cursor extensions, macOS defaults plists, Chrome bookmarks HTML.

## Weekly cron

`zsh-env/tasks/crontab/weekly.sh` calls `backup`.

## Related repos

- `kb/agents` — Cursor hooks/rules/skills (separate git push via `init.sh`)
- `zsh-env` — shell config (separate git push)
