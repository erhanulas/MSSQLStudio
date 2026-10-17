import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct StudioSelectionPickerTests {
  @Test func sharedActionMenuSupportsOptionalIconAndDisabledChoices() throws {
    _=NSApplication.shared
    var invoked=0
    let menu=StudioSelectionMenu(title:"Export",symbol:"square.and.arrow.up",items:[
      .init(title:"Selected",enabled:false,action:{invoked+=10}),
      .init(title:"All",action:{invoked+=1})
    ])
    let host=NSHostingView(rootView:menu.frame(width:142,height:28))
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:180,height:50),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer {window.close()}
    host.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let control=try #require(children(host).compactMap {$0 as? StudioSelectionControl}.first)
    #expect(control.pullsDown && control.leadingSymbol=="square.and.arrow.up")
    #expect(control.itemTitles==["Export","Selected","All"] && control.item(at:1)?.isEnabled==false)
    control.selectItem(at:1)
    #expect(NSApp.sendAction(try #require(control.action),to:control.target,from:control))
    #expect(invoked==0)
    control.selectItem(at:2)
    #expect(NSApp.sendAction(try #require(control.action),to:control.target,from:control))
    #expect(invoked==1)
    #expect(StudioSelectionControl().leadingSymbol==nil)
  }
  @Test func sharedPickerAndExplorerFillEqualWidthSlotsAcrossThemes() async throws {
    _=NSApplication.shared
    let mode=StudioTheme.mode;defer {StudioTheme.apply(mode)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      var selected=1
      let binding=Binding<Int>(get:{selected},set:{selected=$0})
      let titles=["Tüm atamalar","Atanmış","Atanmamış"]
      let shared=NSHostingView(rootView:StudioSelectionPicker(title:"Atama",selection:binding,options:[0,1,2],label:{titles[$0]}).frame(width:142))
      let adapter=StudioSelectionControl();adapter.addItems(withTitles:titles);adapter.selectItem(at:1)
      let second=StudioSelectionControl();second.addItems(withTitles:["İçerir","Eşittir"])
      let row=NSStackView(views:[adapter,second]);row.distribution = .fillEqually;row.spacing=4
      let stack=NSStackView(views:[shared,row]);stack.orientation = .vertical
      row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
      row.heightAnchor.constraint(equalToConstant:StudioMetrics.controlHeight).isActive=true
      let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:160,height:110),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=stack;window.orderFront(nil)
      defer {window.close()}
      try await Task.sleep(for:.milliseconds(100));stack.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      #expect(abs(adapter.frame.width-second.frame.width)<1)
      #expect(adapter.itemTitles==titles && adapter.indexOfSelectedItem==1)
      let boundControl=try #require(descendants(shared).compactMap {$0 as? StudioSelectionControl}.first)
      boundControl.selectItem(at:2)
      #expect(NSApp.sendAction(try #require(boundControl.action),to:boundControl.target,from:boundControl))
      #expect(selected==2)
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
    owner.showExplorerSearch(true)
    owner.searchOperator.selectItem(at:2);owner.searchType.selectItem(at:3)
    #expect(NSApp.sendAction(try #require(owner.searchOperator.action),to:owner.searchOperator.target,from:owner.searchOperator))
    #expect(owner.searchOperator.indexOfSelectedItem==2 && owner.searchType.indexOfSelectedItem==3)
    #expect(owner.showingSearch && owner.explorerTabs.selectedSegment==1 && !owner.searchFilters.isHidden)
  }
}
