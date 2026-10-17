import AppKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct StudioWindowCyclerTests {
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
    let list=cycler.candidates([profiler,main,unrelated,activity])
    #expect(list.count==3 && !list.contains(where:{$0 === unrelated}))
    func event(_ window:NSWindow,_ flags:NSEvent.ModifierFlags)->NSEvent {
      NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
    }
    let first=list[0],second=list[1]

    #expect(cycler.handle(event(first,.control)))
    #expect(activated === second)
    #expect(cycler.handle(event(second,[.control,.shift])))
    #expect(activated === first)
    #expect(!cycler.handle(event(first,.option)))
    let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    sheet.isReleasedWhenClosed=false;first.beginSheet(sheet,completionHandler:nil)
    #expect(!cycler.handle(event(first,.control)))
    first.endSheet(sheet);sheet.close()
  }
}
