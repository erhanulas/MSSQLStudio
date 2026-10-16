import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func openMonitoring() {
    if let node = contextNode, case .folder(let folder) = node.kind {
      if folder == .activity {showPerformanceMonitor(node.server);return}
      if folder == .files {showDatabaseFiles(node.server);return}
      state.newQuery(
        server: node.server, database: node.database, text: Catalog.monitoring(folder),
        title: folder.rawValue, run: true)
    }
  }
  @objc func activity() {if let server=selectedServer {showPerformanceMonitor(server)}}
  func showPerformanceMonitor(_ server:ConnectedServer) {
    if let window=auxiliaryWindows.compactMap(\.window).first(where:{$0.identifier?.rawValue=="activity|\(server.id)"}) {
      window.makeKeyAndOrderFront(nil);return
    }
    activityLauncher.open(server)
  }
  func presentPerformanceMonitor(_ server:ConnectedServer) {
    let window=present(ActivityMonitorPanel(server:server,openDBATool:{[weak self] tool in
      guard let self else {return}
      state.newQuery(server:server,database:"master",text:tool.sql,title:"DBA · "+tool.title)
      view.window?.makeKeyAndOrderFront(nil)
    },openTable:{[weak self] in self?.createActivityTable(server)}),
      title:"Activity Monitor · \(server.profile.name)",width:1220,height:840,minWidth:920,minHeight:700,identity:"activity|\(server.id)")
    window.minSize=window.frameRect(forContentRect:NSRect(x:0,y:0,width:920,height:700)).size
  }
  func showDatabaseFiles(_ server:ConnectedServer,database:String="") {
    let window=present(DatabaseFilesPanel(server:server,database:database,openQuery:{[weak self] in
      guard let self else {return}
      self.state.newQuery(server:server,database:"master",text:Catalog.monitoring(.files),title:"Database Files · Envanter")
      self.view.window?.makeKeyAndOrderFront(nil)
    }),title:"Database Files · \(server.profile.name)",width:1120,height:760,minWidth:920,minHeight:620,identity:"files|\(server.id)")
    window.minSize=window.frameRect(forContentRect:NSRect(x:0,y:0,width:920,height:620)).size
  }
  @objc func openActivityTable() {if let server=contextNode?.server ?? selectedServer {createActivityTable(server)}}
  private func createActivityTable(_ server:ConnectedServer) {
    state.newQuery(server:server,database:"master",text:Catalog.monitoring(.activity),title:"Activity Monitor · İstekler",run:true,refreshSeconds:10)
    view.window?.makeKeyAndOrderFront(nil)
  }
}
