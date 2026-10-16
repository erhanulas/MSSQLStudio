import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct GridToolbarTests {
  private final class SearchTarget:NSObject {
    var received:[String]=[]
    @objc func changed(_ field:NSSearchField) {received.append(field.stringValue)}
  }
  @Test func sharedSearchEditingStaysBetweenSearchAndClearIcons() async throws {
    _=NSApplication.shared
    let field=StudioSearchField(frame:NSRect(x:12,y:12,width:280,height:28))
    field.placeholderString="Nesnelerde filtrele"
    let root=NSView(frame:NSRect(x:0,y:0,width:320,height:60));root.addSubview(field)
    let window=NSWindow(contentRect:root.bounds,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=root;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.makeKeyAndOrderFront(nil)
    defer {window.close()}
    for value in ["","dbo.Customer"] {
      window.makeFirstResponder(nil);field.stringValue=value;field.selectText(nil)
      try await Task.sleep(for:.milliseconds(20))
      let editor=try #require(field.currentEditor() as? NSTextView)
      let rect=field.convert(editor.visibleRect,from:editor)
      let cell=try #require(field.cell as? NSSearchFieldCell)
      let expected=cell.searchTextRect(forBounds:field.bounds)
      #expect(abs(rect.minX-expected.minX)<1 && abs(rect.width-expected.width)<1)
      if !value.isEmpty {
        window.makeFirstResponder(nil)
        let nativeEditor=try #require(window.fieldEditor(true,for:field))
        cell.edit(withFrame:field.bounds,in:field,editor:nativeEditor,delegate:field,event:nil)
        let editRect=field.convert((nativeEditor as? NSTextView)?.visibleRect ?? .zero,from:nativeEditor)
        #expect(abs(editRect.minX-expected.minX)<1 && abs(editRect.width-expected.width)<1)
      }
      let image=try #require(root.bitmapImageRepForCachingDisplay(in:root.bounds));root.cacheDisplay(in:root.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-search-focused-"+(value.isEmpty ? "empty":"text")+".png"))
      #expect(rect.minX >= cell.searchButtonRect(forBounds:field.bounds).maxX+4)
      #expect(rect.maxX <= cell.cancelButtonRect(forBounds:field.bounds).minX-2)
    }
  }
  @Test func sharedSearchKeepsNativeClearAndFitsBothThemes() throws {
    _=NSApplication.shared
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let root=NSView(frame:NSRect(x:0,y:0,width:380,height:140))
      let window=NSWindow(contentRect:root.bounds,styleMask:.borderless,backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=root;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      defer {window.close()}
      let target=SearchTarget()
      for (index,placeholder) in ["Tüm ayarlarda ara…","Nesnelerde filtrele","Sonuç ara"].enumerated() {
        let field=StudioSearchField(frame:NSRect(x:12,y:CGFloat(100-index*40),width:index==2 ? 140:356,height:28))
        field.placeholderString=placeholder;field.target=target;field.action=#selector(SearchTarget.changed(_:));root.addSubview(field)
        #expect(field.cell is NSSearchFieldCell && field.intrinsicContentSize.height==28 && field.isEditable && field.isSelectable)
        if index==1 {
          field.stringValue="customer"
          let cell=try #require(field.cell as? NSSearchFieldCell)
          #expect(field.bounds.contains(cell.searchTextRect(forBounds:field.bounds)))
          cell.cancelButtonCell?.performClick(field)
          #expect(field.stringValue.isEmpty && target.received.last=="")
        }
      }
      root.layoutSubtreeIfNeeded()
      let image=try #require(root.bitmapImageRepForCachingDisplay(in:root.bounds));root.cacheDisplay(in:root.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-shared-search-"+theme+".png"))
    }
  }
  @Test func geometryRefreshClearsHoverWithoutMouseExit() throws {
    _=NSApplication.shared
    let button=StudioToolbarButton(symbol:"sidebar.left",label:"Explorer")
    button.flat=true
    let event=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,trackingNumber:0,userData:nil))
    button.mouseEntered(with:event)
    let hover=button.layer?.backgroundColor
    button.updateTrackingAreas()
    #expect(button.layer?.backgroundColor != hover)
    #expect(button.layer?.borderWidth == 0 && button.state == .off)
  }
  @Test func toolbarHoverStaysInsideControlAndUsesOneCustomHelp() async throws {
    _=NSApplication.shared
    let button=StudioToolbarButton(symbol:"play",label:"Çalıştır",tone:.success)
    button.flat=true;button.toolTip="Çalıştır · ⌃R"
    let root=NSView(frame:NSRect(x:0,y:0,width:320,height:100))
    let window=NSWindow(contentRect:root.frame,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=root
    defer {StudioHoverHelp.shared.hide();window.close()}
    root.addSubview(button);button.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:12),button.topAnchor.constraint(equalTo:root.topAnchor,constant:12)])
    window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil);root.layoutSubtreeIfNeeded()
    #expect(button.frame.size==NSSize(width:28,height:26))
    #expect(button.alignmentRectInsets.top==0 && button.alignmentRectInsets.bottom==0)
    let event=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil))
    button.mouseEntered(with:event)
    #expect(button.layer?.borderWidth==0 && button.clipsToBounds)
    #expect((button.cell as? NSButtonCell)?.highlightsBy.isEmpty==true)
    try await Task.sleep(for:.milliseconds(250))
    #expect(StudioHoverHelp.shared.visibleTitle=="Çalıştır · ⌃R")
    #expect(window.childWindows?.count==1)
    button.toolTip="Yeni açıklama"
    #expect(StudioHoverHelp.shared.visibleTitle==nil && button.accessibilityHelp()=="Yeni açıklama")
    button.tracksActiveState=true;button.state = .on
    #expect(button.layer?.borderWidth==1)
    let host=WorkbenchController(state:StudioState())
    let toolbar=NSToolbar(identifier:"HoverFixture")
    let item=try #require(host.toolbar(toolbar,itemForItemIdentifier:.init("query"),willBeInsertedIntoToolbar:true))
    #expect(item.toolTip==nil && (item.view as? StudioToolbarButton)?.toolTip?.isEmpty==false)
    let controls:[NSView]=[StudioToolbarPopUpButton(),StudioResultTabButton(),StudioSearchablePopUpButton()]
    for control in controls {
      control.toolTip="Tek yardım"
      #expect(control.toolTip=="Tek yardım" && control.accessibilityHelp()=="Tek yardım")
      control.toolTip=nil;#expect(control.accessibilityHelp()==nil)
    }
  }
  func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  func editingFixture() throws -> (QueryController, ResultController, NSWindow) {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Inline editing")
    doc.state = .ready
    doc.results = [Rows(fields: [Field("Id", type: 4), Field("Name"), Field("Required")], values: [["1", "Alpha", "A"], ["2", "Beta", "B"]])]
    let controller = QueryController(document: doc)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    grid.editDefinition = TableDefinition(schema: "dbo", name: "T", columns: [
      .init(id: 1, name: "Id", type: "int", identity: true),
      .init(id: 2, name: "Name", type: "nvarchar(50)"),
      .init(id: 3, name: "Required", type: "nvarchar(50)", nullable: false)], primaryKey: ["Id"])
    grid.editingAllowed = { true }; controller.update()
    window.orderFront(nil); controller.view.layoutSubtreeIfNeeded()
    return (controller, grid, window)
  }
  func button(_ id: String, in controller: QueryController) throws -> NSButton {
    try #require(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == id })
  }
  func clickCell(_ column: Int, grid: ResultController, window: NSWindow) throws {
    let rect = grid.table.frameOfCell(atColumn: column, row: 0)
    let point = grid.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    grid.table.mouseDown(with: event)
  }
  func activate(_ button: NSButton) throws {
    #expect(button.isEnabled)
    let action = try #require(button.action)
    #expect(NSApp.sendAction(action, to: button.target, from: button))
  }
  @Test func inlineActionsFitBothThemesWithoutMovingGridAndUntouchedModeCanClose() throws {
    let old = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer { StudioTheme.apply(old ?? "light") }
    let (controller, grid, window) = try editingFixture()
    defer { window.close() }
    let toolbar = try #require(descendants(controller.view).first { $0.accessibilityIdentifier() == "gridToolbar" })
    let actions = try #require(descendants(toolbar).first { $0.accessibilityIdentifier() == "gridDataActions" })
    #expect(actions.superview === toolbar)
    let export = try #require((toolbar as? NSStackView)?.arrangedSubviews.last as? NSPopUpButton)
    #expect(export.accessibilityLabel() == "Sonuçları dışa aktar")
    #expect(!descendants(toolbar).contains { $0.accessibilityIdentifier() == "gridCancelEditing" })
    let pageSize = try #require(descendants(toolbar).compactMap { $0 as? NSPopUpButton }.first { $0.itemArray.contains { $0.tag == -2 } })
    #expect(!pageSize.title.isEmpty && pageSize.title == pageSize.selectedItem?.title)
    #expect(!descendants(toolbar).compactMap { $0 as? NSPopUpButton }.contains { $0.itemTitles.contains("Satırlar") })
    for theme in ["light", "dark"] {
      StudioTheme.apply(theme)
      for width: CGFloat in [830, 1280] {
        window.setContentSize(NSSize(width: width, height: 680))
        controller.view.frame.size = NSSize(width: width, height: 680)
        controller.view.layoutSubtreeIfNeeded()
        let barRect = controller.view.convert(toolbar.bounds, from: toolbar)
        var rects: [NSRect] = []
        for control in descendants(toolbar).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
          let rect = controller.view.convert(control.bounds, from: control)
          #expect(rect.minX >= 0 && rect.maxX <= width + 1, "Overflow: \(control.accessibilityLabel() ?? "") \(rect)")
          #expect(rect.minY >= barRect.minY && rect.maxY <= barRect.maxY + 1)
          if control is StudioToolbarButton {
            #expect(rect.width >= 24 && rect.height >= 26)
            #expect(control.toolTip?.isEmpty == false && control.accessibilityLabel()?.isEmpty == false)
            #expect(!rects.contains { $0.intersects(rect) }, "Overlapping toolbar buttons: \(rect)")
            rects.append(rect)
          }
        }
        if let image = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
          controller.view.cacheDisplay(in: controller.view.bounds, to: image)
          try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/mssql-inline-toolbar-\(theme)-\(Int(width)).png"))
        }
      }
    }
    let originalFrame = controller.view.convert(grid.view.bounds, from: grid.view)
    let cancel = try button("gridEdit", in: controller)
    #expect(cancel.isEnabled && grid.pendingEdits.isEmpty)
    try activate(cancel)
    controller.view.layoutSubtreeIfNeeded()
    #expect(grid.editDefinition == nil && window.attachedSheet == nil)
    #expect(actions.isHidden)
    #expect(controller.view.convert(grid.view.bounds, from: grid.view) == originalFrame)
  }
  @Test func directRowButtonsStageCloneDeleteUndoAndNullWithSelectionGuards() throws {
    let (controller, grid, window) = try editingFixture()
    defer { window.close() }
    let add = try button("gridAddRow", in: controller), clone = try button("gridCloneRow", in: controller)
    let delete = try button("gridDeleteRows", in: controller), undo = try button("gridUndoRows", in: controller)
    let null = try button("gridSetNull", in: controller), preview = try button("gridPreviewChanges", in: controller)
    #expect(add.isEnabled && !clone.isEnabled && !delete.isEnabled && !undo.isEnabled && !null.isEnabled && !preview.isEnabled)
    grid.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    #expect(clone.isEnabled && delete.isEnabled && !undo.isEnabled)
    try activate(clone)
    #expect(grid.pageCount == 3 && grid.pendingEdits[-1]?.values == [nil, "Alpha", "A"])
    #expect(grid.pendingEdits[-1]?.touched == [1, 2])
    #expect(undo.isEnabled && preview.isEnabled)
    try activate(undo)
    #expect(grid.pendingEdits.isEmpty && grid.pageCount == 2)
    try activate(add)
    #expect(grid.pendingEdits[-2]?.touched.isEmpty == true)
    try activate(delete)
    #expect(grid.pendingEdits.isEmpty && grid.pageCount == 2)
    grid.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try activate(delete)
    #expect(grid.pendingEdits[0]?.deleted == true)
    grid.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    #expect(delete.accessibilityLabel() == "Silmeyi geri al")
    try activate(delete)
    #expect(grid.pendingEdits.isEmpty)
    try clickCell(2, grid: grid, window: window)
    #expect(null.isEnabled)
    try activate(null)
    #expect(grid.pendingEdits[0]?.values[1] == nil && preview.isEnabled)
    #expect(try grid.pendingSQL().contains("[Name] = NULL"))
    try activate(undo)
    #expect(grid.pendingEdits.isEmpty)
    try clickCell(3, grid: grid, window: window)
    #expect(!null.isEnabled)
    try clickCell(1, grid: grid, window: window)
    #expect(!null.isEnabled)
    #expect(grid.result.values[0] == ["1", "Alpha", "A"])
  }
  @Test func momentaryToolbarActionsDoNotLeaveSelectedButtons() throws {
    let (controller,grid,window)=try editingFixture()
    defer {window.close()}
    grid.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    for id in ["gridCopyHeaders","gridCloneRow","gridUndoRows","gridAddRow","gridUndoRows"] {
      let action=try button(id,in:controller)
      #expect(action.isEnabled)
      action.state = .on
      #expect(action.sendAction(action.action,to:action.target))
      #expect(action.state == .off)
    }
    let toggle=try button("gridEdit",in:controller)
    #expect(toggle.state == .on)
    #expect(toggle.sendAction(toggle.action,to:toggle.target))
    #expect(toggle.state == .off && grid.editDefinition == nil)
  }
  @Test func untouchedNativeEditorCanExitViaEditingToggle() throws {
    let (controller, grid, window) = try editingFixture()
    defer { window.close() }
    window.makeKeyAndOrderFront(nil)
    grid.table.editColumn(2, row: 0, with: nil, select: true)
    // Native editing is synchronous; yielding here lets another UI suite change the key window.
    #expect((window.firstResponder as? NSTextView)?.string == "Alpha")
    let toggle = try button("gridEdit", in: controller)
    #expect(toggle.isEnabled && toggle.state == .on)
    try activate(toggle)
    #expect(grid.editDefinition == nil && grid.pendingEdits.isEmpty)
    #expect(window.attachedSheet == nil && grid.table.currentEditor() == nil)
    #expect(toggle.state == .off && grid.result.values[0][1] == "Alpha")
  }
  @Test func cancelWithPendingChangesRequiresConfirmationAndKeepsModeWhenDeclined() async throws {
    let (controller, grid, window) = try editingFixture()
    defer { window.close() }
    grid.setEditValue("Changed", row: 0, column: 1)
    let cancel = try button("gridEdit", in: controller)
    try activate(cancel)
    let sheet = try #require(window.attachedSheet)
    #expect(grid.editDefinition != nil && grid.pendingEdits[0]?.values[1] == "Changed")
    window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
    try await Task.sleep(for: .milliseconds(50))
    #expect(grid.editDefinition != nil && !grid.pendingEdits.isEmpty)
    try activate(cancel)
    let confirmed = try #require(window.attachedSheet)
    window.endSheet(confirmed, returnCode: .alertFirstButtonReturn)
    try await Task.sleep(for: .milliseconds(50))
    #expect(grid.editDefinition == nil && grid.pendingEdits.isEmpty)
    #expect(grid.result.values[0][1] == "Alpha")
  }
  @Test func hoverNamesAppearPromptlyAndCancelOnExit() async throws {
    let (controller, _, window) = try editingFixture()
    let help = StudioHoverHelp()
    defer { help.hide(); window.close() }
    let edit = try button("gridEdit", in: controller)
    help.schedule(for: edit)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while help.visibleTitle == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(help.visibleTitle == "Vazgeç ve düzenleme modunu kapat")
    help.hide(for: edit)
    #expect(help.visibleTitle == nil)
    help.schedule(for: edit)
    help.hide(for: edit)
    try await Task.sleep(for: .milliseconds(250))
    #expect(help.visibleTitle == nil)
  }
  @Test func toolsShareOneBarAndSwitchWithResultTabs() throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Toolbar")
    doc.state = .ready
    doc.results = [Rows(fields: [Field("First")], values: [["A"]]), Rows(fields: [Field("Second")], values: [["B"]])]
    let controller = QueryController(document: doc)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    controller.view.frame.size = NSSize(width: 830, height: 680)
    controller.view.layoutSubtreeIfNeeded()
    let views = descendants(controller.view)
    let bar = try #require(views.first { $0.accessibilityIdentifier() == "gridToolbar" })
    let controls = descendants(bar)
    #expect(controls.contains { $0.accessibilityIdentifier() == "gridNavigation" })
    for control in controls.compactMap({ $0 as? NSControl }) where !control.isHidden {
      let rect = controller.view.convert(control.bounds, from: control)
      #expect(rect.minX >= 0 && rect.maxX <= 831, "Toolbar control overflow: \(rect)")
    }
    #expect(controls.contains { $0.accessibilityIdentifier() == "gridRowOptions" })
    #expect(controls.contains { ($0 as? NSPopUpButton)?.itemTitles.contains("Görünen sonuç · CSV…") == true })
    #expect(!views.contains { $0.accessibilityLabel() == "Kolon filtresi" })
    let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
    tabs.selectTabViewItem(withIdentifier: NSNumber(value: 1))
    let second = try #require(controller.children.compactMap { $0 as? ResultController }.first { $0.result.fields.first?.name == "Second" })
    #expect(descendants(bar).contains { $0 === second.toolbar })
    tabs.selectTabViewItem(withIdentifier: "messages")
    #expect(!descendants(bar).contains { $0.accessibilityIdentifier() == "gridNavigation" })
  }
  @Test func bitCellsRemainReadOnlyAndCopyWithHeadersKeepsRawData() throws {
    _ = NSApplication.shared
    let controller = ResultController()
    controller.update(Rows(fields: [Field("Enabled", type: -7)], values: [["1"], ["0"], [nil]]))
    let column = controller.table.tableColumns[1]
    let cell = try #require(column.dataCell as? GridDataCell)
    #expect(cell.isBit && !cell.isEditable && !cell.isSelectable)
    #expect(!controller.responds(to:#selector(NSTableViewDelegate.tableView(_:viewFor:row:))))
    #expect(controller.tableView(controller.table,objectValueFor:column,row:0) as? String == "1")
    #expect(controller.tableView(controller.table,objectValueFor:column,row:1) as? String == "0")
    #expect(controller.tableView(controller.table,objectValueFor:column,row:2) as? String == "NULL")
    controller.table.selectRowIndexes(IndexSet(integersIn: 0...2), byExtendingSelection: false)
    controller.copySelectionData(includeHeaders: true)
    #expect(NSPasteboard.general.string(forType: .string) == "Enabled\n1\n0\nNULL")
  }
  @Test func trueBitPaintsFilledColorAndFalseAndNullStayDistinctInBothThemes() throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(previous ?? "light")}
    let view=NSView(frame:NSRect(x:0,y:0,width:40,height:30)),cell=GridDataCell(textCell:"1")
    cell.isBit=true
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let accent=try #require(StudioTheme.success.usingColorSpace(.deviceRGB))
      func coloredPixels(_ value:String) throws -> Int {
        cell.stringValue=value
        let bitmap=try #require(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:40,pixelsHigh:30,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let context=try #require(NSGraphicsContext(bitmapImageRep:bitmap))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        StudioTheme.canvas.setFill();view.bounds.fill();cell.drawInterior(withFrame:view.bounds,in:view)
        NSGraphicsContext.restoreGraphicsState()
        return (0..<40).reduce(0) {total,x in total+(0..<30).filter {y in
          guard let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else {return false}
          return abs(color.redComponent-accent.redComponent)<0.03 && abs(color.greenComponent-accent.greenComponent)<0.03 && abs(color.blueComponent-accent.blueComponent)<0.03
        }.count}
      }
      #expect(try coloredPixels("1")>70)
      #expect(try coloredPixels("0") == 0 && coloredPixels("NULL") == 0)
      let copy=try #require(cell.copy() as? GridDataCell)
      #expect(copy.isBit && !copy.isEditable && !copy.isSelectable && copy.stringValue == "NULL")
    }
  }
  @Test func scrollingDoesNotReformatRangeAndHeaderShortcutIsConfigurable() throws {
    _ = NSApplication.shared
    let controller = ResultController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    controller.setPageSize(500)
    controller.update(Rows(fields: [Field("N")], values: (0..<10_000).map { [String($0)] }))
    controller.view.layoutSubtreeIfNeeded()
    let label = try #require(descendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "gridRange" })
    let before = label.stringValue
    controller.table.scrollRowToVisible(400)
    controller.view.layoutSubtreeIfNeeded()
    #expect(label.stringValue == before)
    let last = try #require(controller.toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.tag == 3 })
    last.performClick(nil)
    #expect(label.stringValue == "9501–10000 / \(10_000.formatted())")
    let old = UserDefaults.standard.object(forKey: "gridCopyHeadersShortcut")
    defer { if let old { UserDefaults.standard.set(old, forKey: "gridCopyHeadersShortcut") } else { UserDefaults.standard.removeObject(forKey: "gridCopyHeadersShortcut") } }
    UserDefaults.standard.set("option", forKey: "gridCopyHeadersShortcut")
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command,.option], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
    controller.table.keyDown(with: event)
    #expect(NSPasteboard.general.string(forType: .string) == "N\n9500")
  }
}
