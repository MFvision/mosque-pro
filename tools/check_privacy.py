#!/usr/bin/env python3
"""The privacy text matches what the apps do: every outside service the code talks to is named in it.

    check_privacy.py    # exit 1 and list each problem

Collects every https:// address written in the Apple apps (ios/, tests left out) and the TV page (website/tv/), and
checks that the service behind it is named in both languages of the privacy policy (website/privacy.html). The two
that people meet most, the Quran streams and Clean network's DNS, must also be in the app's own privacy text
(privacy_body, every language) and the store's (privacy_policy_text, every language). A new service in the code
fails here until the privacy policy says who it is.
"""
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# Host (or a domain it ends with) → the service's name as the privacy policy writes it, in English and in Arabic.
SERVICES = {
    "api.met.no": ("MET Norway", "MET Norway"),
    "www.met.no": ("MET Norway", "MET Norway"),
    "mp3quran.net": ("mp3quran.net", "mp3quran.net"),
    "quranicaudio.com": ("QuranicAudio", "QuranicAudio"),
    "qurango.net": ("qurango.net", "qurango.net"),
    "adguard-dns.com": ("AdGuard", "AdGuard"),
    "maps.apple.com": ("Apple Maps", "خرائط Apple"),
    "waze.com": ("Waze", "Waze"),
    "www.google.com": ("Google", "Google"),
    "islamqa.info": ("islamqa.info", "islamqa.info"),
    "dorar.net": ("dorar.net", "dorar.net"),
    "github.com": ("GitHub", "GitHub"),
    "wa.me": ("WhatsApp", "واتساب"),
    "api.open-meteo.com": ("Open-Meteo", "Open-Meteo"),
    "fonts.googleapis.com": ("Google Fonts", "Google Fonts"),
    "doubleclick.net": ("doubleclick.net", "doubleclick.net"),
}
# Addresses that are not a service the app sends anything to.
NOT_SERVICES = {
    "mfvision.github.io",  # Mosque Pro's own site on GitHub Pages
    "nearmosque.net",  # Mosque Pro's pages at nearmosque.net/mosque-pro/ (check_brand.py allows only that section)
    "avaai.sa",  # the publisher's site, opened only from Settings
    "www.w3.org",  # an XML namespace in an SVG
    "host", "x", "s", "l", "invalid", "example.org", "example.com",  # placeholders in code and doc comments
}
# Swift package dependencies are fetched by the build, not by the app.
SKIP_FILES = {"Package.swift"}
URL = re.compile(r"https?://([A-Za-z0-9.-]+)")


def hosts():
    found = {}
    files = [p for p in (REPO / "ios").rglob("*.swift") if "/Tests/" not in str(p) and p.name not in SKIP_FILES]
    files += sorted((REPO / "website/tv").glob("*.js"))
    for p in files:
        for n, line in enumerate(p.read_text().splitlines(), 1):
            for h in URL.findall(line):
                found.setdefault(h.lower(), f"{p.relative_to(REPO)}:{n}")
    return found


def service(host):
    for domain, names in SERVICES.items():
        if host == domain or host.endswith("." + domain):
            return names
    return None


def articles():
    html = (REPO / "website/privacy.html").read_text()
    en = re.search(r'<article lang="en".*?</article>', html, re.S).group(0)
    ar = re.search(r'<article lang="ar".*?</article>', html, re.S).group(0)
    return en, ar


def main():
    problems = []
    en, ar = articles()
    for host, where in sorted(hosts().items()):
        if host in NOT_SERVICES:
            continue
        names = service(host)
        if names is None:
            problems.append(f"{where}: {host} is not in tools/check_privacy.py SERVICES or the privacy policy")
            continue
        if names[0] not in en:
            problems.append(f"{where}: {host} ({names[0]}) is not named in the English privacy policy")
        if names[1] not in ar:
            problems.append(f"{where}: {host} ({names[1]}) is not named in the Arabic privacy policy")

    must = ["mp3quran.net", "AdGuard"]
    strings = json.loads((REPO / "shared/i18n/strings.json").read_text())["strings"]
    for lang, text in strings["privacy_body"].items():
        for word in must:
            if word not in text:
                problems.append(f"strings.json privacy_body [{lang}]: does not mention {word}")
    for lang, text in strings["clean_network_detail"].items():
        if text.count("AdGuard") < 2:
            problems.append(f"strings.json clean_network_detail [{lang}]: does not say what AdGuard sees")
    for f in sorted((REPO / "shared/store/listing").glob("*.json")):
        d = json.loads(f.read_text())
        for word in must:
            if word not in d["privacy_policy_text"]:
                problems.append(f"{f.relative_to(REPO)} privacy_policy_text: does not mention {word}")
        if "mp3quran.net" not in d["tv"]["privacy"]:
            problems.append(f"{f.relative_to(REPO)} tv.privacy: does not mention the Quran streams")

    for p in problems:
        print(p)
    print(f"{len(problems)} problems" if problems else "Privacy text names every service the apps and the TV page use: OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
