import json
import os
import stat
import sys
from functools import lru_cache
from os import environ, path
from pathlib import Path

from .compatibility import *
from .constants import ProjInfo
from .printing import *
from .utils import strip_home


def _manifest_candidates() -> list[Path]:
    """Editable install: repo manifest/. Wheel: bundled copy under backup_run/."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    pkg_root = Path(__file__).resolve().parent
    return [
        repo_root / "manifest" / "backup-run.conf",
        pkg_root / "manifest" / "backup-run.conf",
    ]


@lru_cache(maxsize=1)
def get_config_path() -> str:
    test_config_path = environ.get("BACKUP_RUN_TEST_CONFIG_PATH")
    if test_config_path:
        return test_config_path
    for candidate in _manifest_candidates():
        if candidate.is_file():
            return str(candidate)
    expected = _manifest_candidates()[0]
    print_red_bold(f"ERROR: Config not found at {expected}")
    sys.exit(1)


def get_config() -> dict:
    config_path = get_config_path()
    with open(config_path) as file:
        try:
            config = json.load(file)
        except json.decoder.JSONDecodeError:
            print_red_bold(f"ERROR: Invalid syntax in {config_path}")
            sys.exit(1)
    return config


def write_config(config) -> None:
    with open(get_config_path(), "w") as file:
        json.dump(config, file, indent=4)


def get_default_config() -> dict:
    """Returns a default, platform specific config."""
    return {
        "backup_path": "~/shallow-backup",
        "dotfiles": {
            ".bash_profile": {
                "backup_condition": "",
                "reinstall_condition": "",
            },
            ".bashrc": {},
            ".config/git": {},
            ".config/nvim/init.vim": {},
            ".config/tmux": {},
            ".config/zsh": {},
            ".profile": {},
            ".pypirc": {},
            ".ssh": {},
            ".zshenv": {},
            f"{strip_home(get_config_path())}": {},
        },
        "root-gitignore": ["dotfiles/.ssh", "dotfiles/.pypirc", ".DS_Store"],
        "dotfiles-gitignore": [
            ".ssh",
            ".pypirc",
            ".DS_Store",
        ],
        "config_mapping": get_config_paths(),
        "lowest_supported_version": ProjInfo.VERSION,
    }


def safe_create_config() -> None:
    """Ensure manifest/backup-run.conf exists."""
    get_config_path()


def check_insecure_config_permissions() -> bool:
    """Checks to see if group/others can write to config file.
    Returns: True if they can, False otherwise."""
    config_path = get_config_path()
    mode = os.stat(config_path).st_mode
    if mode & stat.S_IWOTH or mode & stat.S_IWGRP:
        print_red_bold(
            f"WARNING: {config_path} is writable by group/others and vulnerable to attack. To resolve, run: \n\t$ chmod 644 {config_path}"
        )
        return True
    else:
        return False


def delete_config_file() -> None:
    """Delete config file."""
    config_path = get_config_path()
    if os.path.isfile(config_path):
        print_red_bold("Deleting config file.")
        os.remove(config_path)
    else:
        print_red_bold("ERROR: No config file found.")


def add_dot_path_to_config(backup_config: dict, file_path: str) -> dict:
    """
    Add dotfile to config with default reinstall and backup conditions.
    Exit if the file_path parameter is invalid.
    :backup_config: dict representing current config
    :file_path:		str  relative or absolute path of file to add to config
    :return new backup config
    """
    abs_path = path.abspath(file_path)
    if not path.exists(abs_path):
        print_path_red("Invalid file path:", abs_path)
        return backup_config
    else:
        stripped_home_path = strip_home(abs_path)
        print_path_blue("Added:", stripped_home_path)
        backup_config["dotfiles"][stripped_home_path] = {}
    return backup_config


def edit_config():
    """Open the config in the default editor."""
    config_path = get_config_path()
    editor = os.environ.get("EDITOR", "vim")
    os.system(f"{editor} {config_path}")
