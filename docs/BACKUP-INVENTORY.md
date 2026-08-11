# What gets backed up

Human-readable inventory for Bobby's Mac. Source of truth for paths: `manifest/backup-run.conf`. Run everything with:

```bash
backup        # daily — no sudo-only steps
backup -s     # weekly — includes sfltool login items (sudo prompts if needed)
```

Data lands in `~/dev/repos/zzz/backup/` (`bsgrigorov/backup`, private GitHub). The `./backup` script syncs, runs extras, then one commit+push.

---

## Committed to git (safe to push)

### Shell and editor dotfiles

| Source | Backup path |
|--------|-------------|
| `~/.zshrc`, `.zshenv`, `.zprofile`, `.bashrc`, `.profile` | `dotfiles/` |
| `~/.gitconfig`, `.gitignore_global`, `.inputrc`, `.viminfo` | `dotfiles/` |
| `~/.npmrc` | **Not backed up** — contains registry tokens |
| `~/.yarnrc.yml` | `dotfiles/` |

### Cloud and infra configs

| Source | Backup path | Notes |
|--------|-------------|-------|
| `~/.aws/config` | `dotfiles/.aws/` | **Not** `credentials` |
| `~/.kube/config` | `dotfiles/.kube/` | Cluster access; private repo only |
| `~/.docker/config.json` | `dotfiles/.docker/` | Uses macOS keychain for auth |
| `~/.cloudflared/config.yml` | `dotfiles/.cloudflared/` | |
| `~/.colima/_templates/default.yaml` | `dotfiles/.colima/` | |
| `~/.config/aws-sso/config.yaml` | `dotfiles/.config/aws-sso/` | |
| `~/.config/argocd/config` | `dotfiles/.config/argocd/` | |
| `~/.config/k9s/` | `dotfiles/.config/k9s/` | |
| `~/.config/karabiner/karabiner.json` | `dotfiles/.config/karabiner/` | |
| `~/.config/gh/config.yml` | `dotfiles/.config/gh/` | No tokens in file |
| `~/.config/gcloud/configurations/` only | `dotfiles/.config/gcloud/configurations/` | **Non-secret** named configs (accounts, project defaults). **Not** `access_tokens.db`, `credentials.db`, ADC, or `legacy_credentials/` — re-auth on new Mac |
| `~/.config/wireshark/`, `k3d/`, `htop/` | `dotfiles/.config/…` | |
| `~/.config/ghostty/config` | `dotfiles/.config/ghostty/` | Keybinds/UI only — safe to commit. Do not back up scrollback/caches. |

### App settings (plist + Application Support)

| App | Backup path |
|-----|-------------|
| Cursor — settings, keybindings, snippets | `configs/cursor/` |
| VS Code — settings, keybindings, snippets | `configs/vscode/` |
| iTerm2 — plist + Application Support | `configs/iterm2/` |
| Terminal.app | `configs/terminal_plist` |
| Alfred (both plists) | `configs/alfred/` |
| BetterTouchTool — plist + app support | `configs/bettertouchtool/` |
| Raycast | `configs/raycast/` |
| Stats | `configs/stats/` |
| BetterDisplay | `configs/betterdisplay/` |
| LaunchAgents | `configs/launchagents/` |

### Cursor extras (shell script)

| Source | Backup path |
|--------|-------------|
| `cursor --list-extensions --show-versions` | `configs/cursor/extensions.list` |
| `~/.cursor/argv.json`, `sandbox.json` | `configs/cursor/cli/` |

Hooks, rules, skills → **`kb/agents`** (separate repo).

### Package manifests (Python sync + extras)

| Tool | File(s) in `packages/` |
|------|-------------------------|
| Homebrew | `Brewfile` (canonical, extras `--force --describe`), plus `brew_cask_list.txt` / `brew_tap_list.txt` for quick diffs |
| npm / VS Code extensions | `npm_list.txt`, `vscode_list.txt` |
| gem, cargo, pip, pip3 | `gem_list.txt`, `cargo_list.txt`, `pip_list.txt`, `pip3_list.txt` |
| pnpm, mise, asdf, pipx, uv, fnm | `pnpm_list.txt`, `mise_list.txt`, `asdf_current.txt`, `pipx_list.txt`, `uv_tools_list.txt`, `fnm_list.txt` |
| Installed apps | `system_apps_list.txt` (`ls /Applications`, Python sync) |

### macOS system snapshot (extras)

