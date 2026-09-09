#!/usr/bin/env bash
# Back-compat wrapper: secrets bundle to git repo + Google Drive.
exec "$(cd "$(dirname "$0")" && pwd)/offsite-secrets.sh" "$@"
