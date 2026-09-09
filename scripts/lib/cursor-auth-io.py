#!/usr/bin/env python3
"""Export/import Cursor auth SQLite rows (read-only export; replace on import)."""
from __future__ import annotations

import base64
import json
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path

EXPORT_SQL = """
SELECT key, value FROM ItemTable WHERE
  key LIKE 'cursorAuth/%'
  OR key = 'storage.serviceMachineId'
  OR key LIKE 'secret://{"extensionId":"vscode.github-authentication"%'
  OR key LIKE 'secret://{"extensionId":"anysphere.cursor-mcp"%'
"""


def _as_bytes(value: bytes | str | None) -> bytes:
    if value is None:
        return b""
    if isinstance(value, bytes):
        return value
    return value.encode("utf-8")


def export_rows(db_path: Path, out_path: Path) -> list[str]:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows = conn.execute(EXPORT_SQL).fetchall()
    conn.close()
    payload = [
        {"key": key, "value_b64": base64.b64encode(_as_bytes(value)).decode("ascii")}
        for key, value in rows
    ]
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return [row["key"] for row in payload]


def import_rows(db_path: Path, in_path: Path) -> int:
    payload = json.loads(in_path.read_text(encoding="utf-8"))
    conn = sqlite3.connect(str(db_path))
    count = 0
    for row in payload:
        blob = base64.b64decode(row["value_b64"])
        conn.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            (row["key"], blob),
        )
        count += 1
    conn.commit()
    ok = conn.execute("PRAGMA integrity_check").fetchone()
    conn.close()
    if ok and ok[0] != "ok":
        raise RuntimeError(f"sqlite integrity_check failed: {ok[0]}")
    return count


def keychain_items(stage: Path) -> list[dict[str, str]]:
    kc = stage / "keychain"
    if not kc.is_dir():
        return []
    items: list[dict[str, str]] = []
    for secret in sorted(kc.glob("*.secret")):
        svc = secret.name.removesuffix(".secret")
        account_file = kc / f"{svc}.account"
        account = account_file.read_text(encoding="utf-8").strip() if account_file.is_file() else "cursor-user"
        items.append({"service": svc, "account": account})
    return items


def write_manifest(stage: Path, keys: list[str]) -> None:
    kc_items = keychain_items(stage)
    manifest = {
        "created": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hostname": __import__("socket").gethostname(),
        "platform": sys.platform,
        "scope": {
            "ide_auth": True,
            "github_extension": any("vscode.github-authentication" in k for k in keys),
            "mcp_tokens": any("anysphere.cursor-mcp" in k for k in keys),
            "keychain": bool(kc_items),
            "cli_config": True,
        },
        "cursorAuth_keys": [k for k in keys if k.startswith("cursorAuth/") or k == "storage.serviceMachineId"],
        "itemtable_keys": keys,
        "keychain_items": kc_items,
    }
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: cursor-auth-io.py export|import <args...>", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == "export":
        db_path, stage = Path(sys.argv[2]), Path(sys.argv[3])
        stage.mkdir(parents=True, exist_ok=True)
        keys = export_rows(db_path, stage / "sqlite" / "itemtable.json")
        if not keys:
            print("ERROR: no auth rows found in state.vscdb", file=sys.stderr)
            return 1
        write_manifest(stage, keys)
        print(len(keys))
        return 0
    if cmd == "import":
        db_path, stage = Path(sys.argv[2]), Path(sys.argv[3])
        count = import_rows(db_path, stage / "sqlite" / "itemtable.json")
        print(count)
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
