"""Assert-based check for BACKUP_TARGET resolution. Run: uv run python tests/test_backup_target.py"""

import os
import sys
import tempfile
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC))

import backup_run.config as config  # noqa: E402


def main() -> None:
    config.get_backup_target.cache_clear()
    config.get_backup_repo_path.cache_clear()
    config.get_machine_backup_path.cache_clear()

    with tempfile.TemporaryDirectory() as tmp:
        local = Path(tmp) / "local.sh"
        local.write_text('export BACKUP_TARGET=mac-consensys\n')
        orig_local = config._LOCAL_SH
        config._LOCAL_SH = local
        os.environ.pop("BACKUP_TARGET", None)
        try:
            assert config.get_backup_target() == "mac-consensys"
        finally:
            config._LOCAL_SH = orig_local
            config.get_backup_target.cache_clear()

    os.environ["BACKUP_TARGET"] = "macbook-pro-2023"
    config.get_backup_target.cache_clear()
    assert config.get_backup_target() == "macbook-pro-2023"
    del os.environ["BACKUP_TARGET"]
    config.get_backup_target.cache_clear()

    print("test_backup_target: ok")


if __name__ == "__main__":
    main()
