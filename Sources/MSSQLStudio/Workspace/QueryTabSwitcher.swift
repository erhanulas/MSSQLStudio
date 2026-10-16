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
      case 123,126:advance(-1)
      case 124,125:advance(1)
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
    advance(backwards ? -1:1)
    let panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.level = .floating
    panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
    let host=NSHostingController(rootView:QueryTabSwitcherView(model:self));host.sizingOptions=[];panel.contentViewController=host
    let size=NSSize(width:min(760,window.frame.width-48),height:320)
    panel.setFrame(NSRect(x:window.frame.midX-size.width/2,y:window.frame.midY-size.height/2,width:size.width,height:size.height),display:true)
    self.panel=panel;window.addChildWindow(panel,ordered:.above);panel.orderFront(nil)
  }
  var acceptanceHint:String {releaseFlags.isEmpty ? "↩ · Aç":"Tuşu bırak · Aç"}
  func advance(_ delta:Int) {guard !entries.isEmpty else {return};index=(index+delta%entries.count+entries.count)%entries.count}
  func choose(_ id:UUID) {if let value=entries.firstIndex(where:{$0.id==id}) {index=value;dismiss(commit:true)}}
  func dismiss(commit:Bool) {
    guard let panel else {return}
    let id=entries.indices.contains(index) ? entries[index].id:nil
    sourceWindow?.removeChildWindow(panel);panel.orderOut(nil);self.panel=nil;sourceWindow=nil
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
  private var page:ArraySlice<QueryTabSwitcher.Entry> {
    let start=(model.index/3)*3
    return model.entries.dropFirst(start).prefix(3)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        Label("Açık sekmeler",systemImage:"square.stack").font(.system(size:16,weight:.semibold))
        Spacer()
        Text("\(model.index+1) / \(model.entries.count)").monospacedDigit().foregroundStyle(.secondary)
      }
      HStack(spacing:12) {
        ForEach(page) {entry in
          let selected=model.entries.indices.contains(model.index) && model.entries[model.index].id==entry.id
          Button {model.choose(entry.id)} label:{
            VStack(alignment:.leading,spacing:8) {
              HStack(spacing:4) {
                Image(systemName:entry.pinned ? "pin.fill":"doc.text")
                Text(entry.title).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if entry.modified {Circle().fill(Color(nsColor:StudioTheme.accent)).frame(width:5,height:5)}
              }.foregroundStyle(Color(nsColor:selected ? StudioTheme.accent:StudioTheme.text))
              Divider()
              Text(entry.sql.isEmpty ? "Boş SQL sekmesi":entry.sql).font(.system(size:11,design:.monospaced))
                .foregroundStyle(Color(nsColor:StudioTheme.text)).lineLimit(7).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
              Text(entry.context).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
              .background(RoundedRectangle(cornerRadius:8).fill(Color(nsColor:selected ? StudioTheme.selection:StudioTheme.canvas)))
              .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:selected ? StudioTheme.accent:StudioTheme.border),lineWidth:selected ? 2:1).allowsHitTesting(false))
              .contentShape(RoundedRectangle(cornerRadius:8))
          }.buttonStyle(.plain).accessibilityLabel(entry.title+" · "+entry.context).accessibilityAddTraits(selected ? [.isSelected]:[])
        }
        ForEach(0..<(3-page.count),id:\.self) {_ in Color.clear.frame(maxWidth:.infinity,maxHeight:.infinity)}
      }.frame(maxWidth:.infinity,maxHeight:.infinity)
      HStack {
        Text("Tab / ⇧Tab · İlerle     ← → · Seç").foregroundStyle(.secondary)
        Spacer()
        Text(model.acceptanceHint+"     esc · Vazgeç").foregroundStyle(.secondary)
      }.font(.system(size:11))
    }.padding(16).background(Color(nsColor:StudioTheme.panel)).clipShape(RoundedRectangle(cornerRadius:12))
      .overlay(RoundedRectangle(cornerRadius:12).stroke(Color(nsColor:StudioTheme.border),lineWidth:1).allowsHitTesting(false))
      .animation(reduceMotion ? nil:.easeOut(duration:0.10),value:model.index)
  }
}

extension WorkbenchController {
  @objc func showTabSwitcher() {if let window=view.window {tabSwitcher.present(in:window,held:[])}}
}
