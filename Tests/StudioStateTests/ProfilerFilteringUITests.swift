import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

private actor ProfilerFilteringProbe {
  private var calls:[String]=[]
  func statements()->[String] {calls}
  func execute(_ sql:String) throws -> Execution {
    calls.append(sql)
    guard sql.contains("SELECT t.target_data") else {return Execution()}
    let rows=[("123","HOST-A","SELECT foo"),("123","HOST-A","UPDATE bar"),("123","HOST-B","SELECT foo"),("71","HOST-A","SELECT foo")]
    let events=rows.enumerated().map {index,value in
      "<event name=\"rpc_completed\" timestamp=\"2026-10-16T12:00:00Z\"><data name=\"statement\"><value>\(value.2)</value></data><action name=\"event_sequence\"><value>\(index)</value></action><action name=\"client_pid\"><value>\(value.0)</value></action><action name=\"client_hostname\"><value>\(value.1)</value></action><action name=\"session_id\"><value>71</value></action></event>"
    }.joined()
    var result=Execution();result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[["<RingBufferTarget totalEventsProcessed=\"4\" droppedCount=\"0\">\(events)</RingBufferTarget>","0"]])];return result
  }
}
@MainActor @Suite(.serialized) struct ProfilerFilteringUITests {
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<200 where !condition() {try await Task.sleep(for:.milliseconds(3))}
    #expect(condition())
  }
  private func fixture() async throws -> (ProfilerModel,ProfilerFilteringProbe) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let probe=ProfilerFilteringProbe(),model=ProfilerModel(server:server,executor:{try await probe.execute($0)},disconnect:{},interval:.milliseconds(20))
    let name=SQLProfiler.sessionName(UUID());await model.start(name:name,confirmedSQL:try model.preview(name:name))
    try await wait {model.events.count==4 && model.visibleEvents.count==4 && !model.filtering}
    return (model,probe)
  }
  @Test func correlatedPreviewUsesHiddenStartAndPreservesRawExport() async throws {
    let xmlEvents=["rpc_starting","error_reported","rpc_completed"].enumerated().map {index,kind in
      """
      <event name="\(kind)" timestamp="2026-10-16T12:00:00Z">
      <data name="statement"><value>\(index==0 ? "EXEC dbo.Fail;":"")</value></data>
      <data name="message"><value>Failure message</value></data>
      <data name="severity"><value>16</value></data>
      <action name="event_sequence"><value>\(index)</value></action>
      <action name="session_id"><value>71</value></action>
      <action name="client_connection_id"><value>11111111-1111-1111-1111-111111111111</value></action>
      <action name="attach_activity_id"><value>22222222-2222-2222-2222-222222222222-\(index)</value></action>
      </event>
      """
    }.joined()
    var execution=Execution()
    execution.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[["<RingBufferTarget totalEventsProcessed=\"3\">"+xmlEvents+"</RingBufferTarget>","0"]])]
    let snapshot=execution
    let server=ConnectedServer(profile:.init(),password:"")
    let model=ProfilerModel(server:server,executor:{$0.contains("SELECT t.target_data") ? snapshot:Execution()},disconnect:{},interval:.milliseconds(20))
    let name=SQLProfiler.sessionName(UUID())
    await model.start(name:name,confirmedSQL:try model.preview(name:name))
    try await wait {model.visibleEvents.count==2 && !model.filtering}
    let error=try #require(model.visibleEvents.first {$0.kind=="error_reported"})
    let completed=try #require(model.visibleEvents.first {$0.kind=="rpc_completed"})
    #expect(model.relations[completed.id]?.messages.first?.message=="Failure message")
    let preview=ProfilerPreviewPresentation()
    let resolved=model.previewEvents([error]);preview.request(resolved)
    #expect(preview.sql=="EXEC dbo.Fail;" && ProfilerExport.sql(resolved)==preview.sql)
    #expect(error.sql.isEmpty && model.events.count==3)
    let raw=try ProfilerExport.data(model.events,format:.trace)
    #expect(String(decoding:raw,as:UTF8.self).contains("rpc_starting"))
    #expect(!String(decoding:try ProfilerExport.data(model.events,format:.sql),as:UTF8.self).contains("EXEC dbo.Fail;"))
    #expect(await model.stop())
  }
  @Test func liveGridFiltersLatestSearchAndClientSelectionWithoutAdditionalDDLOrChangingCapturedRows() async throws {
    let (model,probe)=try await fixture()
    #expect(model.clients.count==3 && model.clients[0].id.pid=="123" && model.clients[0].count==2)
    #expect(Set(model.choices.values(for:.clientPID))==Set(["","123","71"]))
    #expect(Set(model.choices.values(for:.host))==Set(["","HOST-A","HOST-B"]))
    model.focusClient(model.clients[0])
    model.displayFilter.sqlSearch="stale";model.displayFilter.sqlSearch="bar";model.displayFilter.sqlSearch="foo"
    try await wait {!model.filtering && model.visibleEvents.map(\.id)==[0]}
    #expect(model.events.count==4 && model.clients.count==1 && model.filterError.isEmpty)
    model.displayFilter.rules=[.init(column:.clientPID,comparison:.equals,value:"not a number")]
    try await wait {!model.filtering && !model.filterError.isEmpty}
    #expect(model.visibleEvents.isEmpty && model.events.count==4)
    model.displayFilter = .init()
    try await wait {!model.filtering && model.visibleEvents.count==4}
    let statements=await probe.statements()
    #expect(statements.filter {$0.contains("CREATE EVENT SESSION")}.count==1)
    #expect(statements.filter {$0.contains("DROP EVENT SESSION")}.isEmpty)
    #expect(!statements.contains {$0.contains("not a number")})
    #expect(await model.stop())
  }
  @Test func multiSelectionAndPortableExportPreserveOrderAndFullSQL() async throws {
    let (model,_)=try await fixture()
    let events=Array(model.events.prefix(2))
    #expect(ProfilerExport.sql(events)=="SELECT foo\nGO\nUPDATE bar")
    let json=try ProfilerExport.data(events,format:.trace)
    let root=try #require(JSONSerialization.jsonObject(with:json) as? [String:Any])
    #expect(root["format"] as? String == "MSSQLStudio.Profiler")
    let decoded=try #require(root["events"] as? [[String:Any]])
    #expect(decoded.count==2 && decoded[1]["sql"] as? String == "UPDATE bar")
    #expect(String(data:try ProfilerExport.data(events,format:.sql),encoding:.utf8)==ProfilerExport.sql(events))
    var selected:Set<UInt64>=[]
    let coordinator=ProfilerEventGrid.Coordinator(model:model,selection:Binding(get:{selected},set:{selected=$0}))
    coordinator.events=model.events
    let table=NSTableView();table.allowsMultipleSelection=true
    for _ in 0..<1 {table.addTableColumn(NSTableColumn(identifier:.init("sql")))}
    table.dataSource=coordinator;table.reloadData()
    table.selectRowIndexes(IndexSet([0,1]),byExtendingSelection:false)
    coordinator.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification,object:table))
    #expect(selected==Set([0,1]))
    #expect(await model.stop())
  }
  @Test func clickedCellFilterIsLocalAndPreviewKeepsOnlyLatestSelection() async throws {
    let (model,probe)=try await fixture()
    let coordinator=ProfilerEventGrid.Coordinator(model:model,selection:.constant([]))
    coordinator.events=model.events
    let column=try #require(ProfilerEventGrid.Coordinator.columns.firstIndex {$0.0=="host"})
    let menu=coordinator.menu(row:0,column:column)
    let action=try #require(menu.items.first {$0.title=="Host değerini filtrele"})
    #expect(NSApp.sendAction(try #require(action.action),to:action.target,from:action))
    try await wait {!model.filtering && model.visibleEvents.count==3}
    #expect(model.visibleEvents.allSatisfy {$0.host=="HOST-A"})
    let preview=ProfilerPreviewPresentation()
    preview.request(model.events)
    preview.request([model.events[1]])
    preview.request([model.events[3]])
    #expect(!preview.busy && preview.sql==model.events[3].sql)
    try await wait {!preview.busy}
    #expect(preview.sql==model.events[3].sql && !preview.tokens.isEmpty)
    preview.request([model.events[3]])
    #expect(!preview.busy)
    var object=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(model.events[0])) as? [String:Any])
    let largeSQL=String(repeating:"SELECT 1;\n",count:12000)+"-- END_MARKER"
    object["sql"]=largeSQL
    let large=try JSONDecoder().decode(SQLProfiler.Event.self,from:JSONSerialization.data(withJSONObject:object))
    preview.request([large]);try await wait {!preview.busy}
    #expect(preview.sql==largeSQL && preview.tokens.isEmpty)
    preview.request([model.events[3]]);try await wait {!preview.busy}
    let view=SQLPreviewView(frame:NSRect(x:0,y:0,width:420,height:180))
    view.display(preview.sql,lexicalSnapshot:preview.tokens)
    #expect(view.textView.string==model.events[3].sql)
    #expect((await probe.statements()).filter {$0.contains("CREATE EVENT SESSION")}.count==1)
    #expect(await model.stop())
  }
  @Test func sidebarCanExpandPastOldLimitAndInputModeKeepsHeight() async throws {
    let (model,_)=try await fixture()
    let host=NSHostingController(rootView:ProfilerPanel(model:model,background:{}));host.sizingOptions=[]
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
    window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:1380,height:900));window.orderFront(nil)
    defer {window.close()}
    try await Task.sleep(for:.milliseconds(80));host.view.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let split=try #require(children(host.view).compactMap {$0 as? NSSplitView}.first {$0.isVertical && $0.arrangedSubviews.count==2})
    let modes=children(host.view).compactMap {$0 as? ProfilerInputModeButton.Button}
    #expect(modes.filter {$0.title=="Liste"}.count==4 && modes.filter {$0.title=="Elle"}.count==2)
    #expect(children(host.view).compactMap {$0 as? NSTextField}.filter {$0.isEditable}.count>=7)
    #expect(split.bounds.width>=900)
    #expect(split.arrangedSubviews[0].frame.width<320)
    let sidebar=split.arrangedSubviews[0]
    let bitmap=try #require(sidebar.bitmapImageRepForCachingDisplay(in:sidebar.bounds))
    sidebar.cacheDisplay(in:sidebar.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-sidebar-layout.png"))
    split.adjustSubviews();split.setPosition(460,ofDividerAt:0)
    try await Task.sleep(for:.milliseconds(50));host.view.layoutSubtreeIfNeeded()
    #expect(split.arrangedSubviews[0].frame.width>420)
    #expect(await model.stop())
    var manual=false
    let choice=NSHostingController(rootView:ProfilerCaptureChoice(title:"Veritabanı",values:["","Demo"],text:.constant("Demo"),manual:Binding(get:{manual},set:{manual=$0})))
    choice.sizingOptions=[];choice.view.frame=NSRect(x:0,y:0,width:300,height:28)
    let choiceWindow=NSWindow(contentViewController:choice);choiceWindow.isReleasedWhenClosed=false
    choiceWindow.setFrameOrigin(NSPoint(x:-20000,y:0));choiceWindow.orderFront(nil);defer {choiceWindow.close()}
    try await Task.sleep(for:.milliseconds(40));choice.view.layoutSubtreeIfNeeded()
    let picker=try #require(children(choice.view).compactMap {$0 as? StudioSearchablePopUpButton}.first)
    let before=picker.convert(picker.bounds,to:choice.view)
    manual=true
    choice.rootView=ProfilerCaptureChoice(title:"Veritabanı",values:["","Demo"],text:.constant("Demo"),manual:Binding(get:{manual},set:{manual=$0}))
    try await Task.sleep(for:.milliseconds(40));choice.view.layoutSubtreeIfNeeded()
    let input=try #require(children(choice.view).compactMap {$0 as? NSTextField}.first {$0.isEditable})
    let after=input.convert(input.bounds,to:choice.view)
    #expect(abs(after.midY-before.midY)<1 && abs(after.height-before.height)<=2)

  }
  @Test func largePreviewSwitchBackMeasuresNativeTextReplacement() {
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:700,height:300))
    let window=NSWindow(contentRect:preview.bounds,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    let sql=String(repeating:"SELECT N'Large multi-selection SQL';\nGO\n",count:20000)
    preview.display(sql,lexicalSnapshot:[]);preview.layoutSubtreeIfNeeded()
    preview.scroll.contentView.scroll(to:NSPoint(x:0,y:200000));preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
    let clock=ContinuousClock(),start=clock.now
    preview.display("SELECT 1;",lexicalSnapshot:[]);preview.layoutSubtreeIfNeeded()
    let elapsed=start.duration(to:clock.now)
    print("PROFILER-LARGE-TO-SINGLE",elapsed)
    #expect(preview.textView.string=="SELECT 1;" && preview.scroll.contentView.bounds.minY==0)
    #expect(elapsed < .seconds(1))
  }
  @Test func profilerTimestampAndSymbolAspectStayReadable() {
    #expect(ProfilerTimestamp.display("2026-10-16T17:23:17.010Z")=="16.10.2026 17:23:17.010")
    #expect(ProfilerTimestamp.display("2026-10-16T17:23:17Z")=="16.10.2026 17:23:17.000")
    #expect(ProfilerTimestamp.display("2026-10-16T17:23:17.1Z")=="16.10.2026 17:23:17.100")
    #expect(ProfilerTimestamp.display("2026-10-16T17:23:17.1234567Z")=="16.10.2026 17:23:17.123")
    #expect(ProfilerTimestamp.display("2026-10-16T17:23:17+02:00")=="2026-10-16T17:23:17+02:00")
    let image=NSImage(size:NSSize(width:20,height:10))
    #expect(StudioSymbolDrawing.rect(for:image,in:NSRect(x:0,y:0,width:16,height:16))==NSRect(x:0,y:4,width:16,height:8))
  }
  @Test func inputModeUsesFullNativeHitAreaAndFilterAnchorsToScrolledHeader() async throws {
    let (model,_)=try await fixture()
    var manual=false
    let modeHost=NSHostingController(rootView:ProfilerInputModeButton(manual:Binding(get:{manual},set:{manual=$0}),title:"Veritabanı"))
    modeHost.sizingOptions=[]
    let modeWindow=NSWindow(contentViewController:modeHost);modeWindow.isReleasedWhenClosed=false
    modeWindow.setContentSize(NSSize(width:80,height:40));modeWindow.setFrameOrigin(NSPoint(x:-20000,y:0));modeWindow.orderFront(nil)
    defer {modeWindow.close()}
    try await Task.sleep(for:.milliseconds(40));modeHost.view.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let mode=try #require(descendants(modeHost.view).compactMap {$0 as? ProfilerInputModeButton.Button}.first)
    mode.frame=NSRect(x:0,y:0,width:52,height:26)
    #expect(mode.hitTest(NSPoint(x:2,y:13)) === mode)
    #expect(NSApp.sendAction(try #require(mode.action),to:mode.target,from:mode) && manual)
    mode.isEnabled=false
    _=NSApp.sendAction(try #require(mode.action),to:mode.target,from:mode)
    #expect(manual)
    let host=NSHostingController(rootView:ProfilerEventGrid(model:model,selection:.constant([])));host.sizingOptions=[]
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
    window.setContentSize(NSSize(width:960,height:700));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    try await Task.sleep(for:.milliseconds(80));host.view.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let table=try #require(children(host.view).compactMap {$0 as? NSTableView}.first)
    let owner=try #require(table.delegate as? ProfilerEventGrid.Coordinator)
    let position=table.column(withIdentifier:.init("application"));table.scrollColumnToVisible(position)
    host.view.layoutSubtreeIfNeeded()
    owner.tableView(table,didClick:table.tableColumns[position])
    let popup=try #require(owner.filterPopover);defer {popup.close()}
    let header=try #require(table.headerView),body=try #require(window.contentView)
    let visible=header.headerRect(ofColumn:position).intersection(header.visibleRect)
    let anchor=body.convert(visible,from:header)
    #expect(popup.isShown && !popup.animates && abs(popup.positioningRect.midX-anchor.midX)<1)
    var rule=ColumnRule();rule.choices=[.text("HOST-B")]
    try model.setColumnFilter(rule,column:.host)
    try await wait {!model.filtering && model.visibleEvents.count==1}
    #expect(model.visibleEvents[0].host=="HOST-B")
    if let view=popup.contentViewController?.view,let image=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
      view.cacheDisplay(in:view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-column-filter.png"))
    }
    #expect(await model.stop())
  }
  @Test func repeatedSnapshotDoesNotRebuildGridButLocalFilterStillWorks() async throws {
    let (model,probe)=try await fixture()
    let revision=model.gridRevision,count=await probe.statements().count
    for _ in 0..<200 {
      if await probe.statements().count>=count+3 {break}
      try await Task.sleep(for:.milliseconds(3))
    }
    #expect(await probe.statements().count>=count+3)
    #expect(model.gridRevision==revision && model.events.count==4 && !model.filtering)
    model.displayFilter.sqlSearch="bar"
    try await wait {!model.filtering && model.visibleEvents.map(\.id)==[1]}
    #expect(model.gridRevision != revision)
    #expect(await model.stop())
  }
  @Test func nativeGridContextActionsFilterClearAndStopItsOwnCapture() async throws {
    let (model,probe)=try await fixture()
    var selected:Set<UInt64>=[]
    let coordinator=ProfilerEventGrid.Coordinator(model:model,selection:Binding(get:{selected},set:{selected=$0}))
    coordinator.events=model.visibleEvents
    let menu=coordinator.menu(row:0)
    #expect(menu is StudioMenu && !menu.autoenablesItems)
    let client=try #require(menu.items.first {$0.title=="Bu İstemciyi Filtrele"})
    #expect(client.isEnabled && client.image != nil)
    #expect(NSApp.sendAction(try #require(client.action),to:client.target,from:client))
    try await wait {!model.filtering && model.visibleEvents.count==2}
    #expect(model.visibleEvents.allSatisfy {$0.clientPID=="123" && $0.host=="HOST-A"})
    let clear=try #require(menu.items.first {$0.title=="Listeyi Temizle"})
    #expect(NSApp.sendAction(try #require(clear.action),to:clear.target,from:clear))
    try await wait {!model.filtering && model.visibleEvents.isEmpty}
    let count=await probe.statements().count
    for _ in 0..<100 where await probe.statements().count<=count {try await Task.sleep(for:.milliseconds(3))}
    #expect(model.events.isEmpty && selected.isEmpty && model.running)
    #expect(model.choices.values(for:.host)==[""])
    let stop=try #require(menu.items.first {$0.title=="İzlemeyi Durdur"})
    #expect(NSApp.sendAction(try #require(stop.action),to:stop.target,from:stop))
    try await wait {!model.hasSession && !model.busy}
    #expect((await probe.statements()).filter {$0.contains("DROP EVENT SESSION")}.count==1)
    let empty=coordinator.menu(row:-1)
    #expect(empty.items.first {$0.title=="Bu İstemciyi Filtrele"}?.isEnabled==false)
  }
}
