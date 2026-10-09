#!/usr/bin/env python3
"""Personal signing policy. This file contains public certificate identity only."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

CONFIG = Path(__file__).resolve().parent.parent / 'Sources/SQLServerKit/Resources/SigningIdentity.json'

def policy():
    config = json.loads(CONFIG.read_text())
    if not re.fullmatch(r'[0-9a-f]{40}', config['certificateSHA1']):
        raise ValueError('Invalid signing certificate fingerprint')
    if not re.fullmatch(r'[A-Za-z0-9.-]+', config['bundleIdentifier']):
        raise ValueError('Invalid signing bundle identifier')
    return config

def requirement(identifier=None):
    config = policy()
    name = identifier or config['bundleIdentifier']
    if not re.fullmatch(r'[A-Za-z0-9.-]+', name):
        raise ValueError('Invalid signing identifier')
    return f'identifier "{name}" and certificate leaf = H"{config["certificateSHA1"]}"'

def verify(path, identifier=None):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '-R', '=' + requirement(identifier), str(path)], check=True)
    result = subprocess.run(['codesign', '-d', '-r-', str(path)], capture_output=True, text=True, check=True)
    if result.stdout.strip() != 'designated => ' + requirement(identifier):
        raise ValueError('Signature designated requirement is not the stable personal identity')

def sign(path, identifier=None):
    config = policy()
    command = ['codesign', '--force', '--sign', config['certificateSHA1'], '--timestamp=none', '--identifier', identifier or config['bundleIdentifier'], '--requirements', '=designated => ' + requirement(identifier)]
    if os.environ.get('MSSQL_SIGNING_KEYCHAIN'):
        command += ['--keychain', os.environ['MSSQL_SIGNING_KEYCHAIN']]
    subprocess.run(command + [str(path)], check=True)
    verify(path, identifier)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['sign', 'verify'])
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    (sign if args.operation == 'sign' else verify)(args.path)
