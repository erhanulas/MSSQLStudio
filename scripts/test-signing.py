#!/usr/bin/env python3
"""Prove two distinct signed binaries share a synthetic Keychain item without UI."""
from pathlib import Path
import importlib.util
import os
import shutil
import subprocess
import tempfile
import uuid
from signing import sign, verify, requirement

_spec=importlib.util.spec_from_file_location('credential_agent',Path(__file__).parent/'credential-agent.py')
_agent=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_agent)
if not os.environ.get('RUNNER_TEMP') or os.environ.get('GITHUB_ACTIONS') != 'true' or not os.environ.get('GITHUB_RUN_ID', '').isdigit():
    raise RuntimeError('Partition audit runs only in disposable CI; never use the real user login keychain')
agent, agent_archive = _agent.prepare(Path(os.environ['RUNNER_TEMP'])/('MSSQLStudio-credential-v1-'+os.environ['GITHUB_RUN_ID']))
unauthorized = subprocess.run([str(agent)],input=b'{}',capture_output=True,timeout=20)
assert unauthorized.returncode == 77 and not unauthorized.stdout, 'Helper accepted an unauthorized launcher'

VAULT_SOURCE = (Path(__file__).resolve().parent.parent / 'Sources/SQLServerKit/Persistence.swift').read_text().split('public struct QueryRecord:')[0]
SOURCE = r'''
import Foundation
import Security
public struct ServerProfile: Codable, Sendable {
  public var id=UUID(uuidString:"11111111-2222-3333-4444-555555555555")!
  public var name="Synthetic signing fixture"
}
public struct SQLFailure: Error {let message:String;public init(_ message:String) {self.message=message}}
public enum PersonalSigningIdentity {
  public static func requirement() throws -> String { #"PINNED_REQUIREMENT"# }
}
AGENT_SOURCE
VAULT_SOURCE
SecKeychainSetUserInteractionAllowed(false)
let service = CommandLine.arguments[1]
let operation = CommandLine.arguments[2]
let vault=ServerVault(service:service,keychainPath:CommandLine.arguments[3],credentialAgentURL:CommandLine.arguments[4] == "-" ? nil : URL(fileURLWithPath:CommandLine.arguments[4]))
let profile=ServerProfile()
var keychain:SecKeychain?
guard SecKeychainOpen(CommandLine.arguments[3],&keychain) == errSecSuccess,let keychain else {exit(4)}
do {
  switch operation {
  case "partition":
    let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:profile.id.uuidString,kSecMatchSearchList as String:[keychain],kSecReturnRef as String:true]
    var item:CFTypeRef?,access:SecAccess?
    guard SecItemCopyMatching(query as CFDictionary,&item) == errSecSuccess, let item else {exit(8)}
    guard SecKeychainItemCopyAccess(item as! SecKeychainItem,&access) == errSecSuccess, let access else {exit(9)}
    let partitions=SecAccessCopyMatchingACLList(access,kSecACLAuthorizationPartitionID) as? [SecACL] ?? []
    guard partitions.count == 1 else {exit(10)}
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
} catch { if let error=error as? SQLFailure {FileHandle.standardError.write(Data(error.message.utf8))}; print(-1)}
'''.replace('AGENT_SOURCE',(Path(__file__).resolve().parent.parent/'Sources/SQLServerKit/CredentialAgent.swift').read_text()).replace('VAULT_SOURCE',VAULT_SOURCE).replace('PINNED_REQUIREMENT',requirement())



def status(binary, service, operation, helper=False):
    result = subprocess.run([str(binary), service, operation, str(test_keychain), str(agent) if helper else "-"], capture_output=True, text=True, check=True, timeout=20)
    value=int(result.stdout.strip())
    if value != 0: print("Synthetic fixture",operation,"rejected:",result.stderr.strip())
    return value

with tempfile.TemporaryDirectory(prefix='StudioSigningRegression-', dir='/tmp') as folder:
    root = Path(folder)
    first, second, adhoc = root/'first', root/'second', root/'adhoc'
    test_keychain = Path.home()/'Library/Keychains'/('MSSQLStudio-signing-test-'+str(uuid.uuid4())+'.keychain')
    identifier = 'local.mssqlstudio.app'
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
    subprocess.run(['security','create-keychain','-p','synthetic-isolated-test',str(test_keychain)],check=True)
    try:
        assert status(installed, service, 'save') == 0, 'Cannot create isolated Keychain fixture'
        created = True
        assert status(installed, service, 'partition') == 0, 'Audit fixture lacks enforced modern partitions'
        assert status(installed, service, 'read') == 0, 'Creating build cannot read its own item'
        shutil.copy2(second,installed)
        assert status(installed, service, 'read') != 0, 'Control: personal certificate alone unexpectedly bypassed CDHash partition'
        # A one-time user approval for the helper is simulated only on this disposable synthetic item.
        # Production never calls security, asks for a keychain password, or edits partition lists.
        helper_details = subprocess.run(['codesign','-d','--verbose=4',str(agent)],capture_output=True,text=True,check=True).stderr
        helper_cdhash = next(line.split('=',1)[1] for line in helper_details.splitlines() if line.startswith('CDHash='))
        subprocess.run(['security','set-generic-password-partition-list','-S','cdhash:'+helper_cdhash,
            '-a','11111111-2222-3333-4444-555555555555','-s',service,'-k','synthetic-isolated-test',str(test_keychain)],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
        assert status(installed, service, 'read', True) == 0, 'Frozen helper could not read migrated item'
        assert status(installed, service, 'save', True) == 0, 'Helper password update failed'
        moved = root/'moved-installation'
        shutil.copy2(first,moved)
        assert status(moved, service, 'read', True) == 0, 'Another build/path lost helper access'
        assert status(moved, service, 'save', True) == 0, 'Another build could not update via helper'
        assert status(installed, service, 'read', True) == 0, 'Updated credentials lost cross-build access'
        shutil.copy2(adhoc,installed)
        assert status(installed, service, 'read', True) != 0, 'Frozen helper accepted an ad-hoc parent'
        assert status(installed, service, 'save', True) != 0, 'Ad-hoc parent overwrote credentials'
        assert status(installed, service, 'renew', True) != 0, 'Ad-hoc parent renewed access'
        shutil.copy2(second, installed)
        assert status(installed, service, 'read', True) == 0, 'Rejected client modified the record'
        assert status(installed, service, 'delete', True) == 0, 'Helper could not delete synthetic record'
        created = False
        assert status(installed, service, 'save', True) == 0, 'Helper could not create fresh synthetic record'
        created = True
        assert status(moved, service, 'read', True) == 0, 'New helper-created record did not survive app upgrade'
    finally:
        # Delete only this UUID-named synthetic keychain, even when a control assertion fails.
        subprocess.run(['security','delete-keychain',str(test_keychain)],check=True)
print('PASS: modern partition enforced; changing app CDHash reproduces the old prompt; frozen signed helper preserves create/read/update/delete across distinct builds/paths; ad-hoc parents rejected; synthetic fixtures removed.')
