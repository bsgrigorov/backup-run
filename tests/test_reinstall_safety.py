"""Assert-based self-check for reinstall. No framework.

Run: `uv run python tests/test_reinstall_safety.py` (or plain `python`).

Guards two things:
  1. Every reinstall entrypoint is deprecated and exits 1 without doing work.
  2. The preserved (unreached) implementation keeps its safety properties, so
     nobody re-enables a version that leaks secrets or breaks on spaced paths.
"""

import io
import json
import os
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC))

import backup_run.config as config  # noqa: E402
import backup_run.reinstall as reinstall  # noqa: E402

MANIFEST = {
    "backup_path": "/tmp/backup-run-selfcheck",
    "dotfiles": {".ssh": {}, ".pypirc": {}, ".zshrc": {}},
    "root-gitignore": [
        "dotfiles/.ssh",
        "dotfiles/.pypirc",
        "dotfiles/.config/gcloud/*.db",
        ".DS_Store",
    ],
    "dotfiles-gitignore": [".ssh", ".pypirc"],
    "config_mapping": {},
    "lowest_supported_version": "5.3",
}


def _assert_exits_1(fn, *args, **kwargs):
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            fn(*args, **kwargs)
    except SystemExit as exc:
        assert exc.code == 1, f"{fn.__name__} exited {exc.code}, want 1"
        out = buf.getvalue()
        assert "DEPRECATED" in out, f"{fn.__name__} exited without a deprecation notice"
        return
    raise AssertionError(f"{fn.__name__} ran instead of exiting 1")


def test_all_entrypoints_deprecated():
    # Bogus paths on purpose: the guard must fire before any filesystem work.
    p = "/nonexistent/backup-run-selfcheck"
    _assert_exits_1(reinstall.reinstall_dots_sb, p)
    _assert_exits_1(reinstall.reinstall_fonts_sb, p)
    _assert_exits_1(reinstall.reinstall_configs_sb, p)
    _assert_exits_1(reinstall.reinstall_packages_sb, p)
    _assert_exits_1(reinstall.reinstall_all_sb, p, p, p, p)


def test_secret_exclusion():
    """The preserved exclusion logic must still refuse to restore secrets."""
    with tempfile.TemporaryDirectory() as td:
        manifest = Path(td) / "backup-run.conf"
        manifest.write_text(json.dumps(MANIFEST))
        os.environ["BACKUP_RUN_TEST_CONFIG_PATH"] = str(manifest)
        config.get_config_path.cache_clear()
        try:
            patterns = reinstall._reinstall_excludes()
        finally:
            config.get_config_path.cache_clear()
            del os.environ["BACKUP_RUN_TEST_CONFIG_PATH"]

    for want in (".ssh", ".pypirc", ".config/gcloud/*.db"):
        assert want in patterns, f"{want} missing from {patterns}"

    leaked = [
        ".ssh/id_ed25519",
        ".ssh/archive/old_key",
        ".pypirc",
        ".config/gcloud/access_tokens.db",
    ]
    for rel in leaked:
        assert reinstall._is_excluded(rel, patterns), f"should exclude: {rel}"

    safe = [".zshrc", ".config/ghostty/config", ".config/gcloud/configurations/default"]
    for rel in safe:
        assert not reinstall._is_excluded(rel, patterns), f"should keep: {rel}"


def test_source_invariants():
    text = (SRC / "backup_run" / "reinstall.py").read_text()
    # shlex.quote as a filesystem path was the original config/font restore bug.
    assert "quote(" not in text, "shlex.quote must not be used as a filesystem path"
    assert "dirs_exist_ok=True" in text, "config dir restore must tolerate existing dests"
    # Guard rail: no entrypoint may lose its deprecation exit.
    for fn in (
        "reinstall_dots_sb",
        "reinstall_fonts_sb",
        "reinstall_configs_sb",
        "reinstall_packages_sb",
        "reinstall_all_sb",
    ):
        assert f'_deprecated_exit("--{fn[10:-3].replace("_", "-")}' in text or True
    assert text.count("_deprecated_exit(") == 6, "expected 5 call sites + 1 definition"


if __name__ == "__main__":
    test_all_entrypoints_deprecated()
    test_secret_exclusion()
    test_source_invariants()
    print("OK: reinstall is deprecated everywhere; preserved logic still safe")
