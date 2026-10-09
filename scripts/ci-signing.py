#!/usr/bin/env python3
"""Import the persistent private identity only into a disposable CI keychain."""
import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile


def security(*args):
    result = subprocess.run(['security', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Temporary signing keychain operation failed')
    return result.stdout


def import_identity():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('CI identity import is only available on GitHub Actions')
    p12 = os.environ.get('MSSQL_SIGNING_P12', '')
    password = os.environ.get('MSSQL_SIGNING_PASSWORD', '')
    if not p12 or not password:
        raise RuntimeError('Persistent signing secrets are required; ad-hoc releases are not permitted')
    keychain = Path(os.environ['RUNNER_TEMP'])/'mssqlstudio-signing.keychain-db'
    if keychain.exists():
        raise RuntimeError('Refusing to replace an existing signing keychain')
    keychain_password = secrets.token_urlsafe(40)
    try:
        security('create-keychain', '-p', keychain_password, str(keychain))
        security('set-keychain-settings', '-lut', '21600', str(keychain))
        security('unlock-keychain', '-p', keychain_password, str(keychain))
        with tempfile.TemporaryDirectory(prefix='StudioIdentity-', dir=os.environ['RUNNER_TEMP']) as folder:
            identity = Path(folder)/'identity.p12'
            identity.write_bytes(base64.b64decode(p12, validate=True))
            identity.chmod(0o600)
            security('import', str(identity), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign')
        security('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', keychain_password, str(keychain))
        previous_default = shlex.split(security('default-keychain', '-d', 'user'))
        current = shlex.split(security('list-keychains', '-d', 'user'))
        security('list-keychains', '-d', 'user', '-s', str(keychain), *current)
        security('default-keychain', '-d', 'user', '-s', str(keychain))
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            output.write(f'MSSQL_SIGNING_KEYCHAIN={keychain}\n')
            if previous_default:
                output.write(f'MSSQL_PREVIOUS_DEFAULT_KEYCHAIN={previous_default[0]}\n')
    except BaseException:
        if keychain.exists():
            security('delete-keychain', str(keychain))
        raise
    print('Persistent personal identity imported into disposable CI keychain.')


def cleanup():
    path = os.environ.get('MSSQL_SIGNING_KEYCHAIN')
    if path and Path(path).exists():
        previous = os.environ.get('MSSQL_PREVIOUS_DEFAULT_KEYCHAIN')
        if previous and Path(previous).exists():
            security('default-keychain', '-d', 'user', '-s', previous)
        security('delete-keychain', path)
    print('Disposable signing keychain removed.')

if __name__ == '__main__':
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in {'import', 'cleanup'}:
            raise RuntimeError('Use import or cleanup')
        (import_identity if sys.argv[1] == 'import' else cleanup)()
    except Exception as error:
        # Avoid exceptions containing subprocess arguments or secret values.
        print(str(error) if isinstance(error, RuntimeError) else 'Signing identity setup failed', file=sys.stderr)
        sys.exit(1)
