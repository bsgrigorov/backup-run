# Offsite encryption / decryption

Recipe used by `scripts/offsite-gdrive.sh` and for any single-file secrets dropped into Google Drive `Documents/Backup`.

## Method

```text
openssl enc -aes-256-cbc -pbkdf2 -salt   # encrypt
openssl enc -d -aes-256-cbc -pbkdf2      # decrypt
```

| Piece | Why |
|---|---|
| AES-256-CBC | Standard cipher; fine for personal file encryption |
| `-pbkdf2` | Required — without it OpenSSL’s old key derivation is weak |
| `-salt` | Unique salt per file (default with `enc`) |

**Caveats:** confidentiality only — no authenticity (tampering isn’t detected). Passphrase lives in **1Password**, never next to the `.enc` in Drive. Prefer interactive prompt, `op read`, or `-pass fd:3` (what the script uses); never `-pass pass:…` (shows up in `ps`).

Optional upgrade later: [`age`](https://github.com/FiloSottile/age) for authenticated encryption. Not required.

## Repo snapshot (script)

Fixed name: `git-bsgrigorov-backup.zip.enc` — each run **overwrites**. Destination:

`~/Library/CloudStorage/GoogleDrive-…/My Drive/Documents/Backup/`

```bash
./scripts/offsite-gdrive.sh --dry-run
./scripts/offsite-gdrive.sh --verify    # write, decrypt, check, clean temp

# Passphrase: prompt, or BACKUP_OFFSITE_PASSPHRASE, or BACKUP_OFFSITE_OP_REF='op://…/password'
```

Manual decrypt:

```bash
work="$(mktemp -d "${TMPDIR:-/tmp}/backup-restore.XXXXXX")"
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in ~/Library/CloudStorage/GoogleDrive-b.s.grigorov@gmail.com/"My Drive"/Documents/Backup/git-bsgrigorov-backup.zip.enc \
  -out "$work/backup.zip"
unzip "$work/backup.zip" -d "$work"
# inspect, then remove "$work"
```

## Verify

After encrypt (plaintext still present): decrypt to a temp file and `cmp -s` against the original before deleting plaintext.

Re-check an existing `.enc` (no plaintext): decrypt to a temp dir, confirm openssl exit 0 and expected type (`%PDF` header, non-empty text, or `unzip -t` for zip). Do not print secret contents. Wrong passphrase → FAIL.

```bash
# Encrypt
openssl enc -aes-256-cbc -pbkdf2 -salt -in FILE -out FILE.enc
# Decrypt once to verify, then delete plaintext from Drive (and Drive trash)

# Decrypt to a throwaway dir
work="$(mktemp -d "${TMPDIR:-/tmp}/drive-decrypt.XXXXXX")"
openssl enc -d -aes-256-cbc -pbkdf2 -in FILE.enc -out "$work/FILE"
# inspect, then remove "$work"
```

## Related

- Skill (agent): `openssl-encrypt` — files, folders/zips, short text
- Drive folder inventory / what to encrypt: `kb-projects/projects/mac-setup/backup/drive-encryption.md`
- Restore overview: `kb-projects/projects/mac-setup/restore/` § Offsite
- Weekly hook (commented): `zsh-env/tasks/crontab/weekly.sh`
