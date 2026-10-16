import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct StudioSelectionPickerTests {
  @Test func sharedPickerPreservesBindingAndNativeSelectionAcrossThemes() throws {
    _=NSApplication.shared
    let mode=StudioTheme.mode;defer {StudioTheme.apply(mode)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      var selected=1
      let binding=Binding<Int>(get:{selected},set:{selected=$0})
      let picker=StudioSelectionPicker(title:"Test filtresi",selection:binding,options:[0,1,2],label:{["Tümü","Atanmış","Atanmamış"][$0]})
      let host=NSHostingController(rootView:picker.frame(width:142,height:StudioMetrics.controlHeight))
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:142,height:StudioMetrics.controlHeight));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      defer {window.close()}
      host.view.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      let control=try #require(descendants(host.view).compactMap {$0 as? StudioSelectionPopUpButton}.first)
      #expect(control.indexOfSelectedItem==1 && control.title=="Atanmış")
      control.selectItem(at:2)
      #expect(NSApp.sendAction(try #require(control.action),to:control.target,from:control))
      #expect(selected==2)
      #expect(control.controlSize == .regular && control.bezelStyle == .rounded)
      #expect(control.frame.height>0 && control.frame.height<=StudioMetrics.controlHeight+1)
      let native=StudioSelectionPopUpButton(frame:NSRect(x:0,y:0,width:142,height:26),pullsDown:false)
      native.addItems(withTitles:control.itemTitles);native.selectItem(at:2)
      let image=NSImage(size:native.bounds.size)
      image.lockFocusFlipped(true)
      (NSApp.appearance ?? NSAppearance(named:theme=="dark" ? .darkAqua:.aqua)!).performAsCurrentDrawingAppearance {
        StudioTheme.panel.setFill();native.bounds.fill()
        native.cell?.draw(withFrame:native.bounds,in:native)
      }
      image.unlockFocus()
      let bitmap=try #require(image.tiffRepresentation.flatMap {NSBitmapImageRep(data:$0)})
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-shared-selection-"+theme+".png"))
    }
  }
  @Test func explorerUsesSharedPickerWithoutChangingFilterChoices() throws {
    _=NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false
    let owner=WorkbenchController(state:state);_=owner.view
    #expect(owner.searchOperator.itemTitles==["İçerir","Eşittir","İle başlar","İle biter","İçermez"])
    #expect(owner.searchType.itemTitles==["Tüm nesneler","Tables","Views","Procedures","Functions","Synonyms"])
    #expect(owner.searchOperator.indexOfSelectedItem==0 && owner.searchType.indexOfSelectedItem==0)
    owner.searchOperator.selectItem(at:2);owner.searchType.selectItem(at:3)
    #expect(NSApp.sendAction(try #require(owner.searchOperator.action),to:owner.searchOperator.target,from:owner.searchOperator))
    #expect(owner.searchOperator.indexOfSelectedItem==2 && owner.searchType.indexOfSelectedItem==3)
    #expect(owner.searchOperator.controlSize == .regular && owner.searchType.controlSize == .regular)
  }
}
