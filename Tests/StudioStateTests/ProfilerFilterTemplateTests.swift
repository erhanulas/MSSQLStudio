import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

private actor TemplateSQLProbe {
  var calls=0
  func execute(_ sql:String)->Execution {calls+=1;return Execution()}
  func count()->Int {calls}
}
@MainActor @Suite(.serialized) struct ProfilerFilterTemplateTests {
  @Test func globalTemplatesApplyToAnotherServerWithoutStartingOrClearing() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/ProfilerTemplateUI-"+UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
    let templates=ProfilerFilterTemplatesModel(store:.init(url:folder.appendingPathComponent("templates.json")))
    await templates.load()
    let a=ConnectedServer(profile:.init(name:"A"),password:""),b=ConnectedServer(profile:.init(name:"B"),password:"")
    let probe=TemplateSQLProbe()
    let first=ProfilerModel(server:a,executor:{await probe.execute($0)},disconnect:{},templates:templates)
    let second=ProfilerModel(server:b,executor:{await probe.execute($0)},disconnect:{},templates:templates)
    first.configuration.application="My App";first.configuration.sqlLike="%STOK%"
    first.displayFilter.sqlSearch="SELECT";first.displayFilter.rules=[.init(column:.clientPID,value:"123")]
    let value=try ProfilerFilterTemplate(name:"Genel",configuration:first.configuration,displayFilter:first.displayFilter)
    #expect(await templates.save(value))
    #expect(first.templates === second.templates && second.templates.templates==[value])
    try second.applyTemplate(value)
    #expect(second.configuration==first.configuration && second.displayFilter==first.displayFilter)
    #expect(await probe.count()==0 && !second.hasSession && second.events.isEmpty)
    let name=SQLProfiler.sessionName(UUID())
    await second.start(name:name,confirmedSQL:try second.preview(name:name))
    let before=second.configuration
    #expect(throws:(any Error).self) {try second.applyTemplate(value)}
    #expect(second.hasSession && second.configuration==before)
    #expect(await second.stop())
    await templates.remove(value.id)
    #expect(first.templates.templates.isEmpty && second.templates.templates.isEmpty)
    #expect(second.configuration==before)
  }
  @Test func controlsFitCompactSidebarInBothThemes() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/ProfilerTemplateUI-"+UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
    let templates=ProfilerFilterTemplatesModel(store:.init(url:folder.appendingPathComponent("templates.json")))
    await templates.load()
    #expect(await templates.save(try .init(name:"İstemci filtresi",configuration:.init(),displayFilter:.init())))
    let server=ConnectedServer(profile:.init(),password:"")
    let model=ProfilerModel(server:server,executor:{_ in Execution()},disconnect:{},templates:templates)
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let host=NSHostingController(rootView:ProfilerFilterTemplateControls(model:model))
      host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:260,height:110));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      host.view.layoutSubtreeIfNeeded()
      func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
      let picker=try #require(children(host.view).compactMap {$0 as? StudioSelectionControl}.first)
      #expect(picker.itemTitles==["Filtre şablonu seç","İstemci filtresi"])
      #expect(picker.frame.width>80 && picker.isEnabled)
      let bitmap=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
      host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-template-"+theme+".png"))
      window.close()
    }
  }
}
