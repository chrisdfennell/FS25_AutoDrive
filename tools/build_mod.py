"""Builds the mod zip for a release or a test build.

The zip must be called FS25_AutoDrive.zip: the mod checks its own file name, and savegames,
settings and other mods (Courseplay, placeables with AutoDrive routes) depend on it.

--version stamps the full version (e.g. 3.0.1.4-od.1) into AutoDrive.version, which the HUD shows.
Only the copy in the zip is changed. The part before "-" must match the version in modDesc.xml.

GIANTS' mod checks (TestRunner / ModHub) allow at most 128 files, Lua files of at most 0.5 MB and only
known file types, so the zip differs from the source tree in two ways (the source stays as it is):
  - the scripts that register.lua loads one after another are joined into bundle files, in the same
    order, each file in its own do ... end block so its local variables stay its own. A bundle is
    filled up to BUNDLE_MAX_BYTES, then the next one starts. Scripts that the game loads itself as
    specializations stay separate files. register.lua in the zip loads the bundles one after another.
    A map of bundle line -> source file and line is written next to the zip (not into it).
  - LICENSE is packed as LICENSE.txt
Scripts that register.lua does not load are not packed.

usage: python tools/build_mod.py [--version 3.0.1.4-od.1] [--out dist/FS25_AutoDrive.zip]
"""
import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
# everything the game needs, plus the license and credits that have to travel with every copy (MIT)
CONTENT = ["drawing", "gui", "scripts", "sounds", "textures", "translations", "icon_AutoDrive.dds", "modDesc.xml", "register.lua", "LICENSE", "credits.txt"]
# packed under another name: the mod checks only accept known file types
RENAMED = {"LICENSE": "LICENSE.txt"}
VERSION_FILE = "scripts/AutoDrive.lua"
VERSION_PATTERN = re.compile(r'^AutoDrive\.version = "[^"]*"', re.MULTILINE)
SOURCE_LINE = re.compile(r'^source\(Utils\.getFilename\("(scripts/[^"]+\.lua)", g_currentModDirectory\)\)\s*$')
BUNDLE_NAME = "scripts/OverdriveBundle%d.lua"
MAX_FILES = 128
MAX_LUA_BYTES = 512 * 1024
# a bundle is closed before it gets bigger than this (some room below the limit)
BUNDLE_MAX_BYTES = 450 * 1024


def read(path):
    return open(path, encoding="utf-8", newline="").read()


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


def stamp_version(name, source, version):
    if name == VERSION_FILE and version:
        if not VERSION_PATTERN.search(source):
            sys.exit("AutoDrive.version not found in " + VERSION_FILE)
        source = VERSION_PATTERN.sub('AutoDrive.version = "%s"' % version, source, count=1)
    return source


def specialization_files(register):
    """scripts the game loads itself (addSpecialization with a file name): they stay separate files"""
    return set(re.findall(r'addSpecialization\([^)]*Utils\.getFilename\("(scripts/[^"]+\.lua)"', register))


def bundle(version):
    """returns (register.lua for the zip, {bundle name: source}, set of bundled script names, line map)"""
    register = read(os.path.join(ROOT, "register.lua"))
    keep = specialization_files(register)
    out_lines, bundles, bundled, line_map = [], {}, set(), []
    current = None
    sizes = {}
    for line in register.splitlines(keepends=True):
        match = SOURCE_LINE.match(line.strip())
        name = match.group(1) if match else None
        if name is not None and name not in keep:
            size = len(read(os.path.join(ROOT, name)).encode("utf-8")) + 64
            if current is not None and sizes[current] + size > BUNDLE_MAX_BYTES:
                # full: the next bundle continues, loaded right after this one
                current = None
            if current is None:
                current = BUNDLE_NAME % (len(bundles) + 1)
                bundles[current] = []
                sizes[current] = 0
                out_lines.append('source(Utils.getFilename("%s", g_currentModDirectory))\n' % current)
            bundles[current].append(name)
            sizes[current] += size
            bundled.add(name)
        elif line.strip() == "" or line.strip().startswith("--"):
            # blank lines and comments do not end a run of bundled scripts
            if current is None:
                out_lines.append(line)
        else:
            current = None
            out_lines.append(line)

    sources = {}
    for bundle_name, names in bundles.items():
        parts = ["-- AutoDrive Overdrive: scripts joined by tools/build_mod.py, see the source tree for the files\n"]
        line_no = 2
        for name in names:
            source = stamp_version(name, read(os.path.join(ROOT, name)), version).replace("\r\n", "\n")
            if source.startswith("﻿"):
                source = source[1:]
            if not source.endswith("\n"):
                source += "\n"
            parts.append("-- ===== %s =====\ndo\n" % name)
            line_map.append((bundle_name, line_no + 2, name))
            parts.append(source)
            parts.append("end\n")
            line_no += 2 + source.count("\n") + 1
        sources[bundle_name] = "".join(parts)
    return "".join(out_lines), sources, bundled, line_map


