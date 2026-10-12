import AppKit
import SQLServerKit
import SwiftUI

@main @MainActor final class Application: NSObject, NSApplicationDelegate {
  static var updateTerminationApproved = false
  private var window: NSWindow!
  private let studio = StudioState()
  private var workbench: WorkbenchController!
  static func main() {
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
      let alert=NSAlert()
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
      let document = QueryDocument(server: server, database: "master", title: "SQLQuery1.sql")
      document.sql = ""
      document.savedText = document.sql
      document.intelligenceCatalog = SQLIntelligence.Catalog(snapshot:SQLCatalogSnapshot(symbols:[CatalogSymbol(schema:"dbo",name:"Customers",columns:["CustomerID","Name","City"]),CatalogSymbol(schema:"dbo",name:"Orders",columns:["OrderID","CustomerID","Amount"]),CatalogSymbol(schema:"dbo",name:"usp_GetCustomerDetails",columns:[],kind:"SQL_STORED_PROCEDURE")]))
      document.catalogDatabase = "master"; document.catalogVerified = true
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
      if Bundle.main.object(forInfoDictionaryKey:"StudioActivitySmoke") as? Bool == true {
        server.catalogFixture=ObjectManagementUIFixture.catalog
        if studio.servers.isEmpty {studio.servers.append(server)}
        workbench.showPerformanceMonitor(server)
      }
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
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Self.updateTerminationApproved || studio.canQuit() ? .terminateNow : .terminateCancel
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  private func createMenu() {
    let bar = NSMenu()
    NSApp.mainMenu = bar
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: title)
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
    command(file, "Yeni Sorgu", #selector(WorkbenchController.newQuery), "n")
    command(file, "SQL Dosyası Aç…", #selector(WorkbenchController.openSQL), "o")
    command(file, "Kaydet", #selector(WorkbenchController.saveSQL), "s")
    command(
      file, "Farklı Kaydet…", #selector(WorkbenchController.saveAsSQL), "s",
      modifiers: [.command, .shift])
    file.addItem(.separator())
    command(file, "Sekmeyi Kapat", #selector(WorkbenchController.closeTab), "w")
    let edit = menu("Düzen")
    edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
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
    command(
      edit, "SQL Formatla", #selector(WorkbenchController.formatSQL), "f",
      modifiers: [.command, .shift])
    let query = menu("Sorgu")
    command(query, "Favori Sorgular…", #selector(WorkbenchController.showFavorites))
    command(query, "Favorilere Ekle…", #selector(WorkbenchController.addFavorite))
    query.addItem(.separator())
    command(query, "Çalıştır", #selector(WorkbenchController.execute), "\r")
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
    command(view, "Query History", #selector(WorkbenchController.showHistory))
    command(view, "Activity Monitor", #selector(WorkbenchController.activity))
    command(view, "AI Assistant", #selector(WorkbenchController.aiAssistant))
    command(view, "Extensions", #selector(WorkbenchController.extensionsPanel))
    command(view, "Sorguyu Ayrı Pencereye Taşı", #selector(WorkbenchController.detachQuery))
    command(
      view, "Tüm Sorguları Çalışma Alanına Yerleştir", #selector(WorkbenchController.redockQueries))
    let windowMenu = menu("Pencere")
    NSApp.windowsMenu = windowMenu
    windowMenu.addItem(
      withTitle: "Simge Durumuna Küçült", action: #selector(NSWindow.miniaturize(_:)),
      keyEquivalent: "m")
    workbench.refreshShortcuts()
  }
}
