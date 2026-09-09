# Cursor auth backup & restore

Deterministic backup/restore for **Cursor login state only** (not chat history or full `state.vscdb`). Ported from `kb/agents/skills/cursor-auth-backup/`.

**Unsupported by Cursor.** Enterprise SSO policy may forbid token export. Tokens expire; dual-machine use can rotate refresh tokens.

## What is backed up

| Source | Contents |
|--------|----------|
| `state.vscdb` ItemTable | `cursorAuth/*`, `storage.serviceMachineId`, GitHub extension secrets, MCP OAuth rows |
| `storage.json` | telemetry device IDs (optional) |
| `~/.cursor/cli-config.json` | `authInfo`, `statsigBootstrap` |
| Keychain | `cursor-access-token`, `cursor-refresh-token`, `cursor-api-key`, `cursorvscode.github-authentication` |
| `~/.cursor/auth.json`, `sdk/auth.json` | if present |

**Not included:** chat (`cursorDiskKV`), full DB copy, `gh` CLI config, `mcp.json` (config only; tokens are in SQLite).

## Paths (per machine)

| | Path |
|---|------|
| Git artifact | `backup/<BACKUP_TARGET>/cursor-auth/cursor-auth-bundle.tar.age` |
| Staging (gitignored) | `backup/<BACKUP_TARGET>/cursor-auth/.stage/` |
| Drive (optional) | `…/Backup/cursor-auth-<BACKUP_TARGET>.tar.age` |

Passphrase: same as secrets — `op://Personal/drive-backup/password` (default when `op` is available).

## Backup

**Prerequisite:** Quit Cursor fully (no Cursor processes in Activity Monitor).

```bash
backup --cursor-auth                    # sync + extras + cursor auth + git commit
# Or standalone:
./scripts/cursor-auth-backup.sh --verify
./scripts/cursor-auth-backup.sh --no-drive --verify
```

`backup --cursor-auth` does **not** run `--secrets`; combine flags if needed: `backup --secrets --cursor-auth`.

## Restore

**Prerequisite:** Cursor installed; open and quit once so `state.vscdb` exists. Quit again before restore.

```bash
./scripts/cursor-auth-restore.sh --confirm
# Or explicit bundle:
./scripts/cursor-auth-restore.sh --confirm ~/dev/repos/zzz/backup/macbook-pro-2023/cursor-auth/cursor-auth-bundle.tar.age
```

Then open Cursor and verify: Settings account, Agent chat, MCP connections, GitHub PR extension.

## Two Macs

| Mac | `BACKUP_TARGET` | Notes |
|-----|-----------------|-------|
| Personal | `macbook-pro-2023` | |
| Work | `mac-consensys` | Warn: Consensys IT may prohibit SSO token export |

Each machine has its own bundle under its `<BACKUP_TARGET>/cursor-auth/`. Restoring a bundle from machine A onto machine B defers Okta until tokens expire.

## Verify checklist

**After backup:**
- [ ] `cursor-auth-bundle.tar.age` exists under `<target>/cursor-auth/`
- [ ] No files under `cursor-auth/.stage/`
- [ ] Script printed `verified: cursor-auth bundle structure`

**After restore:**
- [ ] `sqlite3` shows `cursorAuth/accessToken` row (do not print values)
- [ ] Cursor Settings shows correct account
- [ ] Agent sends a message without re-login

## Related

- Skill source: `~/dev/repos/personal/kb/agents/skills/cursor-auth-backup/`
- Secrets bundle: `backup/manual/secrets.md`, `backup --secrets`
- Encryption: `docs/ENCRYPTION.md`
