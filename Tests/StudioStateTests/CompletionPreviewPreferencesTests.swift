import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CompletionPreviewPreferencesTests {
  @Test func completionReadsPreferencesAndDisplaysMatchingNativeLabels() async throws {
    _=NSApplication.shared
    let defaults=UserDefaults.standard
    let keys=[SQLEditorPreferences.completionSchemaKey,SQLEditorPreferences.completionBracketsKey]
    let old=keys.map {defaults.object(forKey:$0)}
    defer {for (key,value) in zip(keys,old) {defaults.set(value,forKey:key)}}
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Preview")
    doc.server.online=false;doc.sql="SELECT * FROM Prod";doc.catalogDatabase="master";doc.catalogVerified=true
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Products",columns:["ID"])]))
    let host=EditorController(document:doc),window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host.surface;window.orderFront(nil)
    host.editor.setSelectedRange(NSRange(location:doc.sql.utf16.count,length:0))
    let completion=EditorCompletionController(document:doc,editor:host.editor)
    defer {completion.cancel();window.close()}
    for (schema,brackets,expected) in [(true,true,"[dbo].[Products]"),(true,false,"dbo.Products"),(false,true,"[Products]"),(false,false,"Products")] {
      defaults.set(schema,forKey:keys[0]);defaults.set(brackets,forKey:keys[1])
      completion.scheduleIntelligence(manual:true,allowPopup:false)
      for _ in 0..<100 where completion.currentAnalysis?.suggestions.first?.label != expected {try await Task.sleep(for:.milliseconds(10))}
      let suggestion=try #require(completion.currentAnalysis?.suggestions.first)
      #expect(suggestion.label==expected)
      let list=SQLSuggestionList();list.update([suggestion])
      let cell=try #require(list.tableView(list.table,viewFor:list.table.tableColumns.first,row:0))
      #expect(cell.accessibilityLabel()?.hasPrefix(expected+" · ")==true)
      #expect(doc.sql=="SELECT * FROM Prod" && doc.lastExecutedSQL==nil)
    }
  }
}
