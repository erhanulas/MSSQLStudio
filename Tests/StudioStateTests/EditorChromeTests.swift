import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorChromeTests {
  private func event(_ text:String,key:UInt16=0)->NSEvent {
    NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:key)!
  }
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  @Test func pickerOpensAsListAndTypingStartsSearchWithoutAcceptingSelection() {
    _=NSApplication.shared
    var accepted:[String]=[];var closed=0
    let chooser=StudioSearchableChoices(values:["master","DemoDB","Archive"],selected:"DemoDB") {accepted.append($0)}
    chooser.dismiss={closed+=1}
    #expect(chooser.search.isHidden && chooser.table.selectedRow==1)
    #expect(chooser.handle(event("",key:125)) && chooser.table.selectedRow==2 && chooser.search.isHidden)
    #expect(chooser.handle(event("m")))
    #expect(!chooser.search.isHidden && chooser.search.stringValue=="m" && chooser.filtered==["master","DemoDB"] && accepted.isEmpty)
    chooser.search.stringValue="Demo";chooser.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
    #expect(chooser.filtered==["DemoDB"] && accepted.isEmpty)
    #expect(chooser.handle(event("\r",key:36)) && accepted==["DemoDB"] && closed==1)
    chooser.filter("missing");chooser.commit();#expect(accepted==["DemoDB"])
    #expect(chooser.handle(event("",key:53)) && closed==2)
    #expect(chooser.table.rowHeight==StudioMetrics.choiceRowHeight)
  }
  @Test func editorActionsBelongToTheirDocumentAndRefreshBusyAndReadOnlyStates() {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Fixture")
    doc.server.online=false;var formats=0
    let actions=QueryEditorActions(document:doc,focus:{},format:{formats+=1})
    #expect(actions.document === doc && actions.run.isEnabled && !actions.cancel.isEnabled)
    #expect(actions.run.title.isEmpty && !actions.run.prominent && actions.run.flat)
    actions.formatButton.performClick(nil);#expect(formats==1)
    doc.state = .running;actions.refresh()
    #expect(!actions.run.isEnabled && !actions.plan.isEnabled && actions.cancel.isEnabled)
    doc.state = .disconnected;actions.refresh();#expect(actions.run.isEnabled && !actions.cancel.isEnabled)
    #expect(actions.formatButton.toolTip?.contains(GridShortcuts.binding(.format).label)==true)
  }
  @Test func databaseIsLeftOfEditorCommandsAndDetachReusesSameCommandBar() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(name:"Fixture"),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Layout");doc.sql="SELECT 1";state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:-5000,y:0,width:1060,height:700),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host
    defer {host.redockQueries();window.close()}
    host.view.frame.size=NSSize(width:1060,height:700);host.view.layoutSubtreeIfNeeded()
    let mainViews=views(host.view)
    let db=try #require(mainViews.first {$0.accessibilityIdentifier()=="databaseSelector"})
    let run=try #require(mainViews.first {$0.accessibilityIdentifier()=="editorRun"})
    let frame=host.view.convert(run.bounds,from:run),dbFrame=host.view.convert(db.bounds,from:db)
    #expect(dbFrame.maxX<=frame.minX && abs(dbFrame.midY-frame.midY)<2)
    let actions=try #require(mainViews.compactMap {$0 as? QueryEditorActions}.first)
    let query=try #require(host.queryController(for:doc))
    host.detachQuery()
    let detached=try #require(query.view.window?.contentView);detached.layoutSubtreeIfNeeded()
    #expect(views(detached).compactMap {$0 as? QueryEditorActions}.first === actions)
    #expect(views(detached).filter {$0.accessibilityIdentifier()=="editorRun"}.count==1)
    #expect(views(detached).contains {$0.accessibilityIdentifier()=="databaseSelector"})
    host.redockQueries();host.view.layoutSubtreeIfNeeded()
    #expect(views(host.view).compactMap {$0 as? QueryEditorActions}.first === actions && doc.sql=="SELECT 1")
  }
  @Test func unchangedChoiceRefreshPreservesSearchAndChangedScopeRejectsStaleAccept() throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:500,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let picker=StudioSearchablePopUpButton(frame:NSRect(x:20,y:220,width:170,height:28));window.contentView?.addSubview(picker)
    defer {picker.removeFromSuperview();window.close()}
    window.orderFront(nil)
    let context=UUID();picker.updateChoices(["master","DemoDB"],selected:"master",contextID:context,enabled:true)
    picker.showChoices()
    let choices=try #require(picker.choices);choices.beginSearch("Demo")
    picker.updateChoices(["master","DemoDB"],selected:"master",contextID:context,enabled:true)
    #expect(picker.choices === choices && choices.search.stringValue=="Demo" && choices.view.window?.isVisible==true)
    picker.updateChoices(["master","Archive"],selected:"master",contextID:UUID(),enabled:true)
    #expect(choices.view.window?.isVisible != true)
    choices.commit();#expect(picker.titleOfSelectedItem=="master")
  }

}
