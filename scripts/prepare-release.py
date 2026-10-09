#!/usr/bin/env python3
"""Validate local release bytes and write the public GitHub update manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile


def prepare(repository, tag, output):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) or any(p in {'.','..'} for p in repository.split('/')):
        raise ValueError('Invalid GitHub owner/repository')
    if not re.fullmatch(r'v[0-9]+(?:\.[0-9]+){1,3}', tag):
        raise ValueError('Release tag must be v followed by a numeric version')
    version = tag[1:]
    archive = output / f'MSSQLStudio-{version}.zip'
    package = output / f'MSSQLStudio-{version}.pkg'
    if not archive.is_file() or not package.is_file():
        raise ValueError('Both ZIP and PKG must exist before publication')
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            parts = entry.filename.split('/')
            if parts[0] != 'MSSQLStudio.app' or '..' in parts or '\\' in entry.filename or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe ZIP entry')
        if z.testzip():
            raise ValueError('Corrupt ZIP')
        info = plistlib.loads(z.read('MSSQLStudio.app/Contents/Info.plist'))
    expected_feed=f'https://github.com/{repository}/releases/latest/download/update.json'
    if info.get('CFBundleIdentifier') != 'local.mssqlstudio.app' or info.get('CFBundleShortVersionString') != version:
        raise ValueError('Tag and signed application version/bundle do not match')
    if info.get('MSSQLUpdateFeedURL') != expected_feed:
        raise ValueError('Application update source does not match release repository')
    with tempfile.TemporaryDirectory(prefix='StudioRelease-',dir='/tmp') as temp:
        subprocess.run(['ditto','-x','-k',str(archive),temp],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(Path(temp)/'MSSQLStudio.app')],check=True)
        expanded=Path(temp)/'pkg'
        subprocess.run(['pkgutil','--expand-full',str(package),str(expanded)],check=True)
        payload=expanded/'MSSQLStudio-component.pkg/Payload/Applications/MSSQLStudio.app'
        subprocess.run(['codesign','--verify','--deep','--strict',str(payload)],check=True)
        package_info=plistlib.loads((payload/'Contents/Info.plist').read_bytes())
        if package_info != info:
            raise ValueError('PKG and ZIP application metadata do not match')
        binary=Path(temp)/'MSSQLStudio.app/Contents/MacOS/MSSQLStudio'
        if binary.read_bytes() != (payload/'Contents/MacOS/MSSQLStudio').read_bytes():
            raise ValueError('PKG and ZIP application binaries do not match')
    manifest={'version':version,'downloadURL':f'https://github.com/{repository}/releases/download/{tag}/{archive.name}','sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
    (output/'update.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--repository',required=True)
    parser.add_argument('--tag',required=True)
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'releases')
    args=parser.parse_args()
    print(json.dumps(prepare(args.repository,args.tag,args.output)))
