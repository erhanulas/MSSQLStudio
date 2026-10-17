import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ExecutionMessagesTests {
  @Test func hiddenResultsOpenOnlyOnErrorAndMessageClickSelectsExecutedSourceLine() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(visibleDatabases:[]),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Error fixture")
    doc.state = .ready;doc.sql="SELECT 0;\nSELECT 1;\nSELEC broken;\nSELECT 3;"
    let controller=QueryController(document:doc)
    _=controller.view;controller.toggleResults()
    #expect(controller.resultsHidden)
    doc.executionFixture={_,_ in Execution()}
    doc.execute()
    for _ in 0..<200 where doc.busy {try await Task.sleep(for:.milliseconds(5))}
    controller.update()
    #expect(!doc.executionFailed && controller.resultsHidden)
    let source=doc.sql as NSString,range=source.range(of:"SELECT 1;\nSELEC broken;")
    doc.selectedRange=range
    doc.executionFixture={_,_ in throw SQLFailure("Batch başlangıç satırı 1: SQL Server işlemi tamamlanamadı.",diagnostics:[.init(state:"42000",code:102,message:"Incorrect syntax",line:2)],batchLine:1)}
    doc.execute()
    for _ in 0..<200 where doc.busy {try await Task.sleep(for:.milliseconds(5))}
    controller.update()
    #expect(doc.executionFailed && !controller.resultsHidden)
    let target=try #require(doc.errorLocations.last)
    #expect(source.substring(with:target.source)=="SELEC broken;" && target.source.location==source.range(of:"SELEC broken;").location)
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let messages=try #require(descendants(controller.view).compactMap {$0 as? ResultMessagesView}.first)
    #expect(messages.textStorage?.attribute(.link,at:target.message.location,effectiveRange:nil) != nil)
    #expect(messages.textStorage?.attribute(.underlineStyle,at:target.message.location,effectiveRange:nil) as? Int == 0)
    #expect(messages.linkTextAttributes?[.underlineStyle] as? Int == 0)
    #expect(messages.linkTextAttributes?[.foregroundColor] as? NSColor == StudioTheme.danger)
    #expect(messages.textView(messages,clickedOnLink:URL(string:"studio-error://1")!,at:target.message.location))
    #expect(doc.selectedRange==target.source)
    controller.toggleResults();controller.update()
    #expect(controller.resultsHidden) // Re-rendering the same error never forces it open again.
    doc.sql="SELECT 99;";controller.update()
    #expect(messages.textStorage?.attribute(.link,at:target.message.location,effectiveRange:nil)==nil)
  }
  @Test func partialExecutionFailureIsNotReportedAsSuccess() async throws {
    let server=ConnectedServer(profile:.init(visibleDatabases:[]),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Partial fixture");doc.state = .ready;doc.sql="SELECT 1;\nGO\ninvalid;"
    let failure=SQLFailure("Batch başlangıç satırı 3: bad syntax",batchLine:3)
    doc.executionFixture={_,_ in
      var output=Execution();output.results=[Rows(fields:[Field("n")],values:[["1"]])]
      output.partial=true;output.stoppedEarly=true;output.failure=failure;output.messages=[failure.localizedDescription];return output
    }
    doc.execute()
    for _ in 0..<200 where doc.busy {try await Task.sleep(for:.milliseconds(5))}
    #expect(doc.executionFailed && !doc.lastExecutionSucceeded && doc.results.count==1)
    #expect(doc.errorLocations.first?.source.location==("SELECT 1;\nGO\n" as NSString).length)
  }
}
