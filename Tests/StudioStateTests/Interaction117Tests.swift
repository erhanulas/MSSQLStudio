import AppKit
import Testing
import SwiftUI
@testable import MSSQLStudio
@testable import SQLServerKit

private actor Interaction117Gate {
  private(set) var started=false
  private var released=false
  private var continuation:CheckedContinuation<Void,Never>?
  func wait() async {
    started=true
    if released {return}
    await withCheckedContinuation {continuation=$0}
  }
  func open() {released=true;continuation?.resume();continuation=nil}
}
@MainActor private final class Click117Target:NSObject {
  var count=0
  @objc func activate(_ sender:Any?) {count+=1}
}
@MainActor @Suite(.serialized) struct Interaction117Tests {
  @Test func tabPaddingAndIconRouteToSelectionButCloseRemainsIndependent() throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:100),styleMask:.borderless,backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;defer {window.close()}
    let tab=QueryTabSurface(frame:NSRect(x:20,y:20,width:220,height:36))
    window.contentView?.addSubview(tab)
    let title=DocumentButton(frame:NSRect(x:30,y:6,width:120,height:24));title.title="Query";title.draggable=true
    let close=QueryTabCloseButton(frame:NSRect(x:188,y:6,width:24,height:24))
    tab.addSubview(title);tab.addSubview(close);tab.primaryButton=title
    for point in [NSPoint(x:1,y:1),NSPoint(x:12,y:18),NSPoint(x:217,y:34)] {
      #expect(tab.hitTest(tab.convert(point,to:tab.superview)) === title)
      #expect(title.acceptsRelease(at:tab.convert(point,to:nil)))
    }
    #expect(tab.hitTest(tab.convert(NSPoint(x:200,y:18),to:tab.superview)) === close)
    #expect(!title.acceptsRelease(at:tab.convert(NSPoint(x:221,y:18),to:nil)))
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:close.convert(NSPoint(x:1,y:1),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    #expect(close.cell?.hitTest(for:event,in:close.bounds,of:close).contains(.trackableArea)==true)
    let target=Click117Target()
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    title.document=QueryDocument(server:server,database:"master",title:"Test")
    title.target=target;title.action=#selector(Click117Target.activate(_:))
    func click(release:NSPoint) throws {
      let up=try #require(NSEvent.mouseEvent(with:.leftMouseUp,location:tab.convert(release,to:nil),modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0))
      var events=[up]
      title.trackingEventFixture={events.isEmpty ? nil:events.removeFirst()}
      title.mouseDown(with:event)
    }
    try click(release:NSPoint(x:1,y:1));#expect(target.count==1)
    try click(release:NSPoint(x:221,y:18));#expect(target.count==1)
    close.isEnabled=false
    #expect(close.cell?.hitTest(for:event,in:close.bounds,of:close).isEmpty==true)
  }
  @Test func databaseIndexIconsHaveStableTrailingColumns() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:["A","VeryLongDatabaseName"]),password:"")
    server.online=false;server.databases=[.init(id:1,name:"A"),.init(id:2,name:"VeryLongDatabaseName")];state.servers=[server]
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    window.setContentSize(NSSize(width:1200,height:800));host.view.layoutSubtreeIfNeeded()
    var frames:[NSRect]=[]
    for name in ["A","VeryLongDatabaseName"] {
      let node=TreeNode(name,kind:.database,server:server,database:name)
      let cell=try #require(host.outlineView(host.outline,viewFor:host.outline.tableColumns.first(where:{$0.identifier.rawValue=="indexes"}),item:node))
      window.contentView=cell;window.setContentSize(NSSize(width:56,height:27));cell.needsLayout=true;cell.layoutSubtreeIfNeeded()
      let buttons=cell.subviews.compactMap {$0 as? DatabaseIndexButton}.sorted {$0.frame.minX<$1.frame.minX}
      #expect(buttons.count==2)
      let first=try #require(buttons.first),last=try #require(buttons.last)
      #expect(first.frame.width==24)
      #expect(abs(last.frame.width-24)<=1/window.backingScaleFactor)
      #expect(last.frame.maxX<=cell.bounds.width)
      #expect(last.frame.minX-first.frame.minX==26)
      #expect(first.accessibilityIdentifier()=="databaseIndex_"+node.database)
      #expect(last.accessibilityIdentifier()=="databaseDefinitionIndex_"+node.database)
      #expect(first.image != nil && last.image != nil)
      frames.append(first.frame)
    }
    #expect(frames.count==2 && frames.first==frames.last)
  }
  @Test func databaseSwitchReleasesQueryBeforeSlowCompletionRefresh() async throws {
    let folder=URL(fileURLWithPath:"/tmp/StudioDBSwitch-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("catalog.sqlite"))
    let metadata=Interaction117Gate(),execution=Interaction117Gate()
    defer {Task {await metadata.open();await execution.open()}}
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in
      await metadata.wait()
      return SQLCatalogSnapshot(symbols:[])
    })
    let server=ConnectedServer(profile:ServerProfile(),password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:service)
    let doc=QueryDocument(server:server,database:"master",title:"Test");doc.state = .ready
    doc.databaseChangeFixture={_ in}
    doc.useDatabase("Other")
    for _ in 0..<1000 {
      if await metadata.started {break}
      try await Task.sleep(for:.milliseconds(2))
    }
    #expect(await metadata.started)
    #expect(doc.database=="Other" && !doc.busy && doc.canExecute && doc.task==nil)
    doc.sql="SELECT 42";#expect(doc.sql=="SELECT 42")
    doc.executionFixture={_,_ in await execution.wait();return Execution()}
    doc.execute()
    for _ in 0..<1000 {
      if await execution.started {break}
      try await Task.sleep(for:.milliseconds(2))
    }
    #expect(await execution.started)
    #expect(doc.busy && doc.task != nil)
    await metadata.open()
    for _ in 0..<1000 where !doc.catalogVerified {try await Task.sleep(for:.milliseconds(2))}
    #expect(doc.catalogVerified && doc.busy && doc.task != nil)
    await execution.open()
    for _ in 0..<1000 where doc.busy {try await Task.sleep(for:.milliseconds(2))}
    #expect(doc.database=="Other" && !doc.busy)
  }
  @Test func progressRowRefreshDoesNotRestoreOtherBranches() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state);host.loadViewIfNeeded()
    let root=try #require(host.roots.first)
    let branch=try #require(root.children.first)
    host.expansionState[branch.persistenceKey]=false
    host.restoringTree=true
    host.outline.expandItem(branch)
    host.restoringTree=false
    #expect(host.outline.isItemExpanded(branch))
    host.reloadExplorer(item:root)
    #expect(host.outline.isItemExpanded(branch))
    host.reloadExplorer(item:root,children:true)
    #expect(!host.outline.isItemExpanded(branch))
  }
  @Test func indexPanelRendersStoredDatabaseUsageInBothThemes() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/StudioIndexPanel-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("catalog.sqlite"))
    let profile=ServerProfile(name:"Index fixture",visibleDatabases:["DemoDB"],indexObjectDefinitions:true)
    let scope=CatalogDiskIndex.scope(profile:profile,database:"DemoDB")
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[]))
    let server=ConnectedServer(profile:profile,password:"",diskIndex:disk);server.online=false
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    for mode in ["light","dark"] {
      StudioTheme.apply(mode)
      let controller=NSHostingController(rootView:ExplorerIndexPanel(server:server,databases:["DemoDB"],refresh:{},setDefinitionIndex:{_,_ in}))
      controller.sizingOptions=[]
      let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:600,height:540),styleMask:[],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=controller.view
      window.orderFront(nil)
      try await Task.sleep(for:.milliseconds(150))
      controller.view.layoutSubtreeIfNeeded();window.displayIfNeeded()
      #expect(controller.view.bounds.size==NSSize(width:600,height:540))
      let bitmap=try #require(controller.view.bitmapImageRepForCachingDisplay(in:controller.view.bounds))
      controller.view.cacheDisplay(in:controller.view.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/MSSQLStudio-index117-\(mode).png"))
      window.close()
    }
  }
  @Test func failedDatabaseSwitchKeepsContextAndAllowsRetry() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"Original",title:"Test");doc.state = .ready
    doc.sql="SELECT 1";doc.databaseChangeFixture={_ in throw SQLFailure("Synthetic USE failure")}
    doc.useDatabase("Other")
    for _ in 0..<100 where doc.busy {try await Task.sleep(for:.milliseconds(2))}
    #expect(!doc.busy && doc.database=="Original" && doc.sql=="SELECT 1" && doc.messages.contains("Synthetic USE failure"))
  }
}
