import os
import sys
from fnmatch import fnmatch
from pathlib import Path
from shutil import copy, copyfile, copytree

from colorama import Fore, Style

from .compatibility import *
from .config import get_config
from .printing import *
from .utils import (
    evaluate_condition,
    find_path_for_permission_error_reporting,
    get_abs_path_subfiles,
    safe_mkdir,
)

# NOTE: Naming convention is like this since the CLI flags would otherwise
#       conflict with the function names.

# DEPRECATED: every reinstall entrypoint is disabled and exits 1. Restore has never
# worked end to end here and writing to a live $HOME / Library is too dangerous to
# leave reachable. The implementations below are kept intentionally, unreached, as
# the reference for what a restore would have to do.
_DEPRECATION_NOTE = (
    "Restore is agent-driven: ~/dev/repos/zzz/bootstrap/skills/migrate-mac/SKILL.md\n"
    "The implementations in reinstall.py are kept for reference only."
)


def reinstall_deprecated_exit(command: str) -> None:
    """Refuse to run and exit 1. Never returns."""
    print_red_bold(f"DEPRECATED: {command} is disabled and does nothing.")
    print_red_bold(_DEPRECATION_NOTE)
    sys.exit(1)


def _skip_if_empty(backup_path: str, backup_type: str) -> bool:
    """Print a notice and return True if there's nothing to reinstall.
    Unlike a hard exit, this lets --reinstall-all continue with the next category
    (e.g. an empty fonts/ dir must not abort the whole restore)."""
    if not os.path.isdir(backup_path) or not os.listdir(backup_path):
        print_red_bold(f"No {backup_type} backup found — skipping.")
        return True
    return False


def _reinstall_excludes() -> list[str]:
    """Paths we intentionally never restore, derived from the gitignore lists.

    Invariant: if we chose not to commit it, we don't copy it back onto a machine.
    The tool restores from the on-disk dotfiles/ dir, not from git, so gitignore
    alone does not stop secrets (SSH private keys, .pypirc, gcloud token DBs, ...)
    from being reinstalled. Returns patterns relative to the dotfiles dir, e.g.
    ".ssh", ".pypirc", ".config/gcloud/*.db".
    """
    cfg = get_config()
    patterns: set[str] = set()
    for entry in cfg.get("root-gitignore", []):
        if entry.startswith("dotfiles/"):
            patterns.add(entry[len("dotfiles/") :])
    patterns.update(cfg.get("dotfiles-gitignore", []))
    return sorted(p.rstrip("/") for p in patterns if p)


def _is_excluded(rel_path: str, patterns: list[str]) -> bool:
    """True if rel_path matches an exclude pattern or lives under an excluded dir."""
    for pat in patterns:
        if fnmatch(rel_path, pat) or fnmatch(rel_path, f"{pat}/*"):
            return True
    return False


