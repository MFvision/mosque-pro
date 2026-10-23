#!/usr/bin/env python3
"""Mosque Pro is its own app: no Near Mosque name, site or link address in what people see or what the apps open.

    check_brand.py      # exit 1 and list each problem

Near Mosque is a separate app by the same publisher, usually installed on the same phone. If Mosque Pro said "Turn on
notifications for Near Mosque", opened nearmosque.net, or claimed nearmosque:// links, people would be sent to the
other app. Code names (the NearMosqueApp type, sa.zood.nearmosque.* Kotlin packages, the keychain label) are not shown
to anyone and are left alone; comments are skipped.
"""
import glob
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
OLD_NAMES = ["Near Mosque", "NearMosque/"]
# How some languages translated the old name as the app's name (ar «أقرب مسجد», ur, fa/prs, ug, ckb). In Arabic
# «أقرب مسجد» without quotes is also the ordinary "nearest mosque" (the Mosques tab), so only the app-name forms count.
OLD_LOCAL = {
    "ar": ["«أقرب مسجد»", "تطبيق أقرب مسجد", "افتح أقرب مسجد"],
    "ur": ["قریبی مسجد کھولیں", "قریبی مسجد کے"],
}
# Mosque Pro's own pages live at nearmosque.net/mosque-pro/ until it has a domain; the rest of Near Mosque's site doesn't.
OLD_DOMAIN = re.compile(r"nearmosque\.net(?!/mosque-pro\b)|nearmosque://")


def strings_problems():
    out = []
    s = json.loads((REPO / "shared/i18n/strings.json").read_text())["strings"]
    for key, langs in s.items():
        for lang, text in langs.items():
            if not isinstance(text, str):
                continue
            for old in OLD_NAMES + OLD_LOCAL.get(lang, []):
                if old in text:
                    out.append(f"strings.json {key} [{lang}]: says {old!r}")
            if OLD_DOMAIN.search(text):
                out.append(f"strings.json {key} [{lang}]: links Near Mosque")
    return out


def listing_problems():
    out = []
    for f in sorted(glob.glob(str(REPO / "shared/store/listing/*.json"))) + [str(REPO / "shared/store/listing.json")]:
        text = pathlib.Path(f).read_text()
        lang = pathlib.Path(f).stem
        for old in OLD_NAMES + OLD_LOCAL.get(lang, []) + (OLD_LOCAL["ar"] if lang == "listing" else []):
            if old in text:
                out.append(f"{pathlib.Path(f).relative_to(REPO)}: says {old!r}")
        if OLD_DOMAIN.search(text):
            out.append(f"{pathlib.Path(f).relative_to(REPO)}: links Near Mosque")
    return out


def code_lines(path):
    """The lines of a Swift or JavaScript file without // comments (block comments are rare here and doc-only)."""
    for n, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
            continue
        yield n, re.sub(r"\s//\s.*$", "", line)


def apple_problems():
    out = []
    files = [p for p in (REPO / "ios").rglob("*.swift") if "/Tests/" not in str(p)]
    for p in files:
        for n, line in code_lines(p):
            for old in OLD_NAMES:
                if f'"{old}' in line or (old in line and '"' in line and re.search(r'"[^"]*' + re.escape(old), line)):
                    out.append(f"{p.relative_to(REPO)}:{n}: shows {old!r}")
            if OLD_DOMAIN.search(line):
                out.append(f"{p.relative_to(REPO)}:{n}: opens Near Mosque ({OLD_DOMAIN.search(line).group(0)})")
    yml = (REPO / "ios/project.yml").read_text()
    for n, line in enumerate(yml.splitlines(), 1):
        if line.strip().startswith("#"):
            continue
        if "CFBundleURLSchemes" in line and "mosquepro" not in line:
            out.append(f"ios/project.yml:{n}: link address is not mosquepro ({line.strip()})")
        if re.search(r"sa\.zood\.nearmosque|com\.AVA\.nearmosque", line):
            out.append(f"ios/project.yml:{n}: Near Mosque identifier ({line.strip()})")
    for p in (REPO / "ios").rglob("*.xcstrings"):
        text = p.read_text()
        for old in OLD_NAMES + OLD_LOCAL["ar"]:
            if old in text:
                out.append(f"{p.relative_to(REPO)}: says {old!r} (run tools/gen_strings.py)")
    return out


def web_problems():
    out = []
    pages = [REPO / "website" / n for n in ("index.html", "story.js", "app.js", "wall.js", "duo.js", "privacy.html", "terms.html")]
    pages += sorted((REPO / "website/tv").glob("*.js")) + sorted((REPO / "website/tv").glob("*.html"))
    for p in pages:
        text = p.read_text()
        for old in OLD_NAMES + OLD_LOCAL["ar"] + ["أقرب مسجد</"]:
            if old in text:
                out.append(f"{p.relative_to(REPO)}: says {old!r}")
        if OLD_DOMAIN.search(text):
            out.append(f"{p.relative_to(REPO)}: links Near Mosque")
    listing = (REPO / "tools/store/listing.py").read_text()
    if OLD_DOMAIN.search(listing):
        out.append("tools/store/listing.py: the privacy link is Near Mosque's")
    return out


def main():
    problems = strings_problems() + listing_problems() + apple_problems() + web_problems()
    for p in problems:
        print(p)
    print(f"{len(problems)} problems" if problems else "Mosque Pro's name, site and link address only: OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
