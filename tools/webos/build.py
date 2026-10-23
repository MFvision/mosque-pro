#!/usr/bin/env python3
"""Builds the Mosque Pro TV screen as an LG webOS app: build/webos/MosquePro-webos.ipk.

    python3 tools/webos/build.py            # → build/webos/MosquePro-webos.ipk
    python3 tools/webos/build.py --preview  # also leaves the app's files in build/webos/app/ to open in a browser

Takes the TV page (website/tv/) with what it uses from the site (places, prayer times, the daily verse and hadith,
the Adhan sound, the time zones) and packs it the way LG's ares-package does: an ar archive with control.tar.gz and
data.tar.gz, so no LG tools are needed. A TV app runs from its own files (file://), where module scripts don't load,
so the four modules become one plain script, app.js. Python 3 only. Packing after Free My TV's webos/build.py
(github.com/simbasjungles/free-my-tv, MIT).
"""
import io
import json
import os
import re
import sys
import tarfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(ROOT, 'website')
OUT = os.path.join(ROOT, 'build', 'webos')
IPK = os.path.join(OUT, 'MosquePro-webos.ipk')

# Older TV Chromium: Object.fromEntries (Chromium 73) and catch without a binding (66) are the newer bits prayer.js uses.
SHIM = ("if (!Object.fromEntries) Object.fromEntries = function (l) { var o = {}; "
        "Array.from(l).forEach(function (e) { o[e[0]] = e[1]; }); return o; };\n")


def read(*parts):
    with open(os.path.join(*parts), 'rb') as f:
        return f.read()


def plain(js):
    """One module as plain script: no imports, no export keywords, catch with a binding."""
    js = re.sub(r'^import [^;]+;\n', '', js, flags=re.M)
    js = re.sub(r'^export (const|let|function|async function|class) ', r'\1 ', js, flags=re.M)
    return js.replace('catch {', 'catch (e) {')


def app_files():
    files = {}
    for name in ('index.html', 'tv.css', 'daily.json', 'launcher.js', 'wall.jpg'):
        files['tv/' + name] = read(SITE, 'tv', name)
    html = files['tv/index.html'].decode('utf-8')
    html = html.replace('<script type="module" src="tv.js"></script>', '<script src="app.js"></script>')
    assert 'src="app.js"' in html, 'website/tv/index.html no longer loads tv.js as expected'
    files['tv/index.html'] = html.encode('utf-8')
    parts = [plain(read(SITE, n).decode('utf-8')) for n in ('places.js', 'prayer.js')]
    parts.append(plain(read(SITE, 'tv', 'mosque.js').decode('utf-8')))
    parts.append(plain(read(SITE, 'tv', 'tv.js').decode('utf-8')))
    files['tv/app.js'] = ('(function () {\n"use strict";\n' + SHIM + '\n'.join(parts) + '\n})();\n').encode('utf-8')
    for name in ('adhan.mp3', 'zones.json', 'icon-180.png', 'kaaba-tawaf.mp4'):
        if os.path.exists(os.path.join(SITE, 'assets', name)):  # an older sparse checkout may not have the film yet
            files['assets/' + name] = read(SITE, 'assets', name)
    for name in ('appinfo.json', 'icon.png', 'largeIcon.png'):
        files[name] = read(HERE, name)
    return files


def tar_gz(entries):
    """A .tar.gz from [(name, bytes or None for a directory)], owned by root, as ares-package makes them."""
    buf = io.BytesIO()
    now = int(time.time())
    with tarfile.open(fileobj=buf, mode='w:gz', format=tarfile.PAX_FORMAT) as tar:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.mtime = now
            info.uid = info.gid = 0
            if data is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                tar.addfile(info)
            else:
                info.size = len(data)
                info.mode = 0o644
                tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def ar(members):
    out = io.BytesIO()
    out.write(b'!<arch>\n')
    now = int(time.time())
    for name, data in members:
        out.write(('%-16s%-12d%-6d%-6d%-8s%-10d`\n' % (name, now, 0, 0, '100644', len(data))).encode('ascii'))
        out.write(data)
        if len(data) % 2:
            out.write(b'\n')
    return out.getvalue()


def build(preview):
    info = json.loads(read(HERE, 'appinfo.json'))
    app_id, version = info['id'], info['version']
    app = app_files()
    base = 'usr/palm/applications/' + app_id
    entries = [('usr', None), ('usr/palm', None), ('usr/palm/applications', None), (base, None)]
    dirs = set()
    for path in sorted(app):
        parent = os.path.dirname(path)
        if parent and parent not in dirs:
            dirs.add(parent)
            entries.append((base + '/' + parent, None))
        entries.append((base + '/' + path, app[path]))
    package = json.dumps({'id': app_id, 'version': version, 'app': app_id}, indent=2).encode('utf-8')
    entries += [('usr/palm/packages', None), ('usr/palm/packages/' + app_id, None),
                ('usr/palm/packages/' + app_id + '/packageinfo.json', package)]
    data = tar_gz(entries)
    control = ('Package: %s\nVersion: %s\nSection: misc\nPriority: optional\nArchitecture: all\n'
               'Installed-Size: %d\nMaintainer: Mosque Pro\nDescription: %s\nwebOS-Package-Format-Version: 2\n'
               'webOS-Packager-Version: x.y.x\n' % (app_id, version, sum(len(v) for v in app.values()) // 1024 + 1, info['title']))
    os.makedirs(OUT, exist_ok=True)
    with open(IPK, 'wb') as f:
        f.write(ar([('debian-binary', b'2.0\n'), ('control.tar.gz', tar_gz([('control', control.encode('utf-8'))])),
                    ('data.tar.gz', data)]))
    if preview:
        for path, body in app.items():
            dest = os.path.join(OUT, 'app', path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, 'wb') as f:
                f.write(body)
    print('Built %s (%d KB)' % (os.path.relpath(IPK, ROOT), os.path.getsize(IPK) // 1024))


if __name__ == '__main__':
    build('--preview' in sys.argv)
