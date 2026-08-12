"""Raycast extension inventory — titles only, not the 415MB install tree."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def write_extensions_list(out_path: Path) -> int:
    ext = Path.home() / ".config" / "raycast" / "extensions"
    lines = [
        "# Raycast store extensions (title — author)",
        "# Full settings/hotkeys/snippets: Export Settings & Data → .rayconfig",
    ]
    if ext.is_dir():
        for d in sorted(ext.iterdir()):
            if not d.is_dir() or d.name.startswith(".") or d.name == "node_modules":
                continue
            title = author = None
            for pkg in [d / "package.json", *d.glob("*/package.json")]:
                if not pkg.is_file():
                    continue
                try:
                    data = json.loads(pkg.read_text())
                except (OSError, json.JSONDecodeError):
                    continue
                title = data.get("title") or data.get("name") or title
                author = data.get("author") or author
                if title:
                    break
            lines.append(f"{title or d.name} — {author or '?'}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n")
    return len(lines) - 2


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] != "extensions-list":
        print("usage: python -m backup_run.extras.raycast extensions-list <out>", file=sys.stderr)
        return 2
    n = write_extensions_list(Path(argv[1]))
    print(n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
