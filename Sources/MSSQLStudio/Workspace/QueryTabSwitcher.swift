import AppKit
import SwiftUI

private final class TabSwitcherMonitor {
  let token:Any
  init(_ token:Any) {self.token=token}
  deinit {NSEvent.removeMonitor(token)}
}

@MainActor final class QueryTabSwitcher:NSObject,ObservableObject {
  struct Entry:Identifiable {
    let id:UUID
    let title:String
    let context:String
    let sql:String
    let pinned:Bool
    let modified:Bool
  }
  @Published private(set) var entries:[Entry]=[]
  @Published private(set) var index=0
  private weak var owner:WorkbenchController?
  private weak var sourceWindow:NSWindow?
  private var monitor:TabSwitcherMonitor?
  private(set) var panel:NSPanel?
  private var lastHoverLocation=NSEvent.mouseLocation
  private var originalTabOrigin:NSPoint?
  private var releaseFlags:NSEvent.ModifierFlags=[]
  init(owner:WorkbenchController) {self.owner=owner;super.init()}
  func install() {
    guard monitor==nil else {return}
    if let token=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged,.leftMouseDown,.rightMouseDown],handler:{ [weak self] event in
      let consumed=MainActor.assumeIsolated {self?.handle(event)==true}
      return consumed ? nil:event
    }) {monitor=TabSwitcherMonitor(token)}
    for name in [NSApplication.didResignActiveNotification,NSWindow.willCloseNotification,NSWindow.didResignKeyNotification] {
      NotificationCenter.default.addObserver(self,selector:#selector(windowChanged(_:)),name:name,object:nil)
    }
  }
  @objc private func windowChanged(_ note:Notification) {
    if note.name==NSApplication.didResignActiveNotification || (note.object as? NSWindow) === sourceWindow {dismiss(commit:false)}
  }
  @discardableResult func handle(_ event:NSEvent)->Bool {
    if panel != nil {
      if event.type == .flagsChanged {
        if !event.modifierFlags.isSuperset(of:releaseFlags) {dismiss(commit:true)}
        return false
      }
      if event.type == .leftMouseDown || event.type == .rightMouseDown {
        if event.window !== panel {dismiss(commit:false)}
        return false
      }
      guard event.type == .keyDown,event.window === sourceWindow || event.window === panel else {return false}
      switch event.keyCode {
      case 53:dismiss(commit:false)
      case 36,76:dismiss(commit:true)
      case 48:advance(event.modifierFlags.contains(.shift) ? -1:1)
      case 123:advance(-1)
      case 124:advance(1)
      case 126:advance(-3)
      case 125:advance(3)
      default:
        if event.modifierFlags.contains(.command) {dismiss(commit:false);return false}
        return true
      }
      return true
    }
    guard event.type == .keyDown,let owner,let window=event.window,
      window === owner.view.window || owner.detached.values.contains(where:{$0.window === window}),
      window.attachedSheet==nil,NSApp.modalWindow==nil else {return false}
    let binding=GridShortcuts.binding(.tabSwitcher)
    var flags=event.modifierFlags.intersection([.command,.option,.control,.shift])
    flags.remove(.shift)
    var expected=binding.flags;expected.remove(.shift)
    let key=event.keyCode==48 ? "\t":GridShortcuts.eventKey(event)
    guard !binding.key.isEmpty,key==binding.key,flags==expected else {return false}
    present(in:window,backwards:event.modifierFlags.contains(.shift),held:expected.intersection([.command,.option,.control]))
    return true
  }
  func present(in window:NSWindow,backwards:Bool=false,held:NSEvent.ModifierFlags = .option) {
    guard panel==nil,let owner,owner.state.documents.count>1 else {return}
    entries=owner.state.documents.map {doc in
      Entry(id:doc.id,title:doc.title,context:doc.server.profile.name+" / "+doc.database,
        sql:String(doc.sql.prefix(1600).split(separator:"\n",omittingEmptySubsequences:false).prefix(7).joined(separator:"\n")),pinned:doc.pinned,modified:doc.needsCloseConfirmation)
    }
    index=entries.firstIndex(where:{$0.id==owner.state.active?.id}) ?? 0
    releaseFlags=held;sourceWindow=window
    lastHoverLocation=NSEvent.mouseLocation
    originalTabOrigin=owner.tabs.enclosingScrollView?.contentView.bounds.origin
    advance(backwards ? -1:1)
    let panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.level = .floating
    panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
    let host=NSHostingController(rootView:QueryTabSwitcherView(model:self));host.sizingOptions=[];panel.contentViewController=host
    let rows=min(5,(entries.count+2)/3)
    let size=NSSize(width:min(760,window.frame.width-48),height:min(CGFloat(rows)*40+240,window.frame.height-80))
    panel.setFrame(NSRect(x:window.frame.midX-size.width/2,y:window.frame.midY-size.height/2,width:size.width,height:size.height),display:true)
    self.panel=panel;window.addChildWindow(panel,ordered:.above);panel.orderFront(nil);refreshHighlight()
  }
  var acceptanceHint:String {releaseFlags.isEmpty ? "↩ · Aç":"Tuşu bırak · Aç"}
  var previewID:UUID? {panel != nil && entries.indices.contains(index) ? entries[index].id:nil}
  func refreshHighlight() {
    guard let owner else {return}
    for surface in owner.tabs.arrangedSubviews.compactMap({$0 as? QueryTabSurface}) {
      let selected=surface.primaryButton?.document?.id==previewID && previewID != nil
      if surface.isSwitchPreview != selected {surface.isSwitchPreview=selected}
      if selected {surface.scrollToVisible(surface.bounds)}
    }
  }
  func advance(_ delta:Int) {
    guard !entries.isEmpty else {return}
    lastHoverLocation=NSEvent.mouseLocation
    index=(index+delta%entries.count+entries.count)%entries.count;refreshHighlight()
  }
  func previewFromHover(_ id:UUID) {
    let point=NSEvent.mouseLocation
    guard hypot(point.x-lastHoverLocation.x,point.y-lastHoverLocation.y)>0.5 else {return}
    lastHoverLocation=point;preview(id)
  }
  func preview(_ id:UUID) {
    guard let value=entries.firstIndex(where:{$0.id==id}),value != index else {return}
    index=value;refreshHighlight()
  }
  func choose(_ id:UUID) {if let value=entries.firstIndex(where:{$0.id==id}) {index=value;dismiss(commit:true)}}
  func dismiss(commit:Bool) {
    guard let panel else {return}
    let id=entries.indices.contains(index) ? entries[index].id:nil
    sourceWindow?.removeChildWindow(panel);panel.orderOut(nil);self.panel=nil;sourceWindow=nil
    refreshHighlight()
    if !commit,let origin=originalTabOrigin,let scroll=owner?.tabs.enclosingScrollView {
      let bounds=scroll.contentView.constrainBoundsRect(NSRect(origin:origin,size:scroll.contentView.bounds.size))
      scroll.contentView.scroll(to:bounds.origin);scroll.reflectScrolledClipView(scroll.contentView)
    }
    originalTabOrigin=nil
    if commit,let id,let owner,let document=owner.state.documents.first(where:{$0.id==id}) {
      owner.activateQueryTab(document)
      if let detached=owner.detached[id] {detached.showWindow(nil);detached.window?.makeKeyAndOrderFront(nil)}
      else {owner.view.window?.makeKeyAndOrderFront(nil)}
    }
    entries=[]
  }
}

