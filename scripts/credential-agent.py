#!/usr/bin/env python3
"""Reuse immutable signed credential code; changing its CDHash would reintroduce prompts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from signing import sign, verify, requirement

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'installer/CredentialAgent-v1.json'
NAME = 'MSSQLStudioCredentials'
ARCHIVE = 'MSSQLStudio-CredentialAgent-v1.zip'

def prepare(output):
    config = json.loads(CONFIG.read_text())
    source = ROOT / 'Tools/CredentialAgent/main.m'
    if hashlib.sha256(source.read_bytes()).hexdigest() != config['sourceSHA256']:
        raise ValueError('Credential agent v1 source is frozen. Plan an explicit identity migration for v2.')
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ARCHIVE
    if not archive.exists():
        if config['archiveSHA256']:
            url = f"https://github.com/erhanulas/MSSQLStudio/releases/download/{config['originTag']}/{ARCHIVE}"
            request = urllib.request.Request(url, headers={'User-Agent': 'MSSQLStudio-credential-build'})
            data = urllib.request.urlopen(request, timeout=90).read(8 * 1024 * 1024)
            if hashlib.sha256(data).hexdigest() != config['archiveSHA256']:
                raise ValueError('Frozen credential archive digest mismatch')
            archive.write_bytes(data)
        else:
            if os.environ.get('RELEASE_TAG') != config['originTag'] or os.environ.get('GITHUB_ACTIONS') != 'true':
                raise ValueError('Unpinned credential agent may bootstrap only on its original release tag')
            with tempfile.TemporaryDirectory(prefix='StudioCredentialBootstrap-', dir='/tmp') as folder:
                executable = Path(folder) / NAME
                subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Werror', '-Wno-deprecated-declarations',
                    '-mmacosx-version-min=27.0', '-framework', 'Foundation', '-framework', 'Security',
                    '-DSTUDIO_REQUIREMENT=' + json.dumps(requirement()), str(source), '-o', str(executable)], check=True)
                # The agent deliberately shares the app's DR, preserving the trusted-app ACL gate.
                # Its *unchanging* bytes separately preserve the XARA partition gate.
                sign(executable)
                with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
                    z.write(executable, NAME)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if config['archiveSHA256'] and digest != config['archiveSHA256']:
        raise ValueError('Frozen credential archive changed')
    with zipfile.ZipFile(archive) as z:
        if z.namelist() != [NAME] or z.getinfo(NAME).file_size > 4 * 1024 * 1024 or z.testzip():
            raise ValueError('Invalid frozen credential archive')
        data = z.read(NAME)
    if config['binarySHA256'] and hashlib.sha256(data).hexdigest() != config['binarySHA256']:
        raise ValueError('Credential executable changed')
    executable = output / NAME
    executable.write_bytes(data)
    executable.chmod(0o755)
    verify(executable)
    print('Frozen credential executable verified:', hashlib.sha256(data).hexdigest())
    return executable, archive

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    executable, archive = prepare(args.output)
    if args.app:
        target = args.app / 'Contents/Helpers' / NAME
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(executable, target)
