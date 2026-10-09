#!/usr/bin/env python3
"""Prove two distinct signed binaries share a synthetic Keychain item without UI."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
from signing import sign, verify

SOURCE = r'''
import Foundation
import Security
SecKeychainSetUserInteractionAllowed(false)
let service = CommandLine.arguments[1]
let operation = CommandLine.arguments[2]
var keychain: SecKeychain?
let opened = SecKeychainOpen(CommandLine.arguments[3], &keychain)
guard opened == errSecSuccess, let keychain else {exit(4)}
let query: [String:Any] = [kSecMatchSearchList as String:[keychain], kSecClass as String:kSecClassGenericPassword,
  kSecAttrService as String:service, kSecAttrAccount as String:"signing-regression"]
var attributes = query
attributes[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
let status: OSStatus
switch operation {
case "create":
  attributes[kSecUseKeychain as String] = keychain
  attributes[kSecValueData as String] = Data("synthetic-signing-test".utf8)
  status = SecItemAdd(attributes as CFDictionary,nil)
case "read":
  attributes[kSecReturnData as String] = true
  var value: CFTypeRef?
  status = SecItemCopyMatching(attributes as CFDictionary,&value)
  if status == errSecSuccess && value as? Data != Data("synthetic-signing-test".utf8) {exit(3)}
case "delete": status = SecItemDelete(attributes as CFDictionary)
default: print("BUILD_MARKER"); exit(0)
}
print(status)
'''


def status(binary, service, operation):
    result = subprocess.run([str(binary), service, operation, str(test_keychain)], capture_output=True, text=True, check=True)
    return int(result.stdout.strip())

with tempfile.TemporaryDirectory(prefix='StudioSigningRegression-', dir='/tmp') as folder:
    root = Path(folder)
    first, second, adhoc = root/'first', root/'second', root/'adhoc'
    test_keychain = root/'synthetic.keychain-db'
    subprocess.run(['security','create-keychain','-p','synthetic-isolated-test',str(test_keychain)],check=True)
    identifier = 'local.mssqlstudio.signing-regression'
    for name, binary in [('FIRST_BUILD', first), ('SECOND_BUILD', second)]:
        source = root/(name+'.swift')
        source.write_text(SOURCE.replace('BUILD_MARKER', name))
        subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
        sign(binary, identifier)
    assert first.read_bytes() != second.read_bytes(), 'Test binaries must actually differ'
    shutil.copyfile(second, adhoc)
    adhoc.chmod(0o700)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', identifier, str(adhoc)], check=True)
    try:
        verify(adhoc, identifier)
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError('Signing policy accepted an ad-hoc replacement')
    service = 'local.mssqlstudio.signing-test.'+str(uuid.uuid4())
    installed = root/'installed'
    shutil.copy2(first,installed)
    created = False
    try:
        assert status(installed, service, 'create') == 0, 'Cannot create isolated Keychain fixture'
        created = True
        shutil.copy2(second,installed)
        read_status = status(installed, service, 'read')
        assert read_status == 0, 'Second signed build required Keychain authorization: '+str(read_status)
        shutil.copy2(adhoc,installed)
        assert status(installed, service, 'read') != 0, 'Unrelated ad-hoc binary gained access'
    finally:
        if created:
            shutil.copy2(first,installed)
            assert status(installed, service, 'delete') == 0, 'Synthetic Keychain cleanup failed'
        subprocess.run(['security','delete-keychain',str(test_keychain)],check=True)
print('PASS: distinct builds, stable certificate/requirement, prompt-free isolated-keychain read, ad-hoc rejection, synthetic item cleanup.')
