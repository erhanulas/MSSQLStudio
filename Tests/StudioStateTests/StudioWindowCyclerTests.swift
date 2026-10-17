import AppKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct StudioWindowCyclerTests {
  @Test func twoWindowCardsFitAndHoverDoesNotSelectOrOpen() async throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let entries:[StudioWindowSwitcherView.Entry]=[
        .init(title:"SQLQuery9.sql",context:"DİNAMİK / TEST2026",type:"Çalışma alanı",symbol:"rectangle.split.2x1",status:"Açık"),
        .init(title:"Activity Monitor",context:"DİNAMİK",type:"Sunucu izleme",symbol:"waveform.path.ecg",status:"Şu an açık")]
      var selected = -1,accepted = -1
      let view=StudioWindowSwitcherView(entries:entries,selected:0,select:{selected=$0},accept:{accepted=$0})
      let height=2*(StudioWindowPickerStyle.rowHeight+StudioWindowPickerStyle.rowGap)+StudioWindowPickerStyle.chromeHeight
      let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:620,height:height),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=view;window.orderFront(nil);defer {window.close()}
      view.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(50));view.layoutSubtreeIfNeeded()
      let row=try #require(view.table.rowView(atRow:1,makeIfNecessary:true))
      let last=view.table.convert(row.bounds,from:row)
      #expect(last.intersection(view.table.visibleRect).height>=last.height-0.5)
      let event=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil))
      row.mouseEntered(with:event)
      #expect(view.table.selectedRow==0 && selected == -1 && accepted == -1)
      row.mouseExited(with:event)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-window-picker-two-\(theme).png"))
      }
    }
  }
  @Test func mainWindowEntrySeparatesQueryNameFromConnectionContext() {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:.init(name:"DİNAMİK",visibleDatabases:[]),password:"")
    let document=QueryDocument(server:server,database:"TEST2026",title:"SQLQuery9.sql")
    state.active=document
    let workbench=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:620,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=workbench;defer {window.close()}
    window.title="SQLQuery9.sql — DİNAMİK / TEST2026"
    let cycler=StudioWindowCycler(main:window)
    let entry=cycler.entry(for:window)
    #expect(entry.title=="SQLQuery9.sql" && entry.context=="DİNAMİK / TEST2026")
    #expect(entry.symbol=="rectangle.split.2x1")
    let activity=StudioAssociatedWindow(contentRect:NSRect(x:-20000,y:0,width:620,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    activity.isReleasedWhenClosed=false;defer {activity.close()}
    activity.identifier = .init("activity|fixture");activity.title="Activity Monitor · DİNAMİK"
    let tool=cycler.entry(for:activity)
    #expect(tool.title=="Activity Monitor" && tool.context=="DİNAMİK" && tool.type=="Sunucu izleme")
  }
  @Test func nativePickerKeepsNamesVisibleWithManyWindowsInBothThemes() async throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let entries=(0..<20).map {i in StudioWindowSwitcherView.Entry(title:i==1 ? "SQL Profiler · DİNAMİK — Üretim Sunucusu":"Activity Monitor · Sunucu \(i+1)",context:"ADAGRUP2026 · SQL Server",type:i==1 ? "SQL izleme":"Sunucu izleme",symbol:i==1 ? "list.bullet.rectangle":"waveform.path.ecg",status:i==2 ? "Küçültülmüş":"Açık")}
      var selected = -1,accepted = -1
      let view=StudioWindowSwitcherView(entries:entries,selected:1,select:{selected=$0},accept:{accepted=$0})
      let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:620,height:600),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=view;window.orderFront(nil)
      defer {window.close()}
      view.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(50));view.layoutSubtreeIfNeeded()
      let cell=try #require(view.table.view(atColumn:0,row:1,makeIfNecessary:true) as? NSTableCellView)
      let title=try #require(cell.textField)
      #expect(title.stringValue==entries[1].title && title.frame.width>250 && title.frame.height>12)
      #expect(view.table.numberOfRows==20 && view.table.selectedRow==1 && selected == -1 && accepted == -1)
      view.table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
      #expect(selected==2 && accepted == -1)
      view.updateSelection(19,reveal:true)
      #expect(view.table.selectedRow==19 && selected==2 && accepted == -1)
      view.updateSelection(1,reveal:true);view.layoutSubtreeIfNeeded()
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-window-picker-\(theme).png"))
      }
    }
  }
  @Test func controlTabCyclesOwnedWindowsBothWaysAndLeavesSheetsAlone() throws {
    _=NSApplication.shared
    func window(_ managed:Bool)->NSWindow {
      let rect=NSRect(x:-20000,y:0,width:400,height:300)
      let result=managed ? StudioAssociatedWindow(contentRect:rect,styleMask:[.titled,.closable],backing:.buffered,defer:false):NSWindow(contentRect:rect,styleMask:[.titled,.closable],backing:.buffered,defer:false)
      result.isReleasedWhenClosed=false;result.orderFront(nil);return result
    }
    let main=window(false),activity=window(true),profiler=window(true),unrelated=window(false)
    defer {[main,activity,profiler,unrelated].forEach {$0.close()}}
    var activated:NSWindow?
    let cycler=StudioWindowCycler(main:main,activate:{activated=$0})
    defer {cycler.dismiss()}
    let list=cycler.candidates([profiler,main,unrelated,activity])
    #expect(list.count==3 && !list.contains(where:{$0 === unrelated}))
    func event(_ window:NSWindow,_ flags:NSEvent.ModifierFlags)->NSEvent {
      NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
    }
    let first=list[0],second=list[1]

    #expect(cycler.handle(event(first,.control)))
    #expect(activated == nil && cycler.panel != nil && cycler.windows[cycler.index] === second)
    let release=NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:[],timestamp:0,windowNumber:first.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:59)!
    #expect(!cycler.handle(release))
    #expect(activated === second && cycler.panel == nil)
    #expect(cycler.handle(event(second,[.control,.shift])))
    #expect(cycler.windows[cycler.index] === first && activated === second)
    let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:second.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
    #expect(cycler.handle(escape))
    #expect(cycler.panel == nil && activated === second)
    #expect(cycler.handle(event(first,.control)))
    let forward=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.control,timestamp:0,windowNumber:first.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
    #expect(cycler.handle(forward))
    let chosen=cycler.windows[cycler.index]
    #expect(activated === second)
    let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.control,timestamp:0,windowNumber:first.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
    #expect(cycler.handle(enter))
    #expect(activated === chosen && cycler.panel == nil)
    #expect(!cycler.handle(event(first,.option)))
    let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    sheet.isReleasedWhenClosed=false;first.beginSheet(sheet,completionHandler:nil)
    #expect(!cycler.handle(event(first,.control)))
    first.endSheet(sheet);sheet.close()
  }
}