| Output | Backup path |
|--------|-------------|
| Dock, Finder, hotkeys, keyboard, trackpad, accessibility, screensaver, loginwindow | `configs/macos-system/*.plist` |
| `.GlobalPreferences.plist` | `configs/macos-system/` |
| Login items (osascript) | `configs/macos-system/login-items-osascript.txt` |
| Login items (sfltool, **sudo**) | `configs/macos-system/login-items-sfltool.txt` |

TCC permissions (Accessibility, Input Monitoring, etc.) are **manual** — not captured.

### Chrome bookmarks

| Source | Backup path |
|--------|-------------|
| Each Chrome profile `Bookmarks` → HTML | `configs/chrome/bookmarks/*.html` |

### Chrome inventory (extras)

Simple `ls` per profile on each `backup` run. Extension folder names are Chrome extension IDs; full state syncs when you sign in to the profile.

| Source | Backup path |
|--------|-------------|
| Profile dirs (`Default`, `Profile *`) | `configs/chrome/inventory/profiles.txt` |
| Per profile: `Extensions/`, `Web Applications/`, manifest resources | `configs/chrome/inventory/<profile>__<name>/*_ls.txt` |

### Dev filesystem layout (extras)

Programmatic snapshot on every `backup` run. Worktree checkouts are **excluded** from the repo index; only umbrella dirs (e.g. `worktrees/`, `sandbox/`) appear in the skeleton.

| Source | Backup path |
|--------|-------------|
| Git walk under `~/dev/repos` — `repo`, `url` (https), `path` per checkout | `layouts/repos_map.yaml` |
| `~/dev/` and `~/dev/repos/` folder tree (no git URLs) | `layouts/dev_layout.yaml` |
| `~/dev/repos/*.code-workspace` | `configs/workspaces/` |

Restore: recreate umbrella dirs from `dev_layout.yaml`, clone from `repos_map.yaml` (or future `bootstrap/repos.yaml`), open workspaces from `configs/workspaces/`.

### Postman (local prefs)

| Source | Backup path | Notes |
|--------|-------------|-------|
| `~/Library/Application Support/Postman/Postman_Config/` | `configs/postman/Postman_Config/` | User/partition prefs |
| `Postman/storage/settings.json`, `userPartitionData.json` | `configs/postman/storage/` | |
| Collections / environments | — | **Cloud-synced** — sign in to Postman on new Mac |

### Manual reference (data repo)

| Location | Purpose |
|----------|---------|
| `manual/apps.md` in **backup data repo** | Per-app reinstall notes — edit in `~/dev/repos/zzz/backup/manual/` |

Not synced from backup-run; the data repo is the single source of truth.

---

## Copied locally, never committed

These are synced to `dotfiles/` for restore on disk but **gitignored**:

| Source | Why excluded |
|--------|--------------|
| `~/.ssh/` (incl. private keys) | Secrets — use 1Password + encrypted external |
| `~/.cursor/mcp.json` | API keys / MCP secrets |
| `~/.claude.json` | Local Claude state, may contain sensitive config |
| `~/.aws/credentials` | Long-lived keys if present |

Public SSH (`config`, `known_hosts`, `*.pub`) could be committed later; whole `.ssh` dir is ignored for simplicity.

---

## Not backed up here

| What | Where instead |
|------|----------------|
| Shell config, aliases, crontab | `zsh-env` repo |
| Cursor/Claude rules, skills, hooks | `kb/agents` |
| `~/.zsh_history` | Too sensitive (tokens in commands); not in manifest |
| `~/.npmrc` | Registry auth tokens |
| GPG secret keys | 1Password + encrypted external |
| `zsh-env/shell/secret/` | 1Password or backup disk |
| Google Drive `backup/` folder | Manual sync for large blobs |
| All source repos | GitHub (`git push`) |
| 1Password vault | Native sync |

---

## Manual before migration

1. Run `backup` or `backup -s`
2. Push `kb/agents`, `zsh-env`, and any active project repos
3. Copy `zsh-env/shell/secret/` to 1Password
4. Verify 1Password fully synced
5. Optional: sync Google Drive `backup/` folder

---

## Security checklist

- [ ] Private repo only (`bsgrigorov/backup`)
- [ ] Never commit `.npmrc`, `.zsh_history`, or PATs in shell history
- [ ] Rotate tokens if they ever appeared in git history
- [ ] SSH private keys in 1Password, not in this repo
