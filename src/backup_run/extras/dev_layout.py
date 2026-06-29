"""Dev layout snapshots — YAML via PyYAML, no external repo tooling."""

from __future__ import annotations

import re
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

import yaml

SKIP_PATH_SEGMENTS = frozenset(
    {
        ".terraform",
        ".terragrunt-cache",
        "node_modules",
    }
)

INDEX_SOURCE = "backup-run git walk"

YAML_DUMP_KWARGS = {
    "sort_keys": False,
    "default_flow_style": False,
    "allow_unicode": True,
}


def _path_has_worktree_segment(path: str) -> bool:
    for part in path.replace("\\", "/").split("/"):
        if part == "worktrees" or part.endswith(".worktrees"):
            return True
    return False


def _is_worktree_dir(name: str) -> bool:
    return name == "worktrees" or name.endswith(".worktrees")


def _should_skip_repo_path(repo_path: Path, repos_root: Path) -> bool:
    if _path_has_worktree_segment(str(repo_path)):
        return True
    try:
        rel = repo_path.relative_to(repos_root)
    except ValueError:
        return True
    return any(part in SKIP_PATH_SEGMENTS for part in rel.parts)


def _git_remote(path: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    url = result.stdout.strip()
    return url or None


def _url_to_repo_slug(url: str) -> str | None:
    match = re.search(r"github\.com[:/]([^/]+/[^/.]+)", url)
    if match:
        return match.group(1).removesuffix(".git")
    match = re.match(r"git@([^:]+):([^/]+/[^/.]+)", url)
    if match:
        return match.group(2).removesuffix(".git")
    return None


def _origin_to_https(url: str) -> str:
    """Normalize origin remote to an https clone URL when possible (no .git suffix)."""
    raw = url.strip()
    if not raw:
        return raw
    if raw.startswith("https://"):
        return raw.removesuffix(".git")
    ssh_scp = re.match(r"git@([^:]+):(.+)$", raw)
    if ssh_scp:
        host, repo_path = ssh_scp.groups()
        return f"https://{host}/{repo_path.removesuffix('.git')}"
    ssh_url = re.match(r"ssh://git@([^/]+)/(.+)$", raw)
    if ssh_url:
        host, repo_path = ssh_url.groups()
        return f"https://{host}/{repo_path.removesuffix('.git')}"
    if raw.startswith("http://"):
        return raw.removesuffix(".git")
    return raw.removesuffix(".git")


def _utc_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_yaml(path: Path, data: dict) -> None:
    path.write_text(yaml.safe_dump(data, **YAML_DUMP_KWARGS))


def _remove_legacy_layout_files(layouts_dir: Path) -> None:
    """Drop obsolete formats — do not delete current YAML outputs."""
    for name in (
        "repos_index.jsonl",
        "repos_index.meta.json",
        "repos_index.yaml",
        "dev_layout.json",
    ):
        stale = layouts_dir / name
        if stale.is_file():
            stale.unlink()


def _collect_repos(repos_root: Path) -> tuple[list[dict[str, str]], int]:
    included: list[dict[str, str]] = []
    excluded = 0

    if not repos_root.is_dir():
        return included, excluded

    for git_entry in sorted(repos_root.rglob(".git")):
        if not git_entry.is_dir():
            continue
        repo_path = git_entry.parent
        if _should_skip_repo_path(repo_path, repos_root):
            excluded += 1
            continue
        remote = _git_remote(repo_path)
        slug = _url_to_repo_slug(remote) if remote else None
        https_url = _origin_to_https(remote) if remote else ""
        included.append(
            {
                "repo": slug or "(unknown)",
                "url": https_url,
                "path": str(repo_path),
            }
        )

    return included, excluded


def build_repos_map(repos_root: Path, out_path: Path) -> None:
    repos, excluded = _collect_repos(repos_root)
    _write_yaml(
        out_path,
        {
            "generated_at": _utc_now(),
            "source": INDEX_SOURCE,
            "repos_root": str(repos_root),
            "worktree_rule": "exclude paths with segment worktrees or *.worktrees",
            "skip_path_segments": sorted(SKIP_PATH_SEGMENTS),
            "included": len(repos),
            "excluded_paths": excluded,
            "repos": repos,
        },
    )


def _list_immediate_children(directory: Path) -> list[str] | str:
    if _is_worktree_dir(directory.name):
        return "skipped"
    if not directory.is_dir():
        return []
    try:
        return sorted(
            entry.name
            for entry in directory.iterdir()
            if entry.name not in {".DS_Store"} and not entry.name.startswith(".")
        )
    except OSError:
        return []


def _top_level(root: Path) -> list[str]:
    if not root.is_dir():
        return []
    return sorted(
        entry.name for entry in root.iterdir() if entry.is_dir() and entry.name != ".DS_Store"
    )


def build_layout(dev_root: Path, repos_root: Path, out_path: Path) -> None:
    repos_children: dict[str, list[str] | str] = {}
    if repos_root.is_dir():
        for name in _top_level(repos_root):
            repos_children[name] = _list_immediate_children(repos_root / name)

    _write_yaml(
        out_path,
        {
            "generated_at": _utc_now(),
            "dev_root": str(dev_root),
            "repos_root": str(repos_root),
            "dev_top_level": _top_level(dev_root),
            "repos_top_level": _top_level(repos_root),
            "repos_children": repos_children,
            "worktree_bases": {
                "consensys": "consensys/worktrees/<repo>--<branch>/",
                "synkube": "synkube/synkube.worktrees/<repo>--<branch>/",
                "metamask": "metamask/metamask-mobile.worktrees/<slug>/",
                "default": "worktrees/<repo>/<branch>/",
            },
        },
    )


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "usage: repos-map <repos_root> <out.yaml> | layout <dev_root> <repos_root> <out.yaml>",
            file=sys.stderr,
        )
        return 1

    cmd = sys.argv[1]
    if cmd == "repos-map":
        out = Path(sys.argv[3])
        _remove_legacy_layout_files(out.parent)
        build_repos_map(Path(sys.argv[2]), out)
    elif cmd == "layout":
        out = Path(sys.argv[4])
        _remove_legacy_layout_files(out.parent)
        build_layout(Path(sys.argv[2]), Path(sys.argv[3]), out)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
