#!/usr/bin/env python3
"""Convert Chrome Bookmarks JSON to Netscape HTML (importable in any browser)."""

from __future__ import annotations

import html
import json
import sys
from pathlib import Path


def node_to_html(node: dict, indent: int = 0) -> list[str]:
    pad = "    " * indent
    node_type = node.get("type")
    if node_type == "folder":
        name = html.escape(node.get("name", ""))
        lines = [f"{pad}<DT><H3>{name}</H3>", f"{pad}<DL><p>"]
        for child in node.get("children", []):
            lines.extend(node_to_html(child, indent + 1))
        lines.extend([f"{pad}</DL><p>"])
        return lines
    if node_type == "url":
        name = html.escape(node.get("name", ""))
        url = html.escape(node.get("url", ""))
        return [f'{pad}<DT><A HREF="{url}">{name}</A>']
    return []


def convert(src: Path, dest: Path) -> None:
    data = json.loads(src.read_text(encoding="utf-8"))
    roots = data.get("roots", {})
    header = (
        "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
        '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n'
        "<TITLE>Bookmarks</TITLE>\n"
        "<H1>Bookmarks</H1>\n"
        "<DL><p>\n"
    )
    body: list[str] = []
    for key in ("bookmark_bar", "other", "synced"):
        if key in roots:
            body.extend(node_to_html(roots[key], 1))
    dest.write_text(header + "\n".join(body) + "</DL><p>\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <Bookmarks> <output.html>", file=sys.stderr)
        return 1
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
