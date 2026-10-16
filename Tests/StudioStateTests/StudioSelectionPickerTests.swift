import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct StudioSelectionPickerTests {
  @Test func sharedPickerMatchesOriginalSettingsPickerAcrossThemes() async throws {
    _=NSApplication.shared
    let mode=StudioTheme.mode;defer {StudioTheme.apply(mode)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      var selected=1
      let binding=Binding<Int>(get:{selected},set:{selected=$0})
      let titles=["Tüm atamalar","Atanmış","Atanmamış"]
      let reference=NSHostingView(rootView:Picker("Atama",selection:binding) {
        ForEach(titles.indices,id:\.self) {Text(titles[$0]).tag($0)}
      }.labelsHidden().frame(width:142))
      let shared=NSHostingView(rootView:StudioSelectionPicker(title:"Atama",selection:binding,options:[0,1,2],label:{titles[$0]}).frame(width:142))
      let adapter=StudioSelectionControl();adapter.addItems(withTitles:titles);adapter.selectItem(at:1)
      let stack=NSStackView(views:[reference,shared,adapter]);stack.orientation = .vertical
      let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:160,height:110),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=stack;window.orderFront(nil)
      defer {window.close()}
      try await Task.sleep(for:.milliseconds(100));stack.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      #expect(reference.frame.width==shared.frame.width && reference.frame.height==shared.frame.height)
      #expect(adapter.itemTitles==titles && adapter.indexOfSelectedItem==1)
      let image=try #require(stack.bitmapImageRepForCachingDisplay(in:stack.bounds))
      stack.cacheDisplay(in:stack.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-selection-reference-"+theme+".png"))
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
  }
}
