import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct RoutineDefinitionParameterTests {
  private var catalog:SQLIntelligence.Catalog {
    SQLIntelligence.Catalog(snapshot:.init(symbols:[
      CatalogSymbol(schema:"dbo",name:"Fn",columns:[],kind:"SQL_SCALAR_FUNCTION"),
      CatalogSymbol(schema:"dbo",name:"Sample",columns:[],kind:"SQL_STORED_PROCEDURE")]))
  }
  private func setSource(_ marked:String,document:QueryDocument,controller:EditorController) {
    let caret=(marked as NSString).range(of:"|").location
    document.sql=marked.replacingOccurrences(of:"|",with:"")
    controller.setText();controller.editor.setSelectedRange(NSRange(location:caret,length:0))
    controller.scheduleParameters(manual:true)
  }
  @Test func definitionHeadersFetchNothingAndReturningFromBodyClosesHelp() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var requests=0
    server.asyncCatalogFixture={sql in
      requests+=1
      var execution=Execution()
      execution.results=[Rows(values:sql.contains("SELECT object_id") ? [["42"]]:[["1","@First","int","0","0"],["2","@Second","int","0","0"]])]
      return execution
    }
    let document=QueryDocument(server:server,database:"master",title:"Definition parameters")
    document.intelligenceCatalog=catalog;document.catalogDatabase="master"
    let controller=EditorController(document:document)
    for marked in [
      "ALTER FUNCTION dbo.Fn(@First int, |@Second int) RETURNS int AS BEGIN RETURN @First END",
      "CREATE OR ALTER FUNCTION [dbo].[Fn](|@First int) RETURNS TABLE AS RETURN SELECT @First AS Value",
      "CREATE FUNCTION dbo.Fn(@First int) RETURNS @Result TABLE (Value int, |Other int) AS BEGIN RETURN END",
      "ALTER PROCEDURE dbo.Sample @First AS int, |@Second int AS SELECT @First"
    ] {
      setSource(marked,document:document,controller:controller)
      try await Task.sleep(for:.milliseconds(40))
      #expect(requests == 0 && controller.parameterCall == nil && !controller.parameterShown)
    }
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {controller.dismissParameterHelp();window.close()}
    window.orderFront(nil);controller.surface.layoutSubtreeIfNeeded();window.makeFirstResponder(controller.editor)
    let source="ALTER FUNCTION dbo.Fn(@First int, @Second int) RETURNS int AS BEGIN RETURN dbo.Fn(@First, |@Second); END"
    setSource(source,document:document,controller:controller)
    for _ in 0..<100 where controller.parameterValues.isEmpty {try await Task.sleep(for:.milliseconds(10))}
    #expect(requests == 2 && controller.parameterValues.map(\.name) == ["@First","@Second"])
    #expect(controller.parameterCall?.activeIndex(in:controller.parameterValues) == 1)
    #expect(controller.parameterShown)
    setSource(source.replacingOccurrences(of:"|",with:"").replacingOccurrences(of:"@First int",with:"|@First int"),document:document,controller:controller)
    for _ in 0..<100 where controller.parameterCall != nil {try await Task.sleep(for:.milliseconds(10))}
    #expect(requests == 2 && controller.parameterCall == nil && controller.parameterValues.isEmpty && !controller.parameterShown)
  }
  @Test func delayedCallMetadataCannotReopenHelpInDefinitionSignature() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var requests=0,started=false
    server.asyncCatalogFixture={sql in
      requests+=1;started=true
      // A provider may finish despite cancellation. The editor must discard it.
      try? await Task.sleep(for:.milliseconds(100))
      var execution=Execution()
      execution.results=[Rows(values:sql.contains("SELECT object_id") ? [["42"]]:[["1","@First","int","0","0"]])]
      return execution
    }
    let document=QueryDocument(server:server,database:"master",title:"Stale definition help")
    document.intelligenceCatalog=catalog;document.catalogDatabase="master"
    let controller=EditorController(document:document)
    setSource("SELECT dbo.Fn(|1)",document:document,controller:controller)
    for _ in 0..<100 where !started {try await Task.sleep(for:.milliseconds(10))}
    #expect(started && requests == 1)
    setSource("ALTER FUNCTION dbo.Fn(@First int, |@Second int) RETURNS int AS BEGIN RETURN @First END",document:document,controller:controller)
    try await Task.sleep(for:.milliseconds(150))
    #expect(requests == 1 && controller.parameterCall == nil && controller.parameterValues.isEmpty && !controller.parameterShown)
  }
}
