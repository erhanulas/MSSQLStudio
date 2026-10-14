import AppKit
import SQLServerKit
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func exportExplorer() {
    guard let window=view.window,window.attachedSheet==nil else {return}
    let archive=ExplorerArchive(profiles:state.servers.map(\.profile),organization:state.explorerOrganization)
    let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="MSSQLStudio-Explorer.json"
    panel.message="Bağlantılar, sıralama, klasörler ve renkler aktarılır. Parolalar, SQL ve indeksler dosyaya eklenmez."
    panel.beginSheetModal(for:window) { [weak self] response in
      guard response == .OK,let url=panel.url else {return}
      Task { @MainActor [weak self] in
        do {try await Task.detached {
          let data=try archive.encoded();try data.write(to:url,options:.atomic)
          try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        }.value} catch {self?.state.showError(error.localizedDescription)}
      }
    }
  }
  @objc func importExplorer() {
    guard let window=view.window,window.attachedSheet==nil,!explorerTransferBusy else {return}
    let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
    panel.message="Mevcut bağlantılar korunur; yeni profiller çevrimdışı eklenir. Parolayı bağlantı ayarlarından girin."
    panel.beginSheetModal(for:window) { [weak self] response in
      guard response == .OK,let url=panel.url else {return}
      Task { @MainActor [weak self] in
        guard let self else {return};explorerTransferBusy=true;defer {explorerTransferBusy=false}
        do {
          let archive=try await Task.detached {
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=2_000_000 else {throw SQLFailure("Explorer aktarımı 2 MB sınırını aşıyor.")}
            return try ExplorerArchive.decode(Data(contentsOf:url))
          }.value
          let count=try await state.importExplorer(archive)
          status.stringValue="Explorer aktarımı tamamlandı · \(count) yeni bağlantı · Parolaları bağlantı ayarlarından girin."
        } catch {state.showError(error.localizedDescription)}
      }
    }
  }
}

extension StudioState {
  @discardableResult func importExplorer(_ archive:ExplorerArchive,
    saveProfile:@escaping @Sendable (ServerProfile) async throws->Void = {profile in try await Task.detached {try ServerVault().save(profile,password:"")}.value}
  ) async throws->Int {
    let plan=try archive.merged(existing:servers.map(\.profile),organization:explorerOrganization)
    var added:[ConnectedServer]=[]
    var failure:(any Error)?
    for profile in plan.added {
      do {
        try await saveProfile(profile)
        let server=ConnectedServer(profile:profile,password:"");server.online=false;server.remembered=true
        server.databases=(profile.visibleDatabases ?? [profile.database]).map {CatalogItem(id:["master":1,"tempdb":2,"model":3,"msdb":4][$0] ?? 10,name:$0)}
        servers.append(server);added.append(server);rememberExplorer(server.id,selected:true)
      } catch {failure=error;break}
    }
    if !added.isEmpty || plan.added.isEmpty {
      var org=plan.organization
      for profile in plan.added where !added.contains(where:{$0.id==profile.id}) {try org.assign(profile.id,to:nil)}
      try changeExplorerOrganization {$0=org}
      explorerOrderDefaults.set(servers.map {$0.id.uuidString},forKey:"explorerServerOrder");changed?()
    }
    if let failure {throw SQLFailure("\(added.count) bağlantı eklendi; kalan aktarım tamamlanamadı: "+failure.localizedDescription)}
    return added.count
  }
}
