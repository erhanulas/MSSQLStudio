import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct UnusedDeclarationColorTests {
  private let source="""
  alter function dbo.Calculate(@used int, @unused int)
  returns int as
  begin
    declare @initialized int = case when 1=1 then 0 else 1 end, @local int;
    return @used;
  end;
  """
  private func fixture(_ sql:String)->(EditorController,QueryDocument,NSWindow) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Unused declarations")
    document.sql=sql
    let controller=EditorController(document:document)
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    window.makeFirstResponder(controller.editor)
    return (controller,document,window)
  }
  private func color(_ name:String,controller:EditorController) throws -> NSColor? {
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    let range=(controller.editor.string as NSString).range(of:name)
    #expect(range.location != NSNotFound)
    guard range.location != NSNotFound else {return nil}
    return storage.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor
  }

  @Test func unusedFormalAndLocalNamesAreDimInBothThemesAndPreviews() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    let (controller,document,window)=fixture(source);defer {window.close()}
    let selected=NSRange(location:(source as NSString).range(of:"@unused").location+3,length:0)
    controller.editor.setSelectedRange(selected)
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for name in ["@unused","@initialized","@local"] {
        #expect(try color(name,controller:controller) == StudioTheme.unusedVariable)
        let preview=SQLSourceHighlighting.attributed(source)
        let location=(source as NSString).range(of:name).location
        #expect(preview.attribute(.foregroundColor,at:location,effectiveRange:nil) as? NSColor == StudioTheme.unusedVariable)
      }
      #expect(try color("@used",controller:controller) == StudioTheme.editorText)
      #expect(StudioTheme.unusedVariable != StudioTheme.editorText)
      #expect(controller.editor.selectedRange() == selected)
      #expect(controller.editor.string == source && document.sql == source)
    }
  }

  @Test func addingAndRemovingUsesImmediatelyRecolorsDeclarationsThroughUndoRedo() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let (controller,document,window)=fixture(source);defer {window.close()}
      let editor=controller.editor,undo=try #require(editor.undoManager)
      let location=(source as NSString).range(of:"return @used").location
      let use="set @used=@used+@unused+@local;\n  "
      undo.beginUndoGrouping()
      editor.insertText(use,replacementRange:NSRange(location:location,length:0))
      undo.endUndoGrouping()
      let withUse=editor.string
      #expect(withUse != source && withUse == document.sql)
      for name in ["@unused","@local"] {#expect(try color(name,controller:controller) == StudioTheme.editorText)}
      #expect(try color("@initialized",controller:controller) == StudioTheme.unusedVariable)
      undo.undo()
      #expect(editor.string == source && document.sql == source)
      for name in ["@unused","@local"] {#expect(try color(name,controller:controller) == StudioTheme.unusedVariable)}
      undo.redo()
      #expect(editor.string == withUse && document.sql == withUse)
      for name in ["@unused","@local"] {#expect(try color(name,controller:controller) == StudioTheme.editorText)}
      let inserted=(editor.string as NSString).range(of:use)
      undo.beginUndoGrouping();editor.insertText("",replacementRange:inserted);undo.endUndoGrouping()
      #expect(editor.string == source && document.sql == source)
      for name in ["@unused","@local"] {#expect(try color(name,controller:controller) == StudioTheme.unusedVariable)}
      #expect(editor.textLayoutManager != nil)
    }
  }

  @Test func formattingAndFoldingPreserveUnusedColorsAndHiddenReferences() async throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let (controller,document,window)=fixture(source);defer {window.close()}
      let undo=try #require(controller.editor.undoManager)
      undo.beginUndoGrouping();controller.replaceText(TSQL.format(source));undo.endUndoGrouping()
      #expect(controller.editor.string != source && controller.editor.string == document.sql)
      #expect(try color("@unused",controller:controller) == StudioTheme.unusedVariable)
      #expect(try color("@local",controller:controller) == StudioTheme.unusedVariable)
      #expect(try color("@used",controller:controller) == StudioTheme.editorText)
      undo.undo();#expect(controller.editor.string == source && document.sql == source)
      for _ in 0..<250 {
        if !controller.regions.isEmpty {break}
        try await Task.sleep(for:.milliseconds(20))
      }
      let region=try #require(controller.regions.first)
      controller.toggleFold(region)
      #expect(!controller.editor.string.contains("return @used"))
      #expect(try color("@unused",controller:controller) == StudioTheme.unusedVariable)
      #expect(try color("@used",controller:controller) == StudioTheme.editorText)
      controller.expandAll()
      #expect(controller.editor.string == source && document.sql == source)
      #expect(try color("@unused",controller:controller) == StudioTheme.unusedVariable)
      #expect(try color("@local",controller:controller) == StudioTheme.unusedVariable)
      #expect(controller.editor.textLayoutManager != nil)
    }
  }
}
