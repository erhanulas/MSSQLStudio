import AppKit
import SQLServerKit
import SwiftUI

@main @MainActor final class Application: NSObject, NSApplicationDelegate {
  static var updateTerminationApproved = false
  static var updateWatcher:Process?
  private let termination=ApplicationTermination()
  private var terminationPrompt:StudioCloseWindowController?
  private var window: NSWindow!
  private let studio = StudioState()
  private var workbench: WorkbenchController!
  static func main() {
    let arguments=ProcessInfo.processInfo.arguments
    // Release smoke uses the actual Foundation updater before UI/Keychain/restore.
    if arguments.dropFirst().first == "--check-update-feed" {
      guard arguments.count == 3,let address=Bundle.main.object(forInfoDictionaryKey:"MSSQLUpdateFeedURL") as? String,let feed=URL(string:address) else {exit(2)}
      Task {
        do {
          guard let release=try await ApplicationUpdate().check(feed:feed,currentVersion:"0"),release.version == arguments[2] else {
            FileHandle.standardError.write(Data("Public update feed version mismatch.\n".utf8));exit(1)
          }
          print("Foundation updater feed verified: "+release.version);exit(0)
        }catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
      }
      RunLoop.main.run();return
    }
    if arguments.dropFirst().first == "--reopen-after-update" {
      guard arguments.count == 4,let parent=Int32(arguments[3]),parent > 1,
        ApplicationUpdate.isNewer(arguments[2],than:"0") else {return}
      Task {
        if await ApplicationUpdate().waitForInstallation(expected:arguments[2],parentProcess:parent) {
          let configuration=NSWorkspace.OpenConfiguration()
          configuration.createsNewApplicationInstance=true
          _ = try? await NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:"/Applications/MSSQLStudio.app"),configuration:configuration)
        }
        exit(0)
      }
      RunLoop.main.run()
      return
    }
    let app = NSApplication.shared
    let delegate = Application()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    if let expected=UserDefaults.standard.string(forKey:"pendingInstallerVersion"),
       !ApplicationUpdate.consumeCompletedInstallation(in: .standard,
         runningVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         bundleURL: Bundle.main.bundleURL) {
      let alert=StudioAlert()
      alert.messageText="Güncelleme henüz tamamlanmadı"
      alert.informativeText="macOS Kurulum penceresinde kurulumu tamamlayıp Uygulamalar’daki MSSQL Studio’yu açın. Beklenen sürüm: \(expected)."
      alert.runModal()
    }
    StudioTheme.start()
    workbench = WorkbenchController(state: studio)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "MSSQL Studio"
    window.toolbarStyle = .unifiedCompact
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 1060, height: 680)
    window.contentViewController = workbench
    window.center()
    window.setFrameAutosaveName("MSSQLStudio.workbench")
    let toolbar = NSToolbar(identifier: "studio.toolbar")
    toolbar.delegate = workbench
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = true
    window.toolbar = toolbar
    createMenu()
    StudioTheme.decorate(workbench.view)
    window.backgroundColor = StudioTheme.chrome
    NotificationCenter.default.addObserver(
      self, selector: #selector(styleWindow(_:)), name: NSWindow.didBecomeKeyNotification,
      object: nil)
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    // UI checks must never read the user's saved credentials or contact their servers.
    if ProcessInfo.processInfo.arguments.contains("--ui-smoke") || Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" {
      let server = ConnectedServer(profile: ServerProfile(name: "UI Test"), password: "")
      server.online = false
      if Bundle.main.object(forInfoDictionaryKey:"StudioObjectSmoke") as? Bool == true {
        server.catalogFixture=ObjectManagementUIFixture.catalog
        server.databases=[CatalogItem(id:5,name:"DemoDB")]
        studio.servers.append(server)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioSchemaComparisonSmoke") as? Bool == true {
        studio.servers.append(SchemaComparisonUIFixture.server())
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioExplorerOrderSmoke") as? Bool == true {
        if !studio.servers.contains(where:{$0 === server}) {studio.servers.append(server)}
        for name in ["UI Test B","UI Test C"] {
          let other=ConnectedServer(profile:ServerProfile(name:name),password:"");other.online=false
          studio.servers.append(other)
        }
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioHistorySmoke") as? Bool == true {
        studio.history=(0..<45).map {index in
          var record=QueryRecord(server:server.profile.name,database:index % 3 == 0 ? "Reporting":"DemoDB",text:"SELECT CustomerID, Name FROM dbo.Customers;\n-- Synthetic history \(index+1)",serverID:server.id,rowCount:105,seconds:Double(index+1)/100,status:index % 9 == 0 ? "Kısmi":"Başarılı")
          record.time=Date().addingTimeInterval(-Double(index)*120);return record
        }
      }
      let document = QueryDocument(server: server, database: "master", title: "SQLQuery1.sql")
      document.sql = ""
      document.savedText = document.sql
      document.intelligenceCatalog = SQLIntelligence.Catalog(snapshot:SQLCatalogSnapshot(symbols:[CatalogSymbol(schema:"dbo",name:"Customers",columns:["CustomerID","Name","City"]),CatalogSymbol(schema:"dbo",name:"Orders",columns:["OrderID","CustomerID","Amount"]),CatalogSymbol(schema:"dbo",name:"ActiveCustomers",columns:["CustomerID","Name"],kind:"VIEW"),CatalogSymbol(schema:"dbo",name:"usp_GetCustomerDetails",columns:[],kind:"SQL_STORED_PROCEDURE"),CatalogSymbol(schema:"dbo",name:"ufn_GetCustomerName",columns:[],kind:"SQL_SCALAR_FUNCTION"),CatalogSymbol(schema:"dbo",name:"ufn_GetCustomerRows",columns:["CustomerID","Name"],kind:"SQL_INLINE_TABLE_VALUED_FUNCTION")]))
      document.catalogDatabase = "master"; document.catalogVerified = true
      if Bundle.main.object(forInfoDictionaryKey:"StudioOfflinePreviewSmoke") as? Bool == true {
        document.sql="SELECT * FROM dbo.Example;";document.savedText=document.sql
        document.offlinePreview=OfflineDefinitionPreview(server:server,database:"master",value:.init(id:1,schema:"dbo",name:"Example",type:"V",sql:"CREATE VIEW dbo.Example AS\nSELECT 1 AS ExampleID, N'Çevrimdışı önizleme' AS Name;"))
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioConnectionSmoke") as? Bool == true {
        if !studio.servers.contains(where:{$0 === server}) {studio.servers.append(server)}
        document.connectionFixture={_,_ in
          try await Task.sleep(for:.seconds(2))
          throw SQLFailure("Sentetik bağlantı hatası · Gerçek sunucuya erişilmedi.")
        }
      }
      if let sql=Bundle.main.object(forInfoDictionaryKey:"StudioRefreshSmokeSQL") as? String {
        document.sql=sql;document.savedText=sql;document.state = .ready
        var executionCount=0
        document.executionFixture = {sql,_ in
          executionCount+=1
          var output=Execution()
          output.results=[Rows(fields:[Field("RefreshRun",type:4)],values:[[String(executionCount)]])]
          output.results[0].source=ResultSourceMap(sql:sql).sources(for:output.results).first ?? nil
          return output
        }
        document.sessionProbeFixture = {_,_ in
          var output=Execution()
          output.results=[Rows(fields:[Field("TranCount"),Field("Database")],values:[["0","master"]])]
          return output
        }
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioGridSmoke") as? Bool == true {
        do {
          let spool = try ResultSpool()
          let compact=Bundle.main.object(forInfoDictionaryKey:"StudioGridSmokeCompact") as? Bool == true
          let rowCount=compact ? 6:2000, columnCount=compact ? 24:64
          var rows = Rows(fields:(0..<columnCount).map { Field($0 == 2 ? "Enabled" : "Column\($0)",type:$0 == 2 ? -7 : 12) })
          for base in stride(from:0,to:rowCount,by:256) {
            rows.values = try spool.append((base..<min(rowCount,base+256)).map { row in
              (0..<columnCount).map { column -> String? in column == 2 ? String(row%2) : column == 3 && row%3 == 0 ? nil : "\(row):\(column) · İstanbul" }
            })
          }
          document.results = [rows]; document.rowCount = rowCount
        } catch { document.messages = "Sentetik grid testi hazırlanamadı." }
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioMultiResultSmoke") as? Bool == true {
        document.sql = "SELECT TOP (100) object_id FROM sys.all_objects; SELECT NULL AS Missing; SELECT 2 AS Last;"
        document.savedText = document.sql
        var first = Rows(fields:[Field("object_id",type:4)],values:(1...10).map {[String($0)]})
        first.truncated = true
        document.results = [first, Rows(fields:[Field("Missing",type:4)],values:[[nil]]), Rows(fields:[Field("Last",type:4)],values:[["2"]])]
        let sources = ResultSourceMap(sql: document.sql).sources(for: document.results)
        for index in document.results.indices { document.results[index].source = sources[index] }
        document.rowCount = 12; document.partial = true
        document.messages = "Sentetik çoklu sonuç: ilk sonuç 10 satırla sınırlandı; sonraki iki sonuç korundu."
      }
      studio.documents.append(document)
      studio.active = document
      studio.changed?()
      if Bundle.main.object(forInfoDictionaryKey:"StudioAgentSmoke") as? Bool == true {
        let node=TreeNode("Demo Nightly",kind:.object(.jobs),server:server,item:CatalogItem(name:"Demo Nightly"))
        workbench.showAgentProperties(node)
        workbench.showAgentHistory(node)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioUpdateSmoke") as? Bool == true {
        let progress=UpdateProgressController();workbench.updateProgress=progress
        progress.beginDownload(version:"0.3.0")
        progress.updateTransfer(.init(receivedBytes:25_000_000,expectedBytes:100_000_000))
        progress.showWindow(nil)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioActivitySmoke") as? Bool == true {
        server.catalogFixture=ObjectManagementUIFixture.catalog
        if studio.servers.isEmpty {studio.servers.append(server)}
        workbench.showPerformanceMonitor(server)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioDatabaseFilesSmoke") as? Bool == true {
        server.catalogFixture=ObjectManagementUIFixture.catalog
        if studio.servers.isEmpty {studio.servers.append(server)}
        workbench.showDatabaseFiles(server)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioSettingsSmoke") as? Bool == true {
        workbench.showSettingsWindow()
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioDesignSmoke") as? Bool == true {
        workbench.present(StudioDesignGallery(),title:"MSSQL Studio · Design Fixture",width:1200,height:850,minWidth:1100,minHeight:760)
      }
      if Bundle.main.object(forInfoDictionaryKey:"StudioRefreshSmokeSQL") is String {document.execute()}
      return
    }
    studio.loadHistory()
    #if DEBUG
      if let password = ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] {
        Task {
          do {
            let server = try await studio.connect(
              ServerProfile(trustCertificate: true), password: password, save: false)
            studio.newQuery(
              server: server,
              text:
                "-- MSSQL Studio\nSELECT DB_NAME() AS [Database], @@SPID AS [Session], SYSDATETIME() AS [Server time];"
            )
          } catch { studio.showError(error.localizedDescription) }
        }
      } else {
        Task { [weak self] in
          guard let self else { return }; if !(await studio.restoreExplorers()) { workbench.showConnect() }
        }
      }
    #else
      Task { [weak self] in
          guard let self else { return }; if !(await studio.restoreExplorers()) { workbench.showConnect() }
        }
    #endif
  }
  @objc private func styleWindow(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    window.backgroundColor = StudioTheme.chrome
    if let content = window.contentView { StudioTheme.decorate(content) }
  }
  private func cancelUpdateTermination() {
    Self.updateTerminationApproved=false
    if let watcher=Self.updateWatcher,watcher.isRunning {watcher.terminate()}
    Self.updateWatcher=nil
  }
  private func completeTermination(_ sender:NSApplication) {
    termination.prepare(flush:{ [self] in await studio.flushHistory() },discardHistory:{
      let alert=StudioAlert();alert.messageText="Geçmiş kaydedilemedi"
      alert.informativeText="Son geçmiş ve kapatılan sekme kayıtları diske yazılamadı. Mevcut dosya korunur. Kaydetmeden çıkarsanız bu oturumdaki yeni geçmiş kayıtları kaybolabilir."
      alert.addButton(withTitle:"Çıkışı İptal Et");alert.addButton(withTitle:"Geçmişi Kaydetmeden Çık")
      return alert.runModal() == .alertSecondButtonReturn
    },mayTerminate:{ [self] in
      SchemaComparisonModel.activeApplications==0 && studio.canQuit()
    },terminate:{sender.terminate(nil)},cancelled:{ [self] in cancelUpdateTermination() })
  }
  func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
    guard SchemaComparisonModel.activeApplications==0 else {cancelUpdateTermination();NSSound.beep();return .terminateCancel}
    if termination.consumeApproval() {return .terminateNow}
    // Cancel this request while asynchronous preparation uses the regular loop;
    // the coordinator requests termination again only after persistence succeeds.
    if termination.preparing {return .terminateCancel}
    if Self.updateTerminationApproved {completeTermination(sender);return .terminateCancel}
    if let terminationPrompt {terminationPrompt.window?.makeKeyAndOrderFront(nil);return .terminateCancel}
    guard studio.canBeginBulkClose() else {return .terminateCancel}
    guard studio.needsBulkCloseConfirmation else {
      guard studio.canQuit() else {return .terminateCancel}
      completeTermination(sender);return .terminateCancel
    }
    let prompt=StudioCloseWindowController(title:"MSSQL Studio’yu kapat",count:studio.documents.count) {[weak self] choice in
      guard let self else {return true}
      if choice == .cancel {terminationPrompt=nil;return true}
      guard studio.canQuit(choice:choice) else {return false}
      terminationPrompt=nil;completeTermination(sender);return true
    }
    terminationPrompt=prompt
    Task { @MainActor in prompt.showWindow(nil);prompt.window?.makeKeyAndOrderFront(nil) }
    return .terminateCancel
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  private func createMenu() {
    let bar = NSMenu()
    NSApp.mainMenu = bar
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let submenu = StudioMenu(title: title)
      item.submenu = submenu
      bar.addItem(item)
      return submenu
    }
    func command(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      modifiers: NSEvent.ModifierFlags = .command
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = workbench
      menu.addItem(item)
    }
    let app = menu("MSSQL Studio")
    command(app, "MSSQL Studio Hakkında", #selector(WorkbenchController.about))
    app.addItem(.separator())
    command(app, "Ayarlar…", #selector(WorkbenchController.settings), ",")
    command(app, "Güncellemeleri Kontrol Et", #selector(WorkbenchController.installUpdate))
    app.addItem(.separator())
    app.addItem(
      withTitle: "MSSQL Studio'dan Çık", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    let file = menu("Dosya")
    command(file,"Bağlantıları Yönet…",#selector(WorkbenchController.showConnect))
    command(file, "Yeni Sorgu", #selector(WorkbenchController.newQuery), "n")
    command(file,"Explorer’ı Dışa Aktar…",#selector(WorkbenchController.exportExplorer))
    command(file,"Explorer’ı İçe Aktar…",#selector(WorkbenchController.importExplorer))
    command(file, "SQL Dosyası Aç…", #selector(WorkbenchController.openSQL), "o")
    command(file, "Kaydet", #selector(WorkbenchController.saveSQL), "s")
    command(
      file, "Farklı Kaydet…", #selector(WorkbenchController.saveAsSQL), "s",
      modifiers: [.command, .shift])
    file.addItem(.separator())
    command(file, "Pencereyi / Sekmeyi Kapat", #selector(WorkbenchController.closeFocusedWindow), "w")
    let reopen=GridShortcuts.binding(.reopenTab)
    command(file, "Kapatılan Sekmeyi Aç", #selector(WorkbenchController.reopenLastClosedTab), reopen.key,modifiers:reopen.flags)
    let edit = menu("Düzen")
    edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "İleri Al", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let find = NSMenuItem(
      title: "Bul…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
    find.tag = 1
    edit.addItem(find)
    let formatBinding = GridShortcuts.binding(.format)
    let formatItem = edit.addItem(withTitle: "SQL Formatla", action: #selector(SQLTextView.formatSQLText(_:)), keyEquivalent: formatBinding.key)
    formatItem.keyEquivalentModifierMask = formatBinding.flags
    edit.addItem(.separator())
    for (title,action,shortcut) in [("Yorum Yap / Kaldır",#selector(SQLTextView.toggleSQLComment(_:)),GridShortcuts.Action.comment),("Yorumu Kaldır",#selector(SQLTextView.uncommentSQL(_:)),.uncomment)] {
      let binding=GridShortcuts.binding(shortcut)
      let item=edit.addItem(withTitle:title,action:action,keyEquivalent:binding.key);item.keyEquivalentModifierMask=binding.flags
    }
    for (title,selector) in [("Nesne Tanımına Git",Selector(("goToDefinition:"))),("Explorer’da Git",Selector(("revealExplorerObject:"))),("Eşleşen Ayırıcıya Git",Selector(("goToMatchingPair:"))),("Parametre Bilgisi",Selector(("showParameterInfo:"))),("Bloğu Daralt / Aç",Selector(("toggleCodeOutline:"))),("Tüm Blokları Aç",Selector(("expandCodeOutline:")))] {
      edit.addItem(withTitle:title,action:selector,keyEquivalent:"")
    }
    edit.addItem(withTitle:"Tamamlamayı Göster",action:#selector(SQLTextView.showSQLCompletion(_:)),keyEquivalent:"")
    let query = menu("Sorgu")
    command(query, "Favori Sorgular…", #selector(WorkbenchController.showFavorites))
    command(query, "Favori Sorguları Yönet…", #selector(WorkbenchController.manageFavorites))
    command(query, "Favorilere Ekle…", #selector(WorkbenchController.addFavorite))
    query.addItem(.separator())
    let statement=NSMenuItem(title:"İfade / Blok Çalıştır…",action:#selector(SQLTextView.runSQLStatement(_:)),keyEquivalent:"\r");statement.target=nil;query.addItem(statement)
    command(query, "Çalıştır", #selector(WorkbenchController.execute))
    command(query, "İptal", #selector(WorkbenchController.cancel), ".")
    command(query, "Sorgu Oturumunu Yeniden Bağla", #selector(WorkbenchController.reconnectQuery))
    query.addItem(.separator())
    command(query, "Tahmini Execution Plan", #selector(WorkbenchController.estimatedPlan), "l")
    command(query, "Gerçek Planı Dahil Et", #selector(WorkbenchController.toggleActualPlan), "m")
    query.addItem(.separator())
    command(query, "BEGIN TRANSACTION", #selector(WorkbenchController.beginTransaction))
    command(query, "COMMIT", #selector(WorkbenchController.commitTransaction))
    command(query, "ROLLBACK", #selector(WorkbenchController.rollbackTransaction))
    let view = menu("Görünüm")
    command(
      view, "Object Explorer Göster / Gizle", #selector(WorkbenchController.toggleExplorer), "b",
      modifiers: [.command, .option])
    command(view, "Sonuçları Göster / Gizle", #selector(WorkbenchController.toggleResults), "r")
    let history=GridShortcuts.binding(.history)
    command(view, "History", #selector(WorkbenchController.showHistory), history.key,modifiers:history.flags)
    command(view, "Activity Monitor", #selector(WorkbenchController.activity))
    command(view, "AI Assistant", #selector(WorkbenchController.aiAssistant))
    command(view, "Extensions", #selector(WorkbenchController.extensionsPanel))
    command(view, "Sorguyu Ayrı Pencereye Taşı", #selector(WorkbenchController.detachQuery))
    command(
      view, "Tüm Sorguları Çalışma Alanına Yerleştir", #selector(WorkbenchController.redockQueries))
    view.addItem(.separator())
    command(view,"Sekmeyi Sabitle / Kaldır",#selector(WorkbenchController.pinActiveTab))
    command(view,"Soldaki Sekmeleri Kapat",#selector(WorkbenchController.closeLeftTabs))
    command(view,"Sağdaki Sekmeleri Kapat",#selector(WorkbenchController.closeRightTabs))
    command(view,"Diğer Sekmeleri Kapat",#selector(WorkbenchController.closeOtherTabs))
    command(view,"Tüm Sekmeleri Kapat",#selector(WorkbenchController.closeAllTabs))
    let windowMenu = menu("Pencere")
    NSApp.windowsMenu = windowMenu
    windowMenu.addItem(
      withTitle: "Simge Durumuna Küçült", action: #selector(NSWindow.miniaturize(_:)),
      keyEquivalent: "m")
    workbench.refreshShortcuts()
  }
}
