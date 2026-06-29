"""Chrome profile helpers and bookmark export."""

from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path


def profile_label_slug(local_state: Path, profile_dir: str) -> str:
    """Return ``{profile_dir}__{slug}`` for inventory/bookmark output filenames."""
    name = profile_dir
    try:
        data = json.loads(local_state.read_text(encoding="utf-8"))
        info = data.get("profile", {}).get("info_cache", {}).get(profile_dir, {})
        if info.get("name"):
            name = info["name"]
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        pass
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or profile_dir
    return f"{profile_dir}__{slug}"


def _node_to_html(node: dict, indent: int = 0) -> list[str]:
    pad = "    " * indent
    node_type = node.get("type")
    if node_type == "folder":
        name = html.escape(node.get("name", ""))
        lines = [f"{pad}<DT><H3>{name}</H3>", f"{pad}<DL><p>"]
        for child in node.get("children", []):
            lines.extend(_node_to_html(child, indent + 1))
        lines.extend([f"{pad}</DL><p>"])
        return lines
    if node_type == "url":
        name = html.escape(node.get("name", ""))
        url = html.escape(node.get("url", ""))
        return [f'{pad}<DT><A HREF="{url}">{name}</A>']
    return []


def bookmarks_to_html(src: Path, dest: Path) -> None:
    """Convert Chrome Bookmarks JSON to Netscape HTML (importable in any browser)."""
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
            body.extend(_node_to_html(roots[key], 1))
    dest.write_text(header + "\n".join(body) + "</DL><p>\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "usage: profile-label <Local State> <profile_dir> | bookmarks <Bookmarks> <out.html>",
            file=sys.stderr,
        )
        return 1

    cmd = sys.argv[1]
    if cmd == "profile-label":
        if len(sys.argv) != 4:
            print("usage: profile-label <Local State> <profile_dir>", file=sys.stderr)
            return 1
        print(profile_label_slug(Path(sys.argv[2]), sys.argv[3]))
        return 0

    if cmd == "bookmarks":
        if len(sys.argv) != 4:
            print("usage: bookmarks <Bookmarks> <out.html>", file=sys.stderr)
            return 1
        bookmarks_to_html(Path(sys.argv[2]), Path(sys.argv[3]))
        return 0

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
