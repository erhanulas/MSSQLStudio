import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CompletionGutterTests {
  @Test func completionPresentationRetainsInsertionTextSelectionAndEditorFocus() throws {
    _ = NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(old ?? "light")}
    let list=SQLSuggestionList()
    let suggestions=(0..<18).map { SQLIntelligence.Suggestion(text:"[dbo].[Customers\($0)] AS C\($0)",label:"[dbo].[Customers\($0)]",kind:.table,detail:"[dbo].[Customers\($0)] AS C\($0)") }
    list.update(suggestions,prefix:"Cus")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false; defer {window.close()}
    window.contentViewController=list
    let editor=SQLTextView(usingTextLayoutManager:true)
    editor.frame=NSRect(x:0,y:-40,width:100,height:30); list.view.addSubview(editor)
    window.makeFirstResponder(editor)
    let responder=window.firstResponder
    var accepted:String?
    list.accept={accepted=list.items[$0].text}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      list.view.frame.size=list.preferredContentSize
      list.view.layoutSubtreeIfNeeded()
      #expect(list.preferredContentSize == NSSize(width:500,height:486))
      #expect(list.table.enclosingScrollView!.frame.minY == 34)
      #expect(list.table.rowHeight == 40 && !list.table.acceptsFirstResponder)
      let cell=try #require(list.tableView(list.table,viewFor:list.table.tableColumns[0],row:0))
      #expect(cell.toolTip?.contains(suggestions[0].text) == true)
      #expect(cell.accessibilityLabel()?.contains("Tablo") == true)
      list.move(100); #expect(list.table.selectedRow == 17)
      list.move(-1); #expect(list.table.selectedRow == 16)
      #expect(window.firstResponder === responder && accepted == nil)
      #expect(list.items == suggestions)
      if let image=list.view.bitmapImageRepForCachingDisplay(in:list.view.bounds) {
        list.view.cacheDisplay(in:list.view.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-070-completion-\(theme).png"))
      }
    }
    #expect(NSApp.sendAction(try #require(list.table.doubleAction),to:list.table.target,from:list.table))
    #expect(accepted == suggestions[16].text)
    list.update(Array(suggestions.prefix(1))); #expect(list.table.selectedRow == 0)
    #expect(list.preferredContentSize.height == 108)
    #expect(list.table.enclosingScrollView!.documentVisibleRect.contains(list.table.rect(ofRow:0)))
  }

  @Test func actualPopoverKeepsUsableSizeAndKeyboardSelectionVisible() async throws {
    _ = NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Keyboard completion")
    doc.sql="SELECT * FROM TBLSTSABIT WHERE STOK_"
    doc.intelligenceCatalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"TBLSTSABIT",columns:(0..<30).map {"STOK_\($0)"})],synchronizedAt:Date()))
    doc.catalogDatabase="master";doc.catalogVerified=true
    let editor=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:50,y:50,width:900,height:680),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=editor.surface
    defer {editor.editor.dismissSuggestions?();window.close()}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor.editor)
    editor.editor.setSelectedRange(NSRange(location:(doc.sql as NSString).length,length:0))
    editor.scheduleIntelligence(manual:true)
    for _ in 0..<200 where !editor.completionShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(editor.completionShown && editor.completionSize.width == 500 && editor.completionSize.height >= 318)
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let table=try #require(NSApp.windows.flatMap {$0.contentView.map(descendants) ?? []}.compactMap {$0 as? SuggestionTable}.first {$0.numberOfRows == 30})
    func key(_ code:UInt16) throws {
      let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code))
      editor.editor.keyDown(with:event)
    }
    let caret=editor.editor.selectedRange()
    try key(121);#expect(table.selectedRow >= 6)
    try key(119);#expect(table.selectedRow == 29)
    #expect(table.enclosingScrollView!.documentVisibleRect.contains(table.rect(ofRow:29)))
    try key(126);#expect(table.selectedRow == 28)
    try key(115);#expect(table.selectedRow == 0)
    try key(125);#expect(table.selectedRow == 1)
    #expect(editor.editor.selectedRange() == caret && window.firstResponder === editor.editor)
    try key(48)
    #expect(editor.editor.string == "SELECT * FROM TBLSTSABIT WHERE [STOK_1]")
    #expect(!editor.completionShown)
    editor.editor.undoManager?.undo()
    #expect(editor.editor.string == "SELECT * FROM TBLSTSABIT WHERE STOK_")
  }

  @Test func fixedGutterTracksVerticalScrollFilterSortPagingAndEditsWithoutEnteringClipboard() async throws {
    _ = NSApplication.shared
    let controller=ResultController()
    let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:720,height:360),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false; defer {window.close()}
    window.contentViewController=controller
    controller.view.frame=NSRect(x:0,y:0,width:720,height:360)
    let fields=(0..<16).map {Field("Column\($0)")}
    let values=(0..<150).map { row in (0..<16).map { column -> String? in column == 1 ? nil:String(format:"%03d",row)+":\(column)"} }
    controller.setPageSize(100); controller.update(Rows(fields:fields,values:values))
    controller.view.layoutSubtreeIfNeeded()
    let table=controller.table, gutter=controller.rowGutter
    let scroll=try #require(table.enclosingScrollView)
    let gutterFrame=controller.view.convert(gutter.bounds,from:gutter)
    #expect(gutterFrame.minX == 0 && gutterFrame.width == 60)
    #expect(table.tableColumns[0].isHidden && table.tableColumns[1].identifier.rawValue == "0")
    #expect(gutter.clipsToBounds && gutter.viewport.minY >= gutter.convert(table.headerView!.bounds,from:table.headerView!).maxY)
    scroll.contentView.scroll(to:NSPoint(x:600,y:300)); scroll.reflectScrolledClipView(scroll.contentView)
    #expect(scroll.contentView.bounds.minX >= 600 && scroll.contentView.bounds.minY >= 300)
    #expect(controller.view.convert(gutter.bounds,from:gutter) == gutterFrame)
    // The first intersecting row can be partially clipped; click a visible row centre.
    let first=try #require(gutter.visibleRows.first {gutter.viewport.contains(NSPoint(x:30,y:gutter.rowRect($0).midY))})
    #expect(first >= 10 && gutter.label?(first).0 == String(first+1))
    #expect(abs(gutter.rowRect(first).minY-gutter.viewport.minY) <= 25)
    let rect=gutter.rowRect(first)
    let point=gutter.convert(NSPoint(x:30,y:rect.midY),to:nil)
    let click=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    gutter.mouseDown(with:click)
    #expect(table.selectedRow == first && table.cellColumns.isEmpty)
    table.copyWithHeaders()
    let copied=try #require(NSPasteboard.general.string(forType:.string))
    #expect(copied.hasPrefix("Column0\tColumn1\t") && copied.contains("\tNULL\t"))
    #expect(!copied.hasPrefix("#") && controller.pageExportIndices?.first == 0)
    table.selectGutterRow(first+2,extending:true)
    #expect(table.selectedRowIndexes == IndexSet(integersIn:first...first+2))
    table.moveColumn(3,toColumn:1)
    controller.filter="149:0"
    for _ in 0..<200 where controller.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!controller.isProcessing && gutter.label?(0).0 == "150")
    controller.filter=""; controller.setPageSize(10)
    let last=try #require(controller.toolbar.arrangedSubviews.compactMap {$0 as? NSButton}.first {$0.tag == 3})
    last.performClick(nil)
    #expect(controller.pageStart == 140 && gutter.label?(0).0 == "141")
    table.sortDescriptors=[NSSortDescriptor(key:"0",ascending:false)]
    for _ in 0..<200 where controller.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!controller.isProcessing && gutter.label?(0).0 == "10")
    controller.editDefinition=TableDefinition(schema:"dbo",name:"T",columns:fields.enumerated().map {.init(id:$0.offset+1,name:$0.element.name,type:"nvarchar(50)")},primaryKey:["Column0"])
    controller.editingAllowed={true}
    controller.setEditValue("changed",row:0,column:0)
    #expect(gutter.label?(0).0 == "✎ 10")
    table.selectGutterRow(0); controller.toggleSelectedDeletion()
    #expect(gutter.label?(0).0 == "− 10")
    controller.appendRow()
    #expect(gutter.label?(controller.pageCount-1).0 == "+ Yeni")
    controller.discardEdits(); #expect(gutter.label?(0).0 == "10")
    #expect(controller.result.values[9][0] == "009:0" && controller.result.values[9][1] == nil)
  }
}
