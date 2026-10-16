"""Static checks of the mod files, run by CI (no game needed).

- every XML file is well formed
- modDesc.xml has a numeric version (x.x.x.x), as the game expects
- translations: placeholders (%s) match the English text, no stray % (would break string.format in game)
- every script loaded by register.lua exists
- the startup check in register.lua accepts the English title of modDesc.xml (otherwise the mod disables itself)
- Lua files have no UTF-8 BOM (Lua 5.1 can not read it)

The Lua 5.1 syntax check itself is done with luac5.1 in the workflow.
usage: python tools/ci_checks.py
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
errors = []


def check_xml():
    files = glob.glob(os.path.join(ROOT, "**", "*.xml"), recursive=True)
    for path in files:
        if os.sep + ".git" + os.sep in path:
            continue
        try:
            ET.parse(path)
        except ET.ParseError as e:
            errors.append("XML: %s: %s" % (os.path.relpath(path, ROOT), e))
    return len(files)


def check_mod_desc():
    version = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot().findtext("version")
    if version is None or not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", version.strip()):
        errors.append("modDesc.xml: version must be x.x.x.x, is %r" % version)
    return version


def texts(path):
    return {e.get("name"): e.get("text") or "" for e in ET.parse(path).getroot().iter("text")}


def check_translations():
    english = texts(os.path.join(ROOT, "translations", "translation_en.xml"))
    files = sorted(glob.glob(os.path.join(ROOT, "translations", "translation_*.xml")))
    for path in files:
        lang = os.path.basename(path)[len("translation_"):-len(".xml")]
        for key, text in texts(path).items():
            if key in english and text.count("%s") != english[key].count("%s"):
                errors.append("translation %s: %s has %d placeholders, English %d" % (lang, key, text.count("%s"), english[key].count("%s")))
            if re.search(r"%(?![s%])", text):
                errors.append("translation %s: %s has a stray %%: %r" % (lang, key, text))
    return len(files)


def check_sources():
    source = open(os.path.join(ROOT, "register.lua"), encoding="utf-8").read()
    scripts = re.findall(r'Utils\.getFilename\("([^"]+\.lua)"', source)
    for script in scripts:
        if not os.path.isfile(os.path.join(ROOT, script)):
            errors.append("register.lua loads %s, which does not exist" % script)
    return len(scripts)


def check_title():
    title = ET.parse(os.path.join(ROOT, "modDesc.xml")).getroot().findtext("title/en")
    source = open(os.path.join(ROOT, "register.lua"), encoding="utf-8").read()
    if 'activemod.title == "%s"' % title not in source:
        errors.append('register.lua: the startup check does not accept the modDesc title "%s", the mod would not load' % title)
    return title


def check_lua_bom():
    files = glob.glob(os.path.join(ROOT, "scripts", "**", "*.lua"), recursive=True) + [os.path.join(ROOT, "register.lua")]
    for path in files:
        with open(path, "rb") as f:
            if f.read(3) == b"\xef\xbb\xbf":
                errors.append("Lua file with BOM: %s" % os.path.relpath(path, ROOT))
    return len(files)


if __name__ == "__main__":
    print("XML files:        %d" % check_xml())
    print("modDesc version:  %s" % check_mod_desc())
    print("translations:     %d" % check_translations())
    print("register sources: %d" % check_sources())
    print("startup title:    %s" % check_title())
    print("Lua files:        %d" % check_lua_bom())
    if errors:
        print("\n%d problem(s):" % len(errors))
        print("\n".join("  " + e for e in errors))
        sys.exit(1)
    print("all checks passed")
