# Offsite encryption / decryption

Backup-run writes **age** passphrase ciphertext (`.age`) for offsite copies. Same
crypto as the `encrypt` skill and `crypt` CLI.

## Method

```text
age -p -o FILE.age FILE     # encrypt (passphrase + confirmation)
age -d -o FILE FILE.age     # decrypt
```

| Piece | Why |
|---|---|
| age (ChaCha20-Poly1305) | Authenticated: wrong passphrase or tampered blob fails loudly |
| Passphrase | 1Password only — never beside the `.age` on Drive or in git |

Use `op read`, interactive prompt, or the script GUI prompt. Never pass the
passphrase on the command line (`ps`).

## Passphrases (1Password)

One item per **job**. Do not reuse the backup pipeline passphrase for ad-hoc files.

| Item name | Used for |
|-----------|----------|
| **encrypt-drive-backup** | All **backup-run** age output: offsite backup zip, secrets bundle, optional cursor-auth bundle, and (if you refresh them) standalone SSH `.age` on Drive |
| **encrypt-secrets-local** | Ad-hoc `age -p` / `encrypt` skill — recovery codes, one-off exports, anything **outside** backup-run |

**Backup-run default:** 1Password item `encrypt-drive-backup`, field `password`.

If `BACKUP_OFFSITE_OP_REF` is unset, scripts read:

`op://Personal/encrypt-drive-backup/password`

(`BACKUP_OFFSITE_OP_REF_DEFAULT` in `scripts/_common.sh` — keeps `op read` working
on this install without extra shell config.)

Override per Mac or vault:

```bash
# ~/.zsh/local.sh
export BACKUP_OFFSITE_OP_REF='op://Personal/encrypt-drive-backup/password'
```

Non-interactive: `BACKUP_OFFSITE_PASSPHRASE` (env, CI only) or `op read` on
`BACKUP_OFFSITE_OP_REF`.

**Not** the age backup passphrase: unlocking your GPG key during
`offsite-secrets.sh --with-gpg`.

Legacy `.enc` (OpenSSL) → `crypt -d -m openssl-10k` only. Do not create new `.enc`.

## Offsite backup zip (`offsite-gdrive.sh`)

Zips the **backup data repo working tree** (no `.git`), encrypts to Drive.

| Env | Role |
|-----|------|
| `BACKUP_ROOT` | Backup data repo (default from manifest) |
| `GDRIVE_BACKUP` | Drive folder for `.age` files (default: Google Drive `Documents/Backup`) |
| Output name | `git-bsgrigorov-backup.zip.age` (fixed; overwrites each run) |

```bash
./scripts/offsite-gdrive.sh --dry-run
./scripts/offsite-gdrive.sh --verify
```

Decrypt example (replace `$GDRIVE_BACKUP` and artifact name):

```bash
work="$(mktemp -d "${TMPDIR:-/tmp}/backup-restore.XXXXXX")"
age -d -o "$work/backup.zip" "$GDRIVE_BACKUP/git-bsgrigorov-backup.zip.age"
unzip "$work/backup.zip" -d "$work"
# inspect, then remove "$work"
```

## Verify

After encrypt: decrypt to a temp file and `cmp -s` against plaintext before deleting
the source.

On an existing `.age`: decrypt to temp, check exit 0 and shape (`unzip -t` for
zips, non-empty file). Do not print secret contents.

`--verify` on offsite scripts decrypts into a temp dir and removes it.

## Secrets bundle

Per machine (`BACKUP_TARGET`):

| Output | Path |
|--------|------|
| Git (private backup repo) | `<backup-repo>/<BACKUP_TARGET>/secrets/bundle.zip.age` |
| Drive (optional) | `$GDRIVE_BACKUP/mac-secrets-<BACKUP_TARGET>.zip.age` |

```bash
backup --secrets
./scripts/offsite-secrets.sh --dry-run
./scripts/offsite-secrets.sh --with-gpg   # adds GPG export; GPG unlock is separate
```

Restore: `backup/manual/secrets.md` in the backup data repo.

## Cursor auth bundle

Optional; same **encrypt-drive-backup** passphrase. See [CURSOR-AUTH-BACKUP.md](CURSOR-AUTH-BACKUP.md).

## Related

- `encrypt` skill — ad-hoc age (`encrypt-secrets-local`)
- `zsh-env/scripts/bin/crypt` — OpenSSL leftovers
- Machine runbooks: backup data repo `manual/secrets.md`, `manual/ssh.md`
- KB inventory (optional): `kb-projects/projects/mac-setup/backup/drive-encryption.md`