def reinstall_dots_sb(
    dots_path: str, home_path: str = os.path.expanduser("~"), dry_run: bool = False
):
    """DEPRECATED — disabled, exits 1. Would reinstall all dotfiles and folders by
    copying them from dots_path to a path relative to home_path, or to an absolute path."""
    reinstall_deprecated_exit("--reinstall-dots")
    if _skip_if_empty(dots_path, "dotfile"):
        return
    print_section_header("REINSTALLING DOTFILES", Fore.BLUE)

    # Get paths of ALL files that we will be reinstalling from config.
    # 	If .ssh is in the config, full paths of all dots_path/.ssh/* files
    # 	will be in dotfiles_to_reinstall
    config = get_config()["dotfiles"]

    dotfiles_to_reinstall = []
    for dotfile_path_from_config, options in config.items():
        # Evaluate condition, if specified. Skip if the command doesn't return true.
        condition_success = evaluate_condition(
            condition=options.get("reinstall_condition", ""),
            backup_or_reinstall="reinstall",
            dotfile_path=dotfile_path_from_config,
        )
        if not condition_success:
            continue

        if dotfile_path_from_config.startswith("/"):
            dotfile_path_from_config = ":" + dotfile_path_from_config[1:]

        real_path_dotfile = os.path.join(dots_path, dotfile_path_from_config)
        if os.path.isfile(real_path_dotfile):
            dotfiles_to_reinstall.append(real_path_dotfile)
        else:
            subfiles_to_add = get_abs_path_subfiles(real_path_dotfile)
            dotfiles_to_reinstall.extend(subfiles_to_add)

    # Never restore anything we intentionally kept out of the backup. These files
    # (SSH private keys, .pypirc, gcloud token DBs, ...) are gitignored but still
    # sit on disk under dotfiles/, and reinstall copies from disk, not git.
    excludes = _reinstall_excludes()
    kept = []
    for source in dotfiles_to_reinstall:
        rel = os.path.relpath(source, dots_path).replace(os.sep, "/")
        if _is_excluded(rel, excludes):
            print_yellow(f"Skipping excluded (secret/ignored): {rel}")
            continue
        kept.append(source)
    dotfiles_to_reinstall = kept

    reinstallation_error_count = 0
    # Create list of tuples containing source and dest paths for dotfile reinstallation
    # The absolute file paths prepended with ':' are converted back to valid paths
    # Format: [(source, dest), ... ]
    full_path_dotfiles_to_reinstall = []
    for source in dotfiles_to_reinstall:
        # If it's an absolute path, dest is the corrected path
        abs_path_start = os.path.join(dots_path, ":")
        if source.startswith(abs_path_start):
            dest = "/" + source[len(abs_path_start) :]
        else:
            # Otherwise, it should go in a path relative to the home path
            dest = source.replace(dots_path, home_path + "/")
        full_path_dotfiles_to_reinstall.append((Path(source), Path(dest)))

    files_with_permission_errors = set()
    # Copy files from backup to system
    for dot_source, dot_dest in full_path_dotfiles_to_reinstall:
        if dry_run:
            print_dry_run_copy_info(dot_source, dot_dest)
            continue

        # Create dest parent dir if it doesn't exist
        # One case that this can fail is if dot_dest.parent is a FILE. We will try-catch this case specifically.
        # https://github.com/alichtman/shallow-backup/issues/343#issuecomment-2120024456
        parent_dir = dot_dest.parent
        if os.path.isfile(parent_dir):
            print(
                f"{Fore.RED}{Style.BRIGHT}ERROR: {Style.NORMAL}{parent_dir}{Style.BRIGHT} is a file, however, this reinstallation process attempts to create {Style.NORMAL}{dot_dest}{Style.BRIGHT}, which would use that path as a directory. You will have to manually remediate this issue (likely by renaming or moving {Style.NORMAL}{dot_dest.parent}{Style.BRIGHT}){Style.NORMAL}{Style.RESET_ALL}"
            )
            reinstallation_error_count += 1
            continue

        safe_mkdir(dot_dest.parent)
        try:
            copy(dot_source, dot_dest)
        except PermissionError as err:
            files_with_permission_errors.add(find_path_for_permission_error_reporting(err.filename))
        except FileNotFoundError as err:
            print_red_bold(f"ERROR: {err}")

    if reinstallation_error_count != 0:
        print_red_bold("\nSome errors which require manual resolution detected.")

    num_permission_errors = len(files_with_permission_errors)
    if num_permission_errors != 0:
        print_red_bold(
            f"\n{num_permission_errors} permission errors detected. Most of the time, this is not a problem.\nGit repos will have some read-only files, and will prevent you from writing to them without using sudo.\nAdditionally, some package managers (like zcomet, etc) make their install files read-only.\nYou should update these files using the respective tools that created them.\nThe following paths were problematic:"
        )
        print_list_pretty(sorted(files_with_permission_errors))

    print_section_header("DOTFILE REINSTALLATION COMPLETED", Fore.BLUE)


def reinstall_fonts_sb(fonts_path: str, dry_run: bool = False):
    """DEPRECATED — disabled, exits 1. Would reinstall all fonts."""
    reinstall_deprecated_exit("--reinstall-fonts")
    if _skip_if_empty(fonts_path, "font"):
        return
    print_section_header("REINSTALLING FONTS", Fore.BLUE)

    # Copy every file in fonts_path to the platform fonts dir.
    fonts_dir = get_fonts_dir()
    if not dry_run:
        safe_mkdir(fonts_dir)
    for font in get_abs_path_subfiles(fonts_path):
        dest_path = os.path.join(fonts_dir, os.path.basename(font))
        if dry_run:
            print_dry_run_copy_info(font, dest_path)
            continue
        copyfile(font, dest_path)
    print_section_header("FONT REINSTALLATION COMPLETED", Fore.BLUE)


