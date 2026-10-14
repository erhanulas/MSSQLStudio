import AppKit
import CoreText
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  func showSettingsWindow() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "studio.settings" && $0.isVisible }) {
      window.makeKeyAndOrderFront(nil); return
    }
    let window = present(SettingsPanel(state: state), title: "MSSQL Studio Ayarları", width: 920, height: 700, minWidth: 780, minHeight: 600, identity: "studio.settings")
    window.minSize = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 780, height: 600)).size
  }
  func showHistoryWindow() {
    let document=favoriteContextDocument
    state.loadHistory()
    present(
      HistoryPanel(
        state: state,
        open: { [weak self] record in
          guard let self, let server = state.historyServer(record) else { return }
          state.newQuery(
            server: server, database: record.database, text: record.text,
            title: "Timeline · \(record.time.formatted())")
        },insert:{[weak self,weak document] record in guard let self else {return};try insertSavedSQL(record.text,into:document)}), title: "Timeline — Sorgu Geçmişi", width: 1120, height: 760, minWidth: 1000, minHeight: 650, identity: "studio.timeline")
  }
  func showAIWindow() {
    present(
      AssistantPanel(
        sql: state.active?.sql ?? "",
        open: { [weak self] sql in
          guard let self, let server = selectedServer else { return }
          state.newQuery(server: server, database: selectedDatabase, text: sql, title: "AI Önerisi")
        }), title: "SQL Assistant", width: 820, height: 720)
  }
  func showExtensionsWindow() {
    present(
      TemplatesPanel(open: { [weak self] template in
        guard let self, let server = selectedServer else { return }
        state.newQuery(
          server: server, database: selectedDatabase, text: template.sql, title: template.name)
      }), title: "SQL Şablon Eklentileri", width: 740, height: 580)
  }
  func showIndexWindow(node: TreeNode?) {
    guard let node, let item = node.item else { return }
    present(
      IndexPanel(
        table: item.qualified,
        load: {
          Catalog.rows(
            try await node.server.catalog(
              Catalog.children(.columns, object: item.id), database: node.database))
        },
        open: { [weak self] sql in
          self?.state.newQuery(
            server: node.server, database: node.database, text: sql,
            title: "Create Index · \(item.name)")
        }), title: "Index Designer — \(item.qualified)", width: 760, height: 620)
  }
  func showJobWindow(node: TreeNode?) {
    guard let node else { return }
    present(
      JobPanel(
        databases: node.server.databases.map(\.name),
        open: { [weak self] sql in
          self?.state.newQuery(
            server: node.server, database: "msdb", text: sql, title: "New SQL Agent Job")
        }), title: "SQL Server Agent — New Job", width: 760, height: 620)
  }
}
