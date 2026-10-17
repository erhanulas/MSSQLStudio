import AppKit
import SwiftUI

private final class StudioWindowKeyMonitor {
  let token:Any
  let observer:NSObjectProtocol?
  init(_ token:Any,observer:NSObjectProtocol?) {self.token=token;self.observer=observer}
  deinit {
    NSEvent.removeMonitor(token)
    if let observer {NotificationCenter.default.removeObserver(observer)}
  }
}

/// Presents persistent app windows without capturing their contents or activating during navigation.
@MainActor final class StudioWindowCycler:ObservableObject {
  private weak var main:NSWindow?
  private var monitor:StudioWindowKeyMonitor?
  private weak var source:NSWindow?
  private let activate:(NSWindow)->Void
  @Published private(set) var windows:[NSWindow]=[]
  @Published private(set) var index=0
  private(set) var panel:NSPanel?
  init(main:NSWindow,activate:@escaping (NSWindow)->Void = {window in
    if window.isMiniaturized {window.deminiaturize(nil)}
    window.makeKeyAndOrderFront(nil)
  }) {
    self.main=main;self.activate=activate
    let token=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged,.leftMouseDown,.rightMouseDown]) { [weak self] event in
      let handled=MainActor.assumeIsolated {self?.handle(event)==true}
      return handled ? nil:event
    }
    let observer=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
      MainActor.assumeIsolated {self?.dismiss()}
    }
    if let token {monitor=StudioWindowKeyMonitor(token,observer:observer)}
  }
  func candidates(_ windows:[NSWindow])->[NSWindow] {
    windows.filter {
      ($0 === main || $0 is StudioAssociatedWindow) && ($0.isVisible || $0.isMiniaturized)
        && $0.canBecomeKey && $0.sheetParent==nil && $0.level == .normal
        && !$0.styleMask.contains(.nonactivatingPanel)
    }.sorted {$0.windowNumber<$1.windowNumber}
  }
  func dismiss() {
    panel?.orderOut(nil);panel?.contentViewController=nil;panel=nil;windows=[];index=0;source=nil
  }
  func accept(_ selected:Int?=nil) {
    let chosen=selected ?? index
    guard windows.indices.contains(chosen) else {dismiss();return}
    let window=windows[chosen]
    let valid=candidates(NSApp.windows).contains {$0 === window} && window.attachedSheet==nil
    dismiss()
    if valid {activate(window)}
  }
  private func move(_ delta:Int) {
    guard !windows.isEmpty else {return}
    index=(index+delta+windows.count)%windows.count
  }
  private func present(from current:NSWindow,backwards:Bool) {
    windows=candidates(NSApp.windows)
    guard windows.count>1,let initial=windows.firstIndex(where:{$0 === current}) else {windows=[];return}
    source=current
    index=(initial+(backwards ? windows.count-1:1))%windows.count
    let height=min(560,CGFloat(windows.count)*56+100)
    let popup=NSPanel(contentRect:NSRect(x:0,y:0,width:480,height:height),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    popup.isReleasedWhenClosed=false;popup.hasShadow=true;popup.isOpaque=true
    popup.backgroundColor=StudioTheme.panel;popup.level = .floating
    popup.contentViewController=NSHostingController(rootView:StudioWindowSwitcherView(model:self))
    let screen=current.screen?.visibleFrame ?? current.frame
    popup.setFrameOrigin(NSPoint(x:screen.midX-240,y:screen.midY-height/2))
    panel=popup;popup.orderFront(nil)
  }
  func handle(_ event:NSEvent)->Bool {
    let flags=event.modifierFlags.intersection([.command,.control,.option,.shift])
    if panel != nil {
      guard let source,source.attachedSheet==nil,NSApp.modalWindow==nil else {dismiss();return false}
      if event.type == .leftMouseDown || event.type == .rightMouseDown {
        if event.window !== panel {dismiss()}
        return false
      }
      if event.type == .flagsChanged {
        if !flags.contains(.control) {accept()}
        return false
      }
      guard event.type == .keyDown else {return false}
      switch event.keyCode {
      case 53:dismiss()
      case 36,76:accept()
      case 48:move(flags.contains(.shift) ? -1:1)
      case 123,126:move(-1)
      case 124,125:move(1)
      default:dismiss();return false
      }
      return true
    }
    guard event.type == .keyDown,event.keyCode==48,flags == .control || flags == [.control,.shift],
      NSApp.modalWindow==nil,let current=event.window,current.attachedSheet==nil,
      (current as? StudioPanelWindow)?.activePopover?.isShown != true else {return false}
    present(from:current,backwards:flags.contains(.shift))
    return panel != nil
  }
}

private struct StudioWindowSwitcherView:View {
  @ObservedObject var model:StudioWindowCycler
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        Label("Açık pencereler",systemImage:"macwindow.on.rectangle").font(.system(size:16,weight:.semibold))
        Spacer()
        Text("\(model.windows.count)").font(.system(size:12)).foregroundStyle(Color(nsColor:StudioTheme.muted))
      }
      ScrollViewReader {proxy in
        ScrollView {
          LazyVStack(spacing:4) {
            ForEach(Array(model.windows.enumerated()),id:\.element.windowNumber) {position,window in
              Button {model.accept(position)} label:{
                HStack(spacing:12) {
                  Image(systemName:window.isMiniaturized ? "macwindow.badge.plus":"macwindow")
                    .font(.system(size:20)).foregroundStyle(Color(nsColor:StudioTheme.accent)).frame(width:32)
                  VStack(alignment:.leading,spacing:3) {
                    Text(window.title.isEmpty ? "MSSQL Studio":window.title).font(.system(size:12,weight:.medium)).lineLimit(1)
                    Text(window.isMiniaturized ? "Küçültülmüş":"Açık pencere").font(.system(size:10)).foregroundStyle(Color(nsColor:StudioTheme.muted))
                  }
                  Spacer(minLength:4)
                  if position==model.index {Image(systemName:"checkmark.circle.fill").foregroundStyle(Color(nsColor:StudioTheme.accent))}
                }.padding(.horizontal,12).frame(height:52).contentShape(Rectangle())
                  .background(position==model.index ? Color(nsColor:StudioTheme.selection):Color.clear,in:RoundedRectangle(cornerRadius:8))
                  .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(position==model.index ? Color(nsColor:StudioTheme.accent):Color.clear,lineWidth:1))
              }.buttonStyle(.plain).id(position)
                .accessibilityAddTraits(position==model.index ? .isSelected:[])
            }
          }
        }.onAppear {proxy.scrollTo(model.index,anchor:.center)}
          .onChange(of:model.index) {_,value in proxy.scrollTo(value,anchor:.center)}
      }
      Text("⌃ bırak / ↩ · Aç     Tab / ⇧ Tab · İlerle     ↑ ↓ · Seç     esc · Vazgeç")
        .font(.system(size:10)).foregroundStyle(Color(nsColor:StudioTheme.muted))
    }.padding(16).background(Color(nsColor:StudioTheme.panel)).foregroundStyle(Color(nsColor:StudioTheme.text))
      .accessibilityIdentifier("studioWindowSwitcher")
  }
}
