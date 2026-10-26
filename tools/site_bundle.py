#!/usr/bin/env python3
"""Gathers Mosque Pro's website into one folder: the home page (the story told over the globe and the sky, with what
it loads), the privacy policy and terms, and the TV page. Everything links relatively, so the folder works at any
address.

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
PAGES = {"index.html": "index.html", "privacy.html": "privacy.html", "terms.html": "terms.html",
         "legal.css": "legal.css", "legal.js": "legal.js"}
# The home page's scripts and styles (index.html), and what the TV page shares with it.
SCRIPTS = ["app.js", "story.js", "globe.js", "places.js", "prayer.js", "sky.js", "duo.js", "wall.js",
           "style.css", "devices.css", "duo.css", "wall.css"]
ASSETS = ["zones.json", "adhan.mp3", "icon-180.png", "icon.webp", "land.json", "cities.json", "earth-day.jpg",
          "earth-night.jpg", "makkah-iss.jpg", "haram-night.jpg", "kaaba-tawaf.mp4", "kaaba-tawaf.webm",
          "kaaba-tawaf-tall.mp4", "kaaba-tawaf-tall.webm"]
# The screenshots, by language, without the ones that show the other app: its Apple TV pictures (the TV pictures
# here are of Mosque Pro's TV page, in screen/) and the welcome steps that say its name (see wall.js).
SHOTS_LEFT_OUT = ["tv", "promise.webp", "done.webp", "extras.webp", "more.webp", "adhan.webp"]


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
    shutil.copytree(WEB / "assets/frames", out / "assets/frames")
    for lang in ("en", "ar"):
        shutil.copytree(WEB / "assets" / lang, out / "assets" / lang, ignore=shutil.ignore_patterns(*SHOTS_LEFT_OUT))
    shutil.copytree(WEB / "vendor", out / "vendor")
    shutil.copytree(WEB / "tv", out / "tv")
    (out / ".nojekyll").touch()
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(f"Mosque Pro's site written to {bundle(sys.argv[1])}")
