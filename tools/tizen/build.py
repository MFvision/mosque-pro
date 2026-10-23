#!/usr/bin/env python3
"""Builds the Mosque Pro TV screen as a Samsung (Tizen) TV app: build/tizen/MosquePro.wgt.

    python3 tools/tizen/build.py

The same files as the LG app (tools/webos/build.py: the TV page as one plain script, with the Adhan, the film and the
time zones), with Samsung's config.xml, zipped as a .wgt. It is unsigned: Samsung TVs take only apps signed with the
owner's Samsung certificate, so TizenBrew Installer (github.com/reisxd/TizenBrewInstaller) signs and installs it from
this repository's latest release. Python 3 only.
"""
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'webos'))
import build as webos  # noqa: E402

OUT = os.path.join(ROOT, 'build', 'tizen')
WGT = os.path.join(OUT, 'MosquePro.wgt')


def main():
    files = {k: v for k, v in webos.app_files().items() if k not in ('appinfo.json', 'icon.png', 'largeIcon.png')}
    files['config.xml'] = webos.read(HERE, 'config.xml')
    files['icon.png'] = webos.read(HERE, 'icon.png')
    os.makedirs(OUT, exist_ok=True)
    with zipfile.ZipFile(WGT, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(files):
            # The film and the Adhan are compressed already.
            z.writestr(path, files[path], zipfile.ZIP_STORED if path.endswith(('.mp4', '.mp3', '.png', '.jpg')) else zipfile.ZIP_DEFLATED)
    print('Built %s (%d KB)' % (os.path.relpath(WGT, ROOT), os.path.getsize(WGT) // 1024))


if __name__ == '__main__':
    main()
