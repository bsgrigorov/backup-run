# Offsite encryption / decryption

`scripts/offsite-gdrive.sh` writes authenticated age passphrase ciphertext
(`.age`). Same recipe as the `encrypt` skill and `crypt` CLI.

## Method

```text
age -p -o FILE.age FILE     # encrypt (passphrase + confirmation)
age -d -o FILE FILE.age     # decrypt
```

| Piece | Why |
|---|---|
| age (ChaCha20-Poly1305) | Authenticated: wrong passphrase or tampered blob fails loudly |
| Passphrase | Lives in **1Password** only, never next to the `.age` in Drive |

Prefer interactive prompt, `op read`, or the script’s hidden GUI prompt. Never
put the passphrase in argv (`ps`).

Legacy `.enc` (OpenSSL AES-256-CBC + PBKDF2) is restore-only via
`crypt -d -m openssl-10k`. Do not create new `.enc`. Never rename `.enc` → `.age`.

## Repo snapshot (script)

Fixed name: `git-bsgrigorov-backup.zip.age` — each run **overwrites**. Destination:

`~/Library/CloudStorage/GoogleDrive-…/My Drive/Documents/Backup/`

```bash
./scripts/offsite-gdrive.sh --dry-run
./scripts/offsite-gdrive.sh --verify    # write, decrypt, check, clean temp

# Passphrase: prompt, or BACKUP_OFFSITE_PASSPHRASE, or BACKUP_OFFSITE_OP_REF='op://…/password'
```

Manual decrypt:

```bash
work="$(mktemp -d "${TMPDIR:-/tmp}/backup-restore.XXXXXX")"
age -d -o "$work/backup.zip" \
  ~/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/"My Drive"/Documents/Backup/git-bsgrigorov-backup.zip.age
unzip "$work/backup.zip" -d "$work"
# inspect, then remove "$work"
```

## Verify

After encrypt (plaintext still present): decrypt to a temp file and `cmp -s`
against the original before deleting plaintext.

Re-check an existing `.age` (no plaintext): decrypt to a temp dir, confirm age
exit 0 and expected type (`%PDF` header, non-empty text, or `unzip -t` for zip).
Do not print secret contents. Wrong passphrase → FAIL.

```bash
# Encrypt
age -p -o FILE.age FILE
# Decrypt once to verify, then delete plaintext from Drive (and Drive trash)

# Decrypt to a throwaway dir
work="$(mktemp -d "${TMPDIR:-/tmp}/drive-decrypt.XXXXXX")"
age -d -o "$work/FILE" FILE.age
# inspect, then remove "$work"
```

## Related

- Skill (agent): `encrypt` — age passphrase for files; `crypt` for OpenSSL leftovers
- CLI: `zsh-env/scripts/bin/crypt` (default age; `-m openssl-10k` for old `.enc`)
- Drive folder inventory: `kb-projects/projects/mac-setup/backup/drive-encryption.md`
- Restore overview: `kb-projects/projects/mac-setup/restore/` § Offsite
- Weekly hook (commented): `zsh-env/tasks/crontab/weekly.sh`
