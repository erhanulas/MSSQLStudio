import AppKit
import SwiftUI

@MainActor final class ShortcutCaptureButton: NSButton {
  var shortcutAction = GridShortcuts.Action.headers
  var report: ((GridShortcuts.AssignmentFeedback) -> Void)?
  private var monitor: Any?
  var recording = false
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event:NSEvent) {beginRecording()}
  override func performClick(_ sender:Any?) {beginRecording()}
  override func accessibilityPerformPress()->Bool {guard isEnabled else {return false};beginRecording();return true}
  @objc func beginRecording() {
    guard isEnabled else {return}
    stop(); recording = true; title = "Tuşlara basın… (Esc: iptal)"
    window?.makeFirstResponder(self)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let handled = MainActor.assumeIsolated {
        guard let self, self.recording else { return false }
        guard event.window === self.window,self.window?.isVisible == true,self.window?.firstResponder === self else {self.stop();return false}
        if event.keyCode == 53 { self.stop(); return true }
        let feedback=GridShortcuts.assign(event,action:self.shortcutAction)
        self.report?(feedback)
        self.stop()
        return true
      }
      return handled ? nil : event
    }
  }
  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil; recording = false
    title = GridShortcuts.binding(shortcutAction).label + " · Değiştir…"
  }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stop() } }
}
struct ShortcutCapture: NSViewRepresentable {
  let action: GridShortcuts.Action
  var report: (GridShortcuts.AssignmentFeedback) -> Void
  func makeNSView(context: Context) -> ShortcutCaptureButton {
    let button = ShortcutCaptureButton(); button.bezelStyle = .rounded; button.shortcutAction = action; button.report = report; button.target=button;button.action=#selector(ShortcutCaptureButton.beginRecording);button.stop()
    button.setAccessibilityLabel(GridShortcuts.title(action)+" kısayolunu değiştir")
    button.toolTip = GridShortcuts.title(action)+" kısayolunu değiştir"
    return button
  }
  func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
    button.report = report
    if !button.recording { button.title = GridShortcuts.binding(action).label + " · Değiştir…" }
  }
}

/// Local search spans every category; the chosen category is restored when search is cleared.
struct ShortcutSettings:View {
  let target:String?
  var navigate:(GridShortcuts.Action)->Void = {_ in}
  var report:(String)->Void
  @State private var category:ShortcutCatalog.Category = .workspace
  @State private var query=""
  @State private var assignment:ShortcutCatalog.Assignment = .all
  @State private var revision=0
  @State private var feedback:GridShortcuts.AssignmentFeedback?
  var body:some View {
    let _=revision
    let actions=ShortcutCatalog.actions(category:category,query:query,assignment:assignment)
    VStack(alignment:.leading,spacing:12) {
      HStack(spacing:12) {
        Picker("Kategori",selection:$category) {
          ForEach(ShortcutCatalog.Category.allCases) {group in
            Label(group.title+" (\(ShortcutCatalog.actions(category:group).count))",systemImage:group.icon).tag(group)
          }
        }.accessibilityIdentifier("shortcutCategory").disabled(!query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        Spacer(minLength:0)
        Text("\(actions.count) komut").font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      HStack(spacing:10) {
        TextField("Tüm kısayollarda ara…",text:$query).textFieldStyle(.roundedBorder)
          .accessibilityLabel("Tüm kısayollarda ara").accessibilityIdentifier("shortcutSearch")
        Picker("Atama",selection:$assignment) {
          ForEach(ShortcutCatalog.Assignment.allCases,id:\.self) {Text($0.title).tag($0)}
        }.labelsHidden().frame(width:142).accessibilityLabel("Kısayol atama filtresi")
      }
      if !query.isEmpty {Text("Tüm kategorilerde arama yapılıyor").font(.caption).foregroundStyle(.secondary)}
      if let feedback {
        HStack(alignment:.top,spacing:8) {
          StudioFeedback(message:feedback.message,tone:feedback.tone == .success ? .success:feedback.tone == .error ? .error:.warning)
          if let action=feedback.target {
            StudioActionButton("Atamaya git",icon:"arrow.turn.down.right") {
              reveal("shortcut."+action.rawValue);navigate(action)
            }.accessibilityIdentifier("shortcutConflictNavigate")
          }
        }.accessibilityIdentifier("shortcutAssignmentFeedback")
      }
      VStack(spacing:0) {
        if actions.isEmpty {
          StudioEmptyState(title:"Eşleşen kısayol yok",icon:"magnifyingglass",detail:"Aramayı veya atama filtresini değiştirin.").padding(20)
        }
        ForEach(actions,id:\.rawValue) {action in
          if action != actions.first {Divider().padding(.horizontal,12)}
          HStack(spacing:8) {
            VStack(alignment:.leading,spacing:3) {
              Text(GridShortcuts.title(action)).font(.system(size:12,weight:.medium)).fixedSize(horizontal:false,vertical:true)
              if !query.isEmpty {Text(ShortcutCatalog.category(action).title).font(.caption2).foregroundStyle(.secondary)}
            }.frame(maxWidth:.infinity,alignment:.leading)
            ShortcutCapture(action:action) {feedback=$0;report("");revision+=1}.frame(width:184,height:28)
            Button {GridShortcuts.clear(action);feedback = .init(message:GridShortcuts.title(action)+" kısayolu kaldırıldı.",tone:.success);report("");revision+=1} label: {Image(systemName:"xmark").frame(width:24,height:28).contentShape(Rectangle())}
              .buttonStyle(.plain).foregroundStyle(.secondary).disabled(GridShortcuts.binding(action).key.isEmpty)
              .accessibilityLabel(GridShortcuts.title(action)+" kısayolunu kaldır").studioHelp("Kısayolu kaldır")
            Button {GridShortcuts.reset(action);feedback = .init(message:GridShortcuts.title(action)+" varsayılan kısayoluna döndürüldü.",tone:.success);report("");revision+=1} label: {Image(systemName:"arrow.counterclockwise").frame(width:24,height:28).contentShape(Rectangle())}
              .buttonStyle(.plain).foregroundStyle(.secondary)
              .accessibilityLabel(GridShortcuts.title(action)+" kısayolunu sıfırla").studioHelp("Varsayılan kısayola dön")
          }.padding(.horizontal,12).padding(.vertical,8)
            .background(target == "shortcut."+action.rawValue ? Color(nsColor:StudioTheme.selection):.clear)
            .id("shortcut."+action.rawValue)
        }
      }.background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color(nsColor:StudioTheme.border)))
      Text("Değiştir’e basıp ⌘ veya ⌃ ile tuş birleşimi girin. Escape iptal eder. Değişiklikler hemen kaydedilir; çakışan ve ayrılmış tuşlar korunur.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.padding(14).background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:10))
      .onChange(of:target) {_,id in reveal(id)}.onAppear {reveal(target)}
      .onReceive(NotificationCenter.default.publisher(for:GridShortcuts.changed)) {_ in revision+=1}
  }
  private func reveal(_ id:String?) {
    guard let action=ShortcutCatalog.target(id) else {return}
    category=ShortcutCatalog.category(action);query="";assignment = .all
  }
}
