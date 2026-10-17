import AppKit

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
@MainActor final class StudioWindowCycler {
  private weak var main:NSWindow?
  private var monitor:StudioWindowKeyMonitor?
  private weak var source:NSWindow?
  private let activate:(NSWindow)->Void
  private(set) var windows:[NSWindow]=[]
  private(set) var index=0
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
    panel?.orderOut(nil);panel?.contentViewController=nil;panel?.contentView=nil;panel=nil;windows=[];index=0;source=nil
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
    select((index+delta+windows.count)%windows.count,reveal:true)
  }
  func select(_ position:Int,reveal:Bool=false) {
    guard windows.indices.contains(position) else {return}
    index=position
    (panel?.contentView as? StudioWindowSwitcherView)?.updateSelection(position,reveal:reveal)
  }
  func entry(for window:NSWindow)->StudioWindowSwitcherView.Entry {
    let role=(window as? StudioAssociatedWindow)?.framePersistenceRole ?? ""
    let type:String,symbol:String
    switch role {
    case "detachedQuery":type="SQL sorgusu";symbol="doc.text"
    default:
      let identity=window.identifier?.rawValue ?? ""
      if window === main {type="Çalışma alanı";symbol="rectangle.split.2x1"}
      else if identity.hasPrefix("activity|") {type="Activity Monitor";symbol="waveform.path.ecg"}
      else if window is ProfilerWindow {type="SQL Profiler";symbol="list.bullet.rectangle"}
      else if identity.hasPrefix("history") {type="Sorgu geçmişi";symbol="clock.arrow.circlepath"}
      else if identity.hasPrefix("favorites") {type="Favori sorgular";symbol="star"}
      else if identity.hasPrefix("files|") {type="Veritabanı dosyaları";symbol="externaldrive"}
      else {type="Araç penceresi";symbol="macwindow"}
    }
    let raw=window.title.trimmingCharacters(in:.whitespacesAndNewlines)
    let title=raw.isEmpty ? type:raw
    var context=window.subtitle
    if window === main,let workbench=window.contentViewController as? WorkbenchController,let doc=workbench.state.active {
      context="\(doc.title) · \(doc.server.profile.name) / \(doc.database)"
    }
    let status=window.isMiniaturized ? "Küçültülmüş":window === source ? "Şu an açık":"Açık"
    return .init(title:title,context:context.isEmpty ? type:context,type:type,symbol:symbol,status:status)
  }
  private func present(from current:NSWindow,backwards:Bool) {
    windows=candidates(NSApp.windows)
    guard windows.count>1,let initial=windows.firstIndex(where:{$0 === current}) else {windows=[];return}
    source=current
    index=(initial+(backwards ? windows.count-1:1))%windows.count
    let screen=current.screen?.visibleFrame ?? current.frame
    let width=min(620,max(360,screen.width-48))
    let height=min(min(640,screen.height-48),CGFloat(windows.count)*76+160)
    let popup=NSPanel(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    popup.isReleasedWhenClosed=false;popup.hasShadow=true;popup.isOpaque=false
    popup.backgroundColor = .clear;popup.level = .floating
    let content=StudioWindowSwitcherView(entries:windows.map {entry(for:$0)},selected:index,
      select:{ [weak self] in self?.select($0) },accept:{ [weak self] in self?.accept($0) })
    popup.contentView=content
    popup.setFrameOrigin(NSPoint(x:screen.midX-width/2,y:screen.midY-height/2))
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
