import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorCaretNavigationTests {
  private func fixture(_ sql:String)->(EditorController,QueryDocument,NSWindow) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Caret navigation")
    document.sql=sql
    let controller=EditorController(document:document)
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeFirstResponder(controller.editor)
    return (controller,document,window)
  }
  private func arrow(_ editor:SQLTextView,right:Bool,flags:NSEvent.ModifierFlags) throws {
    let key=right ? "\u{f703}":"\u{f702}"
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:editor.window?.windowNumber ?? 0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:right ? 124:123))
    editor.keyDown(with:event)
  }
  @Test func rectangularSelectionExtendsEveryLineAndIndentsWithOneUndo() throws {
    let sql="    AA\n    BB\n    CC"
    let (controller,document,window)=fixture(sql);defer {window.close()}
    let editor=controller.editor
    editor.setSelectedRanges([5,12,19].map {NSValue(range:NSRange(location:$0,length:1))},affinity:.upstream,stillSelecting:false)
    #expect(editor.selectedRanges.count == 3)
    try arrow(editor,right:false,flags:[.command,.shift])
    #expect(editor.selectedRanges.map(\.rangeValue) == [4,11,18].map {NSRange(location:$0,length:2)})
    try arrow(editor,right:false,flags:[.command,.shift])
    #expect(editor.selectedRanges.map(\.rangeValue) == [0,7,14].map {NSRange(location:$0,length:6)})
    #expect(document.sql == sql)
    let undo=try #require(editor.undoManager);undo.groupsByEvent=false
    editor.insertTab(nil)
    #expect(editor.string == "\t    AA\n\t    BB\n\t    CC" && document.sql == editor.string)
    undo.undo();#expect(editor.string == sql && document.sql == sql)
  }
  @Test func disjointSelectionsUnindentOnlySelectedLines() throws {
    let sql="    AA\n    BB\n    CC"
    let (controller,document,window)=fixture(sql);defer {window.close()}
    let editor=controller.editor,undo=try #require(controller.editor.undoManager)
    undo.groupsByEvent=false
    editor.setSelectedRanges([4,18].map {NSValue(range:NSRange(location:$0,length:1))},affinity:.downstream,stillSelecting:false)
    editor.insertBacktab(nil)
    #expect(editor.string == "AA\n    BB\nCC" && document.sql == editor.string)
    undo.undo();#expect(editor.string == sql)
  }
  @Test func wordNavigationStopsAtSQLPrefixesAndOperators() throws {
    let (controller,document,window)=fixture("    @PARAM >= @OTHER + 12;")
    defer {window.close()}
    let editor=controller.editor,source=editor.string as NSString
    let parameter=source.range(of:"@PARAM"),comparison=source.range(of:">="),other=source.range(of:"@OTHER")
    editor.setSelectedRange(NSRange(location:NSMaxRange(parameter),length:0))
    try arrow(editor,right:false,flags:.option)
    #expect(editor.selectedRange().location == parameter.location)
    try arrow(editor,right:true,flags:.option)
    #expect(editor.selectedRange().location == NSMaxRange(parameter))
    try arrow(editor,right:true,flags:.option)
    #expect(editor.selectedRange().location == NSMaxRange(comparison))
    try arrow(editor,right:true,flags:.option)
    #expect(editor.selectedRange().location == NSMaxRange(other))
    try arrow(editor,right:false,flags:.option)
    #expect(editor.selectedRange().location == other.location)
    try arrow(editor,right:false,flags:.option)
    #expect(editor.selectedRange().location == comparison.location)
    #expect(editor.string == source as String && document.sql == editor.string)
    #expect(document.selectedRange == editor.selectedRange() && editor.textLayoutManager != nil)
  }
  @Test func commandArrowsRespectCodeEdgesBeforeWhitespace() throws {
    let (controller,document,window)=fixture("SELECT 1;\r\n\t  @PARAM = 1;   \r\nSELECT 2;")
    defer {window.close()}
    let editor=controller.editor,source=editor.string as NSString
    let parameter=source.range(of:"@PARAM"),line=source.lineRange(for:parameter)
    let end=source.range(of:"1;   ",options:[],range:line).location+2
    editor.setSelectedRange(NSRange(location:parameter.location+3,length:0))
    try arrow(editor,right:false,flags:.command);#expect(editor.selectedRange().location == parameter.location)
    try arrow(editor,right:false,flags:.command);#expect(editor.selectedRange().location == line.location)
    try arrow(editor,right:true,flags:.command);#expect(editor.selectedRange().location == end)
    try arrow(editor,right:true,flags:.command);#expect(editor.selectedRange().location == NSMaxRange(line)-2)
    #expect(editor.string == source as String && document.sql == editor.string)
  }
  @Test func shiftNavigationKeepsTheAnchorAcrossDirectionChanges() throws {
    let (controller,document,window)=fixture("@A+@B")
    defer {window.close()}
    let editor=controller.editor
    editor.setSelectedRange(NSRange(location:3,length:0))
    for (right,expected) in [(true,NSRange(location:3,length:2)),(false,NSRange(location:3,length:0)),(false,NSRange(location:2,length:1)),(false,NSRange(location:0,length:3)),(true,NSRange(location:2,length:1)),(true,NSRange(location:3,length:0)),(true,NSRange(location:3,length:2))] {
      try arrow(editor,right:right,flags:[.option,.shift])
      #expect(editor.selectedRange() == expected)
      #expect(document.selectedRange == expected)
    }
    editor.setSelectedRange(NSRange(location:3,length:2),affinity:.upstream,stillSelecting:false)
    try arrow(editor,right:false,flags:[.option,.shift]);#expect(editor.selectedRange() == NSRange(location:2,length:3))
    editor.setSelectedRange(NSRange(location:3,length:2),affinity:.downstream,stillSelecting:false)
    try arrow(editor,right:false,flags:[.option,.shift]);#expect(editor.selectedRange() == NSRange(location:3,length:0))
    #expect(editor.string == "@A+@B" && document.sql == editor.string)
  }
  @Test func selectedTextCollapsesAndResponderActionsUseSQLBoundaries() throws {
    let (controller,_,window)=fixture("    @A += @@SPID, #Temp.Table_Name   ")
    defer {window.close()}
    let editor=controller.editor,source=editor.string as NSString
    let variable=source.range(of:"@@SPID")
    editor.setSelectedRange(variable)
    editor.moveWordBackward(nil);#expect(editor.selectedRange() == NSRange(location:variable.location,length:0))
    editor.moveWordBackward(nil);#expect(editor.selectedRange().location == source.range(of:"+=").location)
    editor.moveWordForward(nil);#expect(editor.selectedRange().location == NSMaxRange(source.range(of:"+=")))
    editor.moveToBeginningOfLine(nil);#expect(editor.selectedRange().location == 4)
    editor.moveToLeftEndOfLine(nil);#expect(editor.selectedRange().location == 0)
    editor.moveToEndOfLine(nil);#expect(editor.selectedRange().location == source.length-3)
    editor.moveToRightEndOfLine(nil);#expect(editor.selectedRange().location == source.length)
  }
  @Test func commandShiftSelectionKeepsAnchorAcrossCodeAndPhysicalEdges() throws {
    let (controller,document,window)=fixture("\t  @PARAM = 1;   ")
    defer {window.close()}
    let editor=controller.editor,source=editor.string as NSString
    let anchor=source.range(of:"@PARAM").location+3,codeEnd=source.length-3
    editor.setSelectedRange(NSRange(location:anchor,length:0))
    try arrow(editor,right:false,flags:[.command,.shift]);#expect(editor.selectedRange() == NSRange(location:3,length:anchor-3))
    try arrow(editor,right:false,flags:[.command,.shift]);#expect(editor.selectedRange() == NSRange(location:0,length:anchor))
    try arrow(editor,right:true,flags:[.command,.shift]);#expect(editor.selectedRange() == NSRange(location:anchor,length:codeEnd-anchor))
    try arrow(editor,right:true,flags:[.command,.shift]);#expect(editor.selectedRange() == NSRange(location:anchor,length:source.length-anchor))
    #expect(document.selectedRange == editor.selectedRange() && document.sql == source as String)
  }
  @Test func unicodeWordsAndPlainCharacterArrowsKeepComposedCharactersIntact() throws {
    let (controller,document,window)=fixture("  @İsim_değeri + e\u{301} 👩🏽‍💻;")
    defer {window.close()}
    let editor=controller.editor,source=editor.string as NSString
    let variable=source.range(of:"@İsim_değeri"),accent=source.range(of:"e\u{301}"),emoji=source.range(of:"👩🏽‍💻")
    editor.setSelectedRange(NSRange(location:NSMaxRange(variable),length:0))
    try arrow(editor,right:false,flags:.option);#expect(editor.selectedRange().location == variable.location)
    editor.setSelectedRange(NSRange(location:NSMaxRange(accent),length:0))
    try arrow(editor,right:false,flags:.option);#expect(editor.selectedRange().location == accent.location)
    try arrow(editor,right:true,flags:.option);#expect(editor.selectedRange().location == NSMaxRange(accent))
    try arrow(editor,right:true,flags:.option);#expect(editor.selectedRange().location == NSMaxRange(emoji))
    try arrow(editor,right:false,flags:[]);#expect(editor.selectedRange().location == emoji.location)
    #expect(document.sql == source as String && editor.textLayoutManager != nil)
  }
  @Test func caretMovementKeepsSQLColorsAndSeparateUndoSteps() throws {
    let (controller,document,window)=fixture("SELECT ")
    defer {window.close()}
    let editor=controller.editor,manager=try #require(editor.undoManager)
    manager.groupsByEvent=false;defer {manager.groupsByEvent=true}
    manager.removeAllActions()
    editor.setSelectedRange(NSRange(location:7,length:0))
    manager.beginUndoGrouping();editor.insertText("@PARAM",replacementRange:editor.selectedRange());manager.endUndoGrouping()
    try arrow(editor,right:false,flags:.option)
    manager.beginUndoGrouping();editor.insertText("X",replacementRange:editor.selectedRange());manager.endUndoGrouping()
    #expect(editor.string == "SELECT X@PARAM" && document.sql == editor.string)
    editor.undoSQL(nil);#expect(editor.string == "SELECT @PARAM" && document.sql == editor.string)
    editor.undoSQL(nil);#expect(editor.string == "SELECT " && document.sql == editor.string)
    editor.redoSQL(nil);editor.redoSQL(nil);#expect(editor.string == "SELECT X@PARAM" && document.sql == editor.string)
    #expect(editor.textContentStorage?.textStorage?.attribute(.foregroundColor,at:1,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
  }
  @Test func navigationThroughFoldedDisplayPreservesSourceAndMappedSelection() throws {
    let sql="BEGIN\n    SELECT @PARAM >= 12;\nEND\nSELECT @@SPID + 1;"
    let (controller,document,window)=fixture(sql)
    defer {window.close()}
    let editor=controller.editor
    editor.setSelectedRange(NSRange(location:0,length:0));controller.toggleCurrentFold()
    let display=editor.string as NSString,variable=display.range(of:"@@SPID")
    #expect(editor.string != sql && variable.location != NSNotFound)
    editor.setSelectedRange(NSRange(location:NSMaxRange(variable),length:0))
    try arrow(editor,right:false,flags:.option)
    #expect(editor.selectedRange().location == variable.location)
    #expect(document.selectedRange.location == (sql as NSString).range(of:"@@SPID").location)
    try arrow(editor,right:true,flags:[.option,.shift])
    #expect(editor.selectedRange() == variable && editor.sourceCopy?() == "@@SPID")
    #expect(document.sql == sql && editor.string == display as String && editor.textLayoutManager != nil)
  }
}
