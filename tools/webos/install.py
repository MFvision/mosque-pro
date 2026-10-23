#!/usr/bin/env python3
"""Installs the Mosque Pro TV app on an LG TV in Developer Mode, over your Wi-Fi.

    python3 tools/webos/install.py 192.168.1.7              # build, install or update, then open it
    python3 tools/webos/install.py 192.168.1.7 --uninstall  # remove it

The TV needs Developer Mode on (LG's "Developer Mode" app, a free LG developer account, Dev Mode Status and Key
Server on). The first time, this downloads the TV's key from its Key Server and asks for the passphrase the app shows
(it is not stored); a key already unlocked for Free My TV (~/.ssh/freemytv_webos_<IP>) is used as it is. The app is
copied over SSH (port 9922) and installed with the TV's own installer, the way LG's tools do it. Python 3 and
OpenSSH only. Install flow after Free My TV's webos/install.py (github.com/simbasjungles/free-my-tv, MIT).
"""
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
IPK = os.path.join(ROOT, 'build', 'webos', 'MosquePro-webos.ipk')
with open(os.path.join(HERE, 'appinfo.json'), encoding='utf-8') as f:
    APP_ID = json.load(f)['id']
TEMP = '/media/developer/temp/mosquepro.ipk'
SSH_OPTS = ['-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=' + os.devnull, '-o', 'LogLevel=ERROR',
            '-o', 'HostKeyAlgorithms=+ssh-rsa', '-o', 'PubkeyAcceptedKeyTypes=+ssh-rsa', '-p', '9922']


def key_path(ip, name='mosquepro'):
    return os.path.join(os.path.expanduser('~'), '.ssh', '%s_webos_%s' % (name, ip.replace('.', '_')))


def fetch_key(ip):
    """The TV's SSH key: one already unlocked here, else from its Key Server with the passphrase the TV shows."""
    for path in (key_path(ip), key_path(ip, 'freemytv')):
        if os.path.exists(path):
            return path
    path = key_path(ip)
    url = 'http://%s:9991/webos_rsa' % ip
    print('Getting the TV\'s key from %s ...' % url)
    try:
        with urllib.request.urlopen(url, timeout=6) as r:
            data = r.read()
    except Exception as e:
        sys.exit('Couldn\'t reach the Key Server (%s). In the TV\'s Developer Mode app, turn on Key Server.' % e)
    passphrase = getpass.getpass('Passphrase shown in Developer Mode on the TV (capitals): ').strip().upper()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.write(data)
    tmp.close()
    os.chmod(tmp.name, 0o600)
    unlock = subprocess.run(['ssh-keygen', '-p', '-P', passphrase, '-N', '', '-f', tmp.name], capture_output=True, text=True)
    if unlock.returncode != 0:
        os.unlink(tmp.name)
        sys.exit('That passphrase didn\'t unlock the key. Check it on the TV (Developer Mode) and try again.')
    shutil.move(tmp.name, path)
    os.chmod(path, 0o600)
    return path


def ssh(ip, key, command, stdin=None, tty=False):
    args = ['ssh'] + (['-tt'] if tty else []) + SSH_OPTS + ['-i', key, 'prisoner@' + ip, command]
    return subprocess.run(args, stdin=stdin, capture_output=True, text=stdin is None)


def luna(ip, key, uri, payload, replies=1, wait=20):
    # luna-send-pub prints nothing without a terminal (-tt); older webOS has BusyBox's timeout -t; webOS 6 may refuse
    # the terminal, where -i streams the replies without one.
    timeout = "if timeout -t 1 true 2>/dev/null; then T='timeout -t %d'; else T='timeout %d'; fi; " % (wait, wait)
    message = "%s '%s'" % (uri, json.dumps(payload, separators=(',', ':')))
    out = ssh(ip, key, timeout + '$T luna-send-pub -n %d %s' % (replies, message), tty=True).stdout or ''
    if not out.strip():
        out = ssh(ip, key, timeout + '$T luna-send-pub -i %s </dev/null' % message).stdout or ''
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args or not re.match(r'^\d{1,3}(\.\d{1,3}){3}$', args[0]):
        sys.exit(__doc__)
    ip = args[0]
    if not shutil.which('ssh') or not shutil.which('ssh-keygen'):
        sys.exit('OpenSSH (ssh and ssh-keygen) is needed.')
    key = fetch_key(ip)

    if '--uninstall' in sys.argv:
        out = luna(ip, key, 'luna://com.webos.appInstallService/dev/remove', {'id': APP_ID}, replies=3, wait=30)
        print('Removed.' if '"returnValue":true' in out else 'The TV said: ' + out.strip())
        return

    subprocess.run([sys.executable, os.path.join(HERE, 'build.py')], check=True)
    print('Copying Mosque Pro to the TV ...')
    with open(IPK, 'rb') as f:
        copy = ssh(ip, key, 'mkdir -p /media/developer/temp && cat > ' + TEMP, stdin=f)
    if copy.returncode != 0:
        err = copy.stderr.decode('utf-8', 'replace') if isinstance(copy.stderr, bytes) else copy.stderr
        sys.exit('Couldn\'t copy it: %s\nIs Developer Mode still on? If the key changed, delete %s and try again.' % (err.strip(), key))
    print('Installing ...')
    out = luna(ip, key, 'luna://com.webos.appInstallService/dev/install', {'id': APP_ID, 'ipkUrl': TEMP, 'subscribe': True},
               replies=30, wait=60)
    if '"state":"installed"' not in out:
        sys.exit('The TV didn\'t finish installing. It said:\n' + out.strip())
    ssh(ip, key, 'rm -f ' + TEMP)
    luna(ip, key, 'luna://com.webos.applicationManager/launch', {'id': APP_ID})
    print('Mosque Pro is installed and open on the TV.')
    print('Tip: while it is open, hold a number key (for example 2) to open it with that key from anywhere.')


if __name__ == '__main__':
    main()
