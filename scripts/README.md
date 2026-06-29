# backup-run scripts

Shell wrappers for extras not covered by `backup-run` sync. Python logic lives in `src/backup_run/extras/`.

| Script | Purpose |
|--------|---------|
| `backup_extras.sh` | Orchestrator: brew manifests, macOS plists, Cursor extras, Chrome, dev layout, Postman |
| `snapshot_chrome_inventory.sh` | Chrome profiles + per-profile `ls` of Extensions and Web Applications |
| `snapshot_dev_layout.sh` | Repo map + dev layout YAML + workspace files |
| `snapshot_postman.sh` | Postman local config |

Invoked by `./backup` after `backup-run --backup-all --skip-git`.

Python modules (via `run_tool_python -m …`):

| Module | Purpose |
|--------|---------|
| `backup_run.extras.chrome` | Profile labels, bookmarks JSON → HTML |
| `backup_run.extras.dev_layout` | `repos_map.yaml`, `dev_layout.yaml` |
