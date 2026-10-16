"""Writes the release notes of an AutoDrive Overdrive release (markdown, to stdout).

The changes are the commit subjects since the previous Overdrive release tag (v*-od.*),
following only the main line, so a merge of a new AutoDrive version is one line.

usage: python tools/release_notes.py 3.0.1.4-od.1
"""
import os
import subprocess
import sys


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8")
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    version = sys.argv[1]
    base = version.split("-")[0]
    repo = os.environ.get("GITHUB_REPOSITORY", "chrisdfennell/FS25_AutoDrive")
    readme = "https://github.com/%s#readme" % repo

    previous = git("describe", "--tags", "--abbrev=0", "--match", "v*-od.*", "HEAD^")
    lines = [
        "## AutoDrive Overdrive %s" % version,
        "",
        "Based on **AutoDrive %s** by the AutoDrive Team, with route editor improvements: "
        "undo and redo (Ctrl+Z / Ctrl+Y) with preview and highlighted changes, target sub folders and folder colours, "
        "moving waypoints by dragging and tidy-up tools, plus a route check, a fleet overview, best price unloading and work schedules. "
        "Everything is described in the [README](%s)." % (base, readme),
        "",
        "### Install",
        "1. Download **FS25_AutoDrive.zip** below.",
        "2. Put it into your mods folder (`Documents/My Games/FarmingSimulator2025/mods`), replacing the official AutoDrive zip.",
        "   Keep the file name: the mod only loads as `FS25_AutoDrive.zip`, and that is also what keeps your savegames, routes and settings working.",
        "3. In multiplayer, every player needs this exact version.",
        "",
    ]
    if previous:
        changes = git("log", "--first-parent", "--format=- %s", "%s..HEAD" % previous) or "- no changes"
        lines += ["### Changes since %s" % previous.lstrip("v"), changes, ""]
    else:
        lines += ["### First release of AutoDrive Overdrive", "See the [README](%s) for everything it adds to AutoDrive %s." % (readme, base), ""]
    lines += [
        "### Credits",
        "AutoDrive is made by the AutoDrive Team (Stephan-S, Axel32019, TyKonKet and [many contributors](https://github.com/%s/blob/main/credits.txt)) "
        "and released under the MIT licence. This is an unofficial edition, for the official mod see https://github.com/Stephan-S/FS25_AutoDrive." % repo,
    ]
    print("\n".join(lines))


if __name__ == "__main__":
    main()
