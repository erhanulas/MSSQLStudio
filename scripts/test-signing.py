#!/usr/bin/env python3
"""Prove two distinct signed binaries share a synthetic Keychain item without UI."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
from signing import sign, verify, requirement

VAULT_SOURCE = (Path(__file__).resolve().parent.parent / 'Sources/SQLServerKit/Persistence.swift').read_text().split('public struct QueryRecord:')[0]
SOURCE = r'''
import Foundation
import Security
public struct ServerProfile: Codable, Sendable {
  public var id=UUID(uuidString:"11111111-2222-3333-4444-555555555555")!
  public var name="Synthetic signing fixture"
}
public struct SQLFailure: Error {public init(_ message:String) {}}
public enum PersonalSigningIdentity {
  public static func requirement() throws -> String { #"PINNED_REQUIREMENT"# }
}
VAULT_SOURCE
SecKeychainSetUserInteractionAllowed(false)
let service = CommandLine.arguments[1]
let operation = CommandLine.arguments[2]
let vault=ServerVault(service:service,keychainPath:CommandLine.arguments[3])
let profile=ServerProfile()
var keychain:SecKeychain?
guard SecKeychainOpen(CommandLine.arguments[3],&keychain) == errSecSuccess,let keychain else {exit(4)}
do {
  switch operation {
  case "renew":
    guard try vault.renewApplicationAccess() == 1 else {exit(5)}
  case "read":
    let records=try vault.list()
    guard records.count == 1,records.first?.password == "synthetic-signing-test",records.first?.profile.id == profile.id else {exit(3)}
  case "save": try vault.save(profile,password:"synthetic-signing-test")
  case "delete": try vault.delete(profile.id)
  default: print("BUILD_MARKER");exit(0)
  }
  print(0)
} catch {print(-1)}
'''.replace('VAULT_SOURCE',VAULT_SOURCE).replace('PINNED_REQUIREMENT',requirement('local.mssqlstudio.signing-regression'))



def status(binary, service, operation):
    result = subprocess.run([str(binary), service, operation, str(test_keychain)], capture_output=True, text=True, check=True, timeout=20)
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
        assert status(installed, service, 'save') == 0, 'Cannot create isolated Keychain fixture'
        created = True
        assert status(installed, service, 'save') == 0, 'Vault update failed'
        shutil.copy2(second,installed)
        read_status = status(installed, service, 'read')
        assert read_status == 0, 'Second signed build required Keychain authorization: '+str(read_status)
        assert status(installed, service, 'save') == 0, 'Updated build could not save credentials'
        moved = root/'moved-installation'
        shutil.copy2(second,moved)
        assert status(moved, service, 'read') == 0, 'Stable identity depended on installation path'
        shutil.copy2(first,installed)
        assert status(installed, service, 'read') == 0, 'Updated credentials did not preserve cross-build access'
        shutil.copy2(adhoc,installed)
        assert status(installed, service, 'read') != 0, 'Unrelated ad-hoc binary gained access'
        assert status(installed, service, 'renew') != 0, 'Unrelated ad-hoc binary renewed access'
    finally:
        try:
            if created:
                shutil.copy2(first,installed)
                assert status(installed, service, 'delete') == 0, 'Synthetic Keychain cleanup failed'
        finally:
            subprocess.run(['security','delete-keychain',str(test_keychain)],check=True)
print('PASS: distinct builds, stable certificate/requirement, real ServerVault create/update, credentials preserved, prompt-free cross-build and moved-path isolated-keychain read, ad-hoc rejection, synthetic item cleanup.')
