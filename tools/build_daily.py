#!/usr/bin/env python3
"""Ayah of the day and Hadith of the day: the small bundled list both apps pick from.

    python3 tools/build_daily.py          # writes shared/daily/daily.json
    python3 tools/build_daily.py --check  # fails if daily.json is out of date

Verses: the approved references in shared/daily/ayat.txt, with the Arabic (Tanzil), Pickthall's English and the
QuranEnc translations from packs/sources (the translator's footnotes are left out; the main text is unchanged).
Hadith: HadeethEnc entries graded Sahih or Hasan whose title (the Prophet's words, as HadeethEnc gives them) is short
enough for one screen and that exist in every bundled language, spread evenly over the collection. The text, grade and
source are copied unaltered, with HadeethEnc's attribution, as its terms require.

Both apps pick the day's entry with the same rule (DailyContent.swift / DailyContent.kt), checked against
shared/fixtures/daily.json.
"""
import datetime
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "packs", "sources")
OUT = os.path.join(ROOT, "shared", "daily", "daily.json")
AYAT = os.path.join(ROOT, "shared", "daily", "ayat.txt")
FIXTURE = os.path.join(ROOT, "shared", "fixtures", "daily.json")
EPOCH = datetime.date(2026, 1, 1)

LANGS = ["en", "es", "fr", "id", "tr", "ur"]
HADITH_COUNT = 365
HADITH_MAX_CHARS = 110
GRADES = {"صحيح", "حسن"}
ARABIC_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
SEPARATOR = "⁣"  # between a pack entry's parts (main text, then footnotes or explanation)


def read_chunks(name):
    with open(os.path.join(SOURCES, name, "chunks.jsonl"), encoding="utf-8") as f:
        for line in f:
            yield json.loads(line)


def main_text(text):
    return text.split(SEPARATOR, 1)[0].strip()


def without_footnote_marks(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == "[":
            j = text.find("]", i)
            if j != -1 and text[i + 1:j].isdigit():
                i = j + 1
                continue
        out.append(text[i])
        i += 1
    return "".join(out).strip()


def parse_refs():
    refs = []
    with open(AYAT, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            surah, ayat = line.split(":")
            first, _, last = ayat.partition("-")
            refs.append((int(surah), int(first), int(last or first)))
    return refs


def build_ayat():
    arabic, english, names = {}, {}, {}
    for c in read_chunks("quran-tanzil-pickthall"):
        s = c["section"]
        key = (s["surah"], s["ayah"])
        arabic[key] = c["original"]["text"]
        english[key] = c["translations"][0]["text"]
        names[s["surah"]] = {"ar": s["nameAr"], "en": s["nameEn"], "translit": s["nameTranslit"]}
    other = {lang: {} for lang in LANGS if lang != "en"}
    for lang in other:
        for c in read_chunks(f"quranenc-{lang}"):
            s = c["section"]
            text = without_footnote_marks(main_text(c["original"]["text"]))
            other[lang][(s["surah"], s["ayah"])] = re.sub(r"^\d+\.\s*", "", text)  # some translators number each verse

    ayat = []
    for surah, first, last in parse_refs():
        keys = [(surah, a) for a in range(first, last + 1)]
        missing = [k for k in keys if k not in arabic]
        if missing:
            sys.exit(f"ayat.txt: no such verse {missing[0][0]}:{missing[0][1]}")
        translations = {"en": " ".join(english[k] for k in keys)}
        for lang, table in other.items():
            if all(k in table for k in keys):
                translations[lang] = " ".join(table[k] for k in keys)
        ayat.append({
            "ref": f"{surah}:{first}" + (f"-{last}" if last != first else ""),
            "surah": surah, "first": first, "last": last,
            "surahName": names[surah],
            "ar": " ".join(f"{arabic[k]} ﴿{str(k[1]).translate(ARABIC_DIGITS)}﴾" for k in keys),
            "translations": translations,
        })
    return ayat


def build_hadith():
    arabic = {}
    for c in read_chunks("hadeethenc-ar"):
        s = c["section"]
        if s.get("grade") in GRADES and len(c["anchor"]) <= HADITH_MAX_CHARS:
            arabic[s["itemId"]] = {"text": c["anchor"], "grade": s["grade"], "source": s["source"], "version": s["version"]}
    translated = {lang: {} for lang in LANGS}
    for lang in LANGS:
        for c in read_chunks(f"hadeethenc-{lang}"):
            s = c["section"]
            if s["itemId"] in arabic:
                translated[lang][s["itemId"]] = {"text": c["anchor"], "grade": s["grade"], "source": s["source"]}
    ids = sorted(i for i in arabic if all(i in translated[lang] for lang in LANGS))
    if len(ids) < HADITH_COUNT:
        sys.exit(f"only {len(ids)} hadith qualify, need {HADITH_COUNT}")
    picked = [ids[round(n * (len(ids) - 1) / (HADITH_COUNT - 1))] for n in range(HADITH_COUNT)]
    return [{
        "id": i,
        "ar": arabic[i],
        "translations": {lang: translated[lang][i] for lang in LANGS},
        "url": f"https://hadeethenc.com/ar/browse/hadith/{i}",
    } for i in picked]


def day_index(date, count):
    """The rule both apps use: whole days since EPOCH (the person's local calendar date), wrapped to the list."""
    return (date - EPOCH).days % count


def build_fixture(data):
    dates = [datetime.date(2026, 1, 1), datetime.date(2026, 1, 2), datetime.date(2025, 12, 31),
             datetime.date(2026, 3, 1), datetime.date(2026, 10, 22), datetime.date(2027, 1, 1),
             datetime.date(2028, 2, 29), datetime.date(2031, 6, 15)]
    cases = []
    for d in dates:
        a, h = day_index(d, len(data["ayat"])), day_index(d, len(data["hadith"]))
        cases.append({"date": d.isoformat(), "ayahIndex": a, "ayahRef": data["ayat"][a]["ref"],
                      "hadithIndex": h, "hadithId": data["hadith"][h]["id"]})
    return {"_comment": "Generated by tools/build_daily.py: the day's verse and hadith for both apps.",
            "ayatCount": len(data["ayat"]), "hadithCount": len(data["hadith"]), "cases": cases}


def build():
    return {
        "_comment": "Generated by tools/build_daily.py; do not edit.",
        "version": 1,
        "epoch": EPOCH.isoformat(),
        "attribution": {
            "quran": "Qur'an text: Tanzil.net. English: Pickthall. Other translations: QuranEnc.com.",
            "hadith": "HadeethEnc.com (Encyclopedia of Translated Prophetic Hadiths)",
        },
        "ayat": build_ayat(),
        "hadith": build_hadith(),
    }


def main():
    data = build()
    outputs = {OUT: json.dumps(data, ensure_ascii=False, indent=1) + "\n",
               FIXTURE: json.dumps(build_fixture(data), ensure_ascii=False, indent=2) + "\n"}
    if "--check" in sys.argv:
        for path, text in outputs.items():
            with open(path, encoding="utf-8") as f:
                if f.read() != text:
                    sys.exit(f"{os.path.relpath(path, ROOT)} is out of date: run python3 tools/build_daily.py")
        return
    for path, text in outputs.items():
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    text = outputs[OUT]
    print(f"{len(data['ayat'])} verses, {len(data['hadith'])} hadith, {len(text.encode()) // 1024} KB")


if __name__ == "__main__":
    main()
