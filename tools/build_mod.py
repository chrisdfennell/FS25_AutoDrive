"""Builds the mod zip for a release or a test build.

The zip must be called FS25_AutoDrive.zip: the mod checks its own file name, and savegames,
settings and other mods (Courseplay, placeables with AutoDrive routes) depend on it.

--version stamps the full version (e.g. 3.0.1.4-od.1) into AutoDrive.version, which the HUD shows.
Only the copy in the zip is changed. The part before "-" must match the version in modDesc.xml.

usage: python tools/build_mod.py [--version 3.0.1.4-od.1] [--out dist/FS25_AutoDrive.zip]
"""
import argparse
import hashlib
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
# everything the game needs, plus the license and credits that have to travel with every copy (MIT)
CONTENT = ["drawing", "gui", "scripts", "sounds", "textures", "translations", "icon_AutoDrive.dds", "modDesc.xml", "register.lua", "LICENSE", "credits.txt"]
VERSION_FILE = "scripts/AutoDrive.lua"
VERSION_PATTERN = re.compile(r'^AutoDrive\.version = "[^"]*"', re.MULTILINE)


def files():
    for entry in CONTENT:
        path = os.path.join(ROOT, entry)
        if os.path.isdir(path):
            for folder, _, names in os.walk(path):
                for name in names:
                    full = os.path.join(folder, name)
                    yield full, os.path.relpath(full, ROOT).replace(os.sep, "/")
        elif os.path.isfile(path):
            yield path, entry
        else:
            sys.exit("missing: " + entry)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="full version shown in game, e.g. 3.0.1.4-od.1")
    parser.add_argument("--out", default=os.path.join(ROOT, "dist", "FS25_AutoDrive.zip"))
    args = parser.parse_args()

    mod_version = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot().findtext("version").strip()
    if args.version and args.version.split("-")[0] != mod_version:
        sys.exit("version %s does not start with the modDesc.xml version %s" % (args.version, mod_version))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    count = 0
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as zf:
        for full, name in sorted(files(), key=lambda f: f[1]):
            if name == VERSION_FILE and args.version:
                source = open(full, encoding="utf-8", newline="").read()
                if not VERSION_PATTERN.search(source):
                    sys.exit("AutoDrive.version not found in " + VERSION_FILE)
                source = VERSION_PATTERN.sub('AutoDrive.version = "%s"' % args.version, source, count=1)
                zf.writestr(name, source.encode("utf-8"))
            else:
                zf.write(full, name)
            count += 1

    digest = hashlib.sha256(open(args.out, "rb").read()).hexdigest()
    print("built %s: %d files, version %s, sha256 %s" % (os.path.relpath(args.out, ROOT), count, args.version or mod_version, digest))


if __name__ == "__main__":
    main()