private struct QueryTabSwitcherView:View {
  @ObservedObject var model:QueryTabSwitcher
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var selected:QueryTabSwitcher.Entry? {model.entries.indices.contains(model.index) ? model.entries[model.index]:nil}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        Label("Açık sekmeler",systemImage:"square.stack").font(.system(size:16,weight:.semibold))
        Spacer()
        Text("\(model.index+1) / \(model.entries.count)").monospacedDigit().foregroundStyle(.secondary)
      }
      ScrollViewReader {proxy in
        ScrollView {
          LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
            ForEach(model.entries) {entry in
              let active=entry.id==selected?.id
              Button {model.choose(entry.id)} label:{
                HStack(spacing:6) {
                  Image(systemName:entry.pinned ? "pin.fill":"doc.text").frame(width:14)
                  Text(entry.title).fontWeight(active ? .semibold:.regular).lineLimit(1).truncationMode(.middle)
                  Spacer(minLength:0)
                  if active {Image(systemName:"checkmark.circle.fill")}
                  else if entry.modified {Circle().frame(width:5,height:5)}
                }.font(.system(size:12)).foregroundStyle(Color(nsColor:active ? StudioTheme.accent:StudioTheme.text))
                  .padding(.horizontal,8).frame(maxWidth:.infinity).frame(height:32)
                  .background(RoundedRectangle(cornerRadius:6).fill(Color(nsColor:active ? StudioTheme.selection:StudioTheme.canvas)))
                  .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:active ? StudioTheme.accent:StudioTheme.border),lineWidth:active ? 2:1).allowsHitTesting(false))
                  .contentShape(RoundedRectangle(cornerRadius:6))
              }.buttonStyle(.plain).id(entry.id)
                .onHover {inside in if inside {model.previewFromHover(entry.id)}}
                .accessibilityLabel(entry.title+" · "+entry.context).accessibilityAddTraits(active ? [.isSelected]:[])
            }
          }.padding(2)
        }.onChange(of:model.index) {_,_ in if let id=selected?.id {proxy.scrollTo(id,anchor:.center)}}
          .onAppear {if let id=selected?.id {proxy.scrollTo(id,anchor:.center)}}
      }.frame(maxWidth:.infinity,maxHeight:.infinity)
      if let selected {
        VStack(alignment:.leading,spacing:8) {
          HStack {
            Text(selected.title).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            Spacer(minLength:8)
            Text(selected.context).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          }.font(.system(size:12))
          Divider()
          ScrollView([.horizontal,.vertical]) {
            Text(selected.sql.isEmpty ? "Boş SQL sekmesi":selected.sql).font(.system(size:11,design:.monospaced))
              .frame(maxWidth:.infinity,alignment:.topLeading)
          }
        }.padding(12).frame(height:140,alignment:.topLeading)
          .frame(maxWidth:.infinity,alignment:.leading)
          .background(RoundedRectangle(cornerRadius:8).fill(Color(nsColor:StudioTheme.canvas)))
          .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:StudioTheme.border),lineWidth:1).allowsHitTesting(false))
          .accessibilityLabel("Seçili sekme önizlemesi")
      }
      HStack {
        Text("Tab / ⇧Tab · İlerle     ← ↑ ↓ → · Seç").foregroundStyle(.secondary)
        Spacer()
        Text(model.acceptanceHint+"     esc · Vazgeç").foregroundStyle(.secondary)
      }.font(.system(size:11))
    }.padding(16).background(Color(nsColor:StudioTheme.panel)).clipShape(RoundedRectangle(cornerRadius:12))
      .overlay(RoundedRectangle(cornerRadius:12).stroke(Color(nsColor:StudioTheme.border),lineWidth:1).allowsHitTesting(false))
      .animation(reduceMotion ? nil:.easeOut(duration:0.10),value:selected?.id)
  }
}

extension WorkbenchController {
  @objc func showTabSwitcher() {if let window=view.window {tabSwitcher.present(in:window,held:[])}}
}