def reinstall_configs_sb(configs_path: str, dry_run: bool = False):
    """DEPRECATED — disabled, exits 1. Would reinstall all configs from the backup."""
    reinstall_deprecated_exit("--reinstall-configs")
    if _skip_if_empty(configs_path, "config"):
        return
    print_section_header("REINSTALLING CONFIG FILES", Fore.BLUE)

    config = get_config()
    for dest_path, backup_loc in config["config_mapping"].items():
        source_path = os.path.join(configs_path, backup_loc)

        if dry_run:
            print_dry_run_copy_info(source_path, dest_path)
            continue

        if os.path.isdir(source_path):
            # dirs_exist_ok so restoring over an existing config dir doesn't raise.
            copytree(source_path, dest_path, symlinks=True, dirs_exist_ok=True)
        elif os.path.isfile(source_path):
            safe_mkdir(os.path.dirname(dest_path))
            copyfile(source_path, dest_path)

    print_section_header("CONFIG REINSTALLATION COMPLETED", Fore.BLUE)


def reinstall_packages_sb(packages_path: str, dry_run: bool = False):
    """DEPRECATED — disabled, exits 1.

    Live package restore was unsafe: it ran `pip install -r` / `npm install -g`
    from stale global lists and `code --install-extension` while `code` resolves
    to Cursor. Restore Homebrew from the Brewfile and install the rest by hand.
    """
    reinstall_deprecated_exit("--reinstall-packages")
    if _skip_if_empty(packages_path, "package"):
        return
    print_section_header("PACKAGE REINSTALL (DEPRECATED — AUDIT ONLY)", Fore.YELLOW)
    print_red_bold(
        "Package reinstall no longer executes. The commands below are for audit only —\n"
        "run the ones you want by hand. Global lists go stale and `code` is aliased to Cursor.\n"
        "Recommended: `brew bundle install --file Brewfile`, then review the rest."
    )

    package_mgrs = set()
    backup_root = Path(packages_path).resolve().parent
    vscode_ext = backup_root / "configs" / "vscode" / "extensions.list"
    for file in os.listdir(packages_path):
        if file == "Brewfile":
            package_mgrs.add("brew")
            continue
        manager = file.split("_")[0].replace("-", " ")
        if manager in ["gem", "cargo", "npm", "pip", "pip3", "brew", "macports"]:
            package_mgrs.add(file.split("_")[0])
    if vscode_ext.is_file():
        package_mgrs.add("vscode")

    audit_cmds = {
        "brew": f"brew bundle install --no-lock --file {packages_path}/Brewfile",
        "npm": f"cat {packages_path}/npm_list.txt | xargs npm install -g",
        "pip": f"pip install -r {packages_path}/pip_list.txt",
        "pip3": f"pip3 install -r {packages_path}/pip3_list.txt",
        "gem": f"cat {packages_path}/gem_list.txt | xargs -L 1 gem install",
        "cargo": f"cat {packages_path}/cargo_list.txt | xargs -L 1 cargo install",
        "vscode": f'while read ext; do code --install-extension "$ext"; done < {vscode_ext}',
    }
    for pm in sorted(package_mgrs):
        if pm == "macports":
            print_red_bold("WARNING: Macports reinstallation is not supported.")
            continue
        cmd = audit_cmds.get(pm)
        if cmd:
            print_yellow_bold(f"$ {cmd}")

    print_section_header("PACKAGE AUDIT COMPLETED", Fore.YELLOW)


def reinstall_all_sb(
    dotfiles_path: str,
    packages_path: str,
    fonts_path: str,
    configs_path: str,
    dry_run: bool = False,
):
    """DEPRECATED — disabled, exits 1. Would call all reinstallation methods."""
    reinstall_deprecated_exit("--reinstall-all")
    reinstall_dots_sb(dotfiles_path, dry_run=dry_run)
    reinstall_packages_sb(packages_path, dry_run=dry_run)
    reinstall_fonts_sb(fonts_path, dry_run=dry_run)
    reinstall_configs_sb(configs_path, dry_run=dry_run)
