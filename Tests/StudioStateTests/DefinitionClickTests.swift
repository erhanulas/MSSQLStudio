import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DefinitionClickTests {
  private func click(_ view:NSTextView,point:NSPoint)throws {
    let location=view.convert(point,to:nil)
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:location,modifierFlags:.command,timestamp:0,windowNumber:view.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    view.mouseDown(with:event)
  }
  @Test func commandClickUsesTheClickedGlyphInsteadOfTheOldSelection() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Click")
    doc.server.online=false
    doc.sql="SELECT * FROM dbo.First;\nSELECT * FROM [dbo].[Second_Long_Object] AS s;\nSELECT 'dbo.First';"
    let controller=EditorController(document:doc),window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:950,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    var opened:[[String]]=[];doc.openDefinitionNamed={opened.append($0)}
    var selections=0;controller.editor.mouseSelectionEnded={selections+=1}
    let range=(controller.editor.string as NSString).range(of:"[Second_Long_Object]")
    let rect=try #require(controller.editor.rects(forCharacterRange:range)?.first?.rectValue)
    for point in [NSPoint(x:rect.minX+1,y:rect.midY),NSPoint(x:rect.midX,y:rect.minY+1),NSPoint(x:rect.maxX-1,y:rect.maxY-1)] {
      controller.editor.setSelectedRange(NSRange(location:0,length:6))
      try click(controller.editor,point:point)
    }
    #expect(opened==Array(repeating:["dbo","Second_Long_Object"],count:3) && selections==0)
    try click(controller.editor,point:NSPoint(x:rect.maxX+180,y:rect.midY))
    let literal=(controller.editor.string as NSString).range(of:"'dbo.First'")
    let literalRect=try #require(controller.editor.rects(forCharacterRange:literal)?.first?.rectValue)
    try click(controller.editor,point:NSPoint(x:literalRect.midX,y:literalRect.midY))
    #expect(opened.count==3 && doc.lastExecutedSQL==nil)
  }
  @Test func foldedSourceAndReadonlyPreviewNavigateVisibleObjects() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Folded")
    doc.server.online=false;doc.sql="IF 1=1\nBEGIN\n SELECT 1;\nEND\nSELECT * FROM dbo.Target;"
    let controller=EditorController(document:doc),window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:950,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {window.close()}
    controller.toggleFold(try #require(controller.regions.first))
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    var opened:[[String]]=[];doc.openDefinitionNamed={opened.append($0)}
    let range=(controller.editor.string as NSString).range(of:"Target")
    let rect=try #require(controller.editor.rects(forCharacterRange:range)?.first?.rectValue)
    try click(controller.editor,point:NSPoint(x:rect.midX,y:rect.midY))
    #expect(opened==[["dbo","Target"]] && controller.editor.string != doc.sql)
    controller.navigateDefinition()
    #expect(opened.count==2 && doc.sql.contains("SELECT 1;"))
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:950,height:400))
    window.contentView=preview;preview.display("SELECT * FROM [dbo].[Target];");preview.layoutSubtreeIfNeeded()
    preview.navigateDefinition={opened.append($0)}
    let token=(preview.textView.string as NSString).range(of:"Target")
    let screenRect=preview.textView.firstRect(forCharacterRange:token,actualRange:nil)
    let windowRect=window.convertFromScreen(screenRect)
    let point=preview.textView.convert(NSPoint(x:windowRect.midX,y:windowRect.midY),from:nil)
    try click(preview.textView,point:point)
    #expect(opened.count==3 && opened.last==["dbo","Target"])
  }
}
