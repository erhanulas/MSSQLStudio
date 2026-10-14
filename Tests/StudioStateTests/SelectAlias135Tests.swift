import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SelectAlias135Tests {
  @Test func editorMarksActualMissingColumnsButPreservesAssignmentAndAsLabels() async throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Alias validation")
    doc.server.online=false;doc.catalogDatabase="master";doc.catalogVerified=true
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Stock",columns:["Code","Amount"])]))
    doc.sql="SELECT HUCREKODU='1100', BAKIYE=SUM(T.Amount), T.Code AS DisplayCode, T.Missing FROM dbo.Stock T; "
    let controller=EditorController(document:doc)
    controller.editor.setSelectedRange(NSRange(location:doc.sql.utf16.count,length:0))
    controller.scheduleIntelligence(allowPopup:false)
    for _ in 0..<100 where controller.diagnostics.isEmpty {try await Task.sleep(for:.milliseconds(20))}
    #expect(controller.diagnostics.map {(doc.sql as NSString).substring(with:$0.range)}==["Missing"])
    #expect(controller.editor.string==doc.sql && doc.lastExecutedSQL==nil)
  }
}
