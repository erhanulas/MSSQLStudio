import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ProfilerMessagePresentationTests {
  private func event()->SQLProfiler.Event {
    let json=#"{"id":0,"timestamp":"2026-10-16T12:00:00Z","kind":"error_reported","database":"Demo","application":"Client","host":"Mac","login":"reader","session":"71","clientPID":"123","cpu":"","reads":"","writes":"","sql":"","message":"Changed language setting to us_english.","errorNumber":5703,"severity":10,"errorState":1}"#
    return try! JSONDecoder().decode(SQLProfiler.Event.self,from:Data(json.utf8))
  }
  @Test func gridColorsRespectNativeSelectedTextAndExposeFilterableMetadata() throws {
    let source=event()
    var error=source;error.severity=16;error.errorNumber=208
    var warning=source;warning.errorNumber=8153
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    let model=ProfilerModel(server:server,executor:{_ in Execution()},disconnect:{})
    let owner=ProfilerEventGrid.Coordinator(model:model,selection:.constant([]))
    owner.events=[source,warning,error]
    let table=NSTableView(),column=NSTableColumn(identifier:.init("messageLevel"))
    table.addTableColumn(column)
    for row in 0..<3 {
      let field=try #require(owner.tableView(table,viewFor:column,row:row) as? NSTextField)
      #expect(field.stringValue==["Bilgi","Uyarı","Hata"][row])
      let color=ProfilerMessagePresentation.color(owner.events[row].messageLevel)
      #expect(field.textColor==color)
      field.cell?.backgroundStyle = .emphasized
      #expect(field.textColor==NSColor.selectedControlTextColor)
      field.cell?.backgroundStyle = .normal
      #expect(field.textColor==color)
    }
  }
  @Test func neutralInformationDoesNotUseWarningColorAndDetailsArePreserved() throws {
    let event=event()
    #expect(ProfilerMessagePresentation.tone(event.messageLevel) == .info)
    #expect(ProfilerMessagePresentation.tone(.warning) == .warning)
    #expect(ProfilerMessagePresentation.tone(.error) == .error)
    #expect(ProfilerMessagePresentation.tone(.unknown) == .info)
    let details=ProfilerMessagePresentation.details(event)
    #expect(details.contains("Bilgi") && details.contains("5703") && details.contains("Önem derecesi 10") && details.contains(event.message))
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let host=NSHostingController(rootView:StudioFeedback(message:details,tone:ProfilerMessagePresentation.tone(event.messageLevel)).padding(12).background(Color(nsColor:StudioTheme.panel)))
      host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:640,height:100));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      host.view.layoutSubtreeIfNeeded()
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-message-"+theme+".png"))
      window.close()
    }
  }
}