def syntax_check(sources):
    """luac5.1 -p on the bundles, where it is installed (CI)"""
    luac = shutil.which("luac5.1")
    if luac is None:
        return False
    with tempfile.TemporaryDirectory() as folder:
        for name, source in sources.items():
            path = os.path.join(folder, os.path.basename(name))
            open(path, "w", encoding="utf-8", newline="\n").write(source)
            result = subprocess.run([luac, "-p", path], capture_output=True, text=True)
            if result.returncode != 0:
                sys.exit("syntax error in %s: %s" % (name, result.stderr.strip()))
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="full version shown in game, e.g. 3.0.1.4-od.1")
    parser.add_argument("--out", default=os.path.join(ROOT, "dist", "FS25_AutoDrive.zip"))
    args = parser.parse_args()

    mod_version = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot().findtext("version").strip()
    if args.version and args.version.split("-")[0] != mod_version:
        sys.exit("version %s does not start with the modDesc.xml version %s" % (args.version, mod_version))

    register, bundles, bundled, line_map = bundle(args.version)
    checked = syntax_check(bundles)
    loaded = bundled | specialization_files(read(os.path.join(ROOT, "register.lua")))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    count, skipped = 0, []
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as zf:
        for full, name in sorted(files(), key=lambda f: f[1]):
            # bundled scripts are in the bundle, scripts that are not loaded at all are left out
            if name.startswith("scripts/") and name.endswith(".lua") and (name in bundled or name not in loaded):
                if name not in bundled:
                    skipped.append(name)
                continue
            if name == "register.lua":
                zf.writestr(name, register.encode("utf-8"))
            elif name == VERSION_FILE:
                zf.writestr(name, stamp_version(name, read(full), args.version).encode("utf-8"))
            else:
                zf.write(full, RENAMED.get(name, name))
            count += 1
        for name, source in bundles.items():
            zf.writestr(name, source.encode("utf-8"))
            count += 1

    if count > MAX_FILES:
        sys.exit("%d files in the zip, GIANTS' mod checks allow %d" % (count, MAX_FILES))
    with zipfile.ZipFile(args.out) as zf:
        for info in zf.infolist():
            if info.filename.endswith(".lua") and info.file_size > MAX_LUA_BYTES:
                sys.exit("%s is %.2f MB, GIANTS' mod checks allow %.2f MB per Lua file" % (info.filename, info.file_size / 1048576, MAX_LUA_BYTES / 1048576))
    map_path = os.path.splitext(args.out)[0] + ".bundlemap.txt"
    with open(map_path, "w", encoding="utf-8") as f:
        f.write("bundle line of the first source line -> source file (line numbers in the game log minus this, plus 1)\n")
        for bundle_name, line_no, name in line_map:
            f.write("%s:%d %s\n" % (bundle_name, line_no, name))

    digest = hashlib.sha256(open(args.out, "rb").read()).hexdigest()
    print("built %s: %d files (%d scripts in %d bundle(s)%s), version %s, sha256 %s" % (
        os.path.relpath(args.out, ROOT), count, len(bundled), len(bundles), ", luac5.1 checked" if checked else "",
        args.version or mod_version, digest))
    if skipped:
        print("not packed (not loaded by register.lua): " + ", ".join(skipped))


if __name__ == "__main__":
    main()
