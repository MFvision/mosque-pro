#!/usr/bin/env python3
"""Gathers Mosque Pro's website into one folder: the home page, the privacy policy and terms, and the TV page with
what it loads. Everything links relatively, so the folder works at any address.

    site_bundle.py OUT          # write the site into OUT (emptied first)

Used for GitHub Pages (.github/workflows/tv-preview.yml, https://mfvision.github.io/mosque-pro/) and copied into
Near Mosque's site as nearmosque.net/mosque-pro/ (MFvision/nearest-mosque, website/mosque-pro/), where the apps link
until Mosque Pro has its own domain.
"""
import pathlib
import shutil
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
WEB = REPO / "website"
PAGES = {"index.html": "home.html", "privacy.html": "privacy.html", "terms.html": "terms.html",
         "legal.css": "legal.css", "legal.js": "legal.js"}
SCRIPTS = ["prayer.js", "places.js", "sky.js"]
ASSETS = ["zones.json", "adhan.mp3", "icon-180.png", "kaaba-tawaf.mp4"]


def bundle(out):
    out = pathlib.Path(out)
    if out.exists():
        shutil.rmtree(out)
    (out / "assets").mkdir(parents=True)
    for dest, src in PAGES.items():
        shutil.copyfile(WEB / src, out / dest)
    for name in SCRIPTS:
        shutil.copyfile(WEB / name, out / name)
    for name in ASSETS:
        shutil.copyfile(WEB / "assets" / name, out / "assets" / name)
    shutil.copytree(WEB / "tv", out / "tv")
    (out / ".nojekyll").touch()
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(f"Mosque Pro's site written to {bundle(sys.argv[1])}")
