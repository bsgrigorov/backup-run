# What gets backed up

Human-readable inventory for Bobby's Mac. Source of truth for paths: `manifest/backup-run.conf`. Run everything with:

```bash
backup        # daily — no sudo-only steps
backup -s     # weekly — includes sfltool login items (sudo prompts if needed)
```

Data lands in `~/dev/repos/zzz/backup/` (`bsgrigorov/backup`, private GitHub). The `./backup` script syncs, runs extras, then one commit+push.

`config_mapping` and `dotfiles` are **allowlists**. Directory copies are also capped by `max_copy_dir_mb` (default 50) so a mistaken large path cannot dump caches into the repo.

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
| `~/.claude.json` | `dotfiles/` | Claude Code local state (profile metadata, MCP entries, project usage). Private repo only — contains email/org IDs, not API tokens. |
| `~/.codex/config.toml` | `dotfiles/.codex/` | Model/plugins. **Not** `auth.json` (gitignored if present). |
| `~/.conductor/settings.toml` | `dotfiles/.conductor/` | Tiny non-secret defaults. |

### App settings (plist + Application Support)

| App | Backup path |
|-----|-------------|
| Cursor — settings, keybindings, snippets, extensions.list | `configs/cursor/` |
| VS Code — settings, keybindings, snippets, extensions.list | `configs/vscode/` |
| iTerm2 — plist + Application Support | `configs/iterm2/` |
| Terminal.app | `configs/terminal_plist` |
| Alfred (both plists) | `configs/alfred/` |
| BetterTouchTool — plist + app support | `configs/bettertouchtool/` |
| Raycast | `configs/raycast/` (plist + extensions.list) |
| Stats | `configs/stats/` |
| BetterDisplay | `configs/betterdisplay/` |
| Time Out | `configs/timeout/` |
| LaunchAgents | `configs/launchagents/` |

### Cursor extras (shell script)

| Source | Backup path | Notes |
|--------|-------------|-------|
| `cursor --list-extensions --show-versions` | `configs/cursor/extensions.list` | |
| `code` (unaliased; skip if path is cursor) | `configs/vscode/extensions.list` | Not in Brewfile (`--no-vscode`) |
| `~/.cursor/mcp.json` | `dotfiles/.cursor/` | Committed. Currently gcloud MCP only (no tokens). Re-check if you add API keys. |
| `~/.cursor/argv.json`, `sandbox.json` | `configs/cursor/cli/` + `dotfiles/.cursor/` | Duplicated paths — fine for now |

### Raycast restore (important)

Plist + `extensions.list` are **not** a full restore. Hotkeys, aliases, snippets, AI chats, etc. live in Raycast’s encrypted store.

| Method | What | Notes |
|--------|------|-------|
| **Export Settings & Data** | `.rayconfig` (encrypted, passphrase) | Run in Raycast; save under `backup/custom_backups/raycast/` (or GDrive). Jan 2026 export is stale — re-export. |
| **Scheduled Export** (Pro) | Auto `.rayconfig` to a folder | Settings → Advanced → Export; point at `custom_backups/raycast/` or a sync folder |
| **Cloud Sync** (Pro) | Cross-device | Settings → Cloud Sync; still keep a `.rayconfig` backup |
| **Do not** | Copy `~/.config/raycast/extensions` (415MB) or `raycast-enc.sqlite` | Store installs + encrypted DB; size cap would refuse anyway |

Hooks, rules, skills → **`kb/agents`** (separate repo).

### Package manifests (Python sync + extras)

| Tool | File(s) in `packages/` |
|------|-------------------------|
| Homebrew | `Brewfile` (canonical, `--force --no-vscode`), plus `brew_cask_list.txt` / `brew_tap_list.txt` for quick diffs |
| npm | `npm_list.txt` |
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
| `~/.ssh/` (incl. private keys) | **Not copied.** Removed from manifest. Live keys → 1Password SSH Key; optional Drive `ssh-id_ed25519.age`. Gitignore still blocks `dotfiles/.ssh` if anything lands there. |
| `~/.codex/auth.json` | Codex credentials |
| `~/.aws/credentials` | Long-lived keys if present |

Public SSH (`config`, `known_hosts`, `*.pub`) are easy to recreate; private keys stay out of this repo entirely.

---

## Not backed up here

| What | Where instead |
|------|----------------|
| Shell config, aliases, crontab | `zsh-env` repo |
| Cursor/Claude rules, skills, hooks | `kb/agents` |
| MCP tokens / API keys in `mcp.json` | Prefer env/1P — current file has none; do not commit secrets |
| `~/.zsh_history` | Too sensitive (tokens in commands); not in manifest |
| `~/.npmrc` | Registry auth tokens |
| GPG secret keys | 1Password + encrypted external — **procedure:** `backup/manual/gpg.md` |
| SSH private keys | 1Password SSH Key + optional Drive `.age` — **procedure:** `backup/manual/ssh.md` |
| `zsh-env/shell/secret/` | 1Password or backup disk |
| Google Drive `backup/` folder | Manual sync for large blobs |
| All source repos | GitHub (`git push`) |
| 1Password vault | Native sync |

---

## Manual before migration

1. Run `backup` or `backup -s`
2. Push `kb/agents`, `zsh-env`, and any active project repos
3. Copy `zsh-env/shell/secret/` to 1Password
4. Confirm SSH + GPG backups per `backup/manual/ssh.md` and `backup/manual/gpg.md` (1P items present; optional Drive `.age` refreshed)
5. Verify 1Password fully synced
6. Optional: sync Google Drive `Documents/Backup` folder

---

## Security checklist

- [ ] Private repo only (`bsgrigorov/backup`)
- [ ] Never commit `.npmrc`, `.zsh_history`, or PATs in shell history
- [ ] Rotate tokens if they ever appeared in git history
- [ ] SSH private keys in 1Password (+ optional Drive `.age`), not in this repo — see `backup/manual/ssh.md`
- [ ] GPG secret export in 1Password — see `backup/manual/gpg.md`