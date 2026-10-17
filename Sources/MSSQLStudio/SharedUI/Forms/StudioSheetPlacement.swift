import AppKit
import SwiftUI

extension View {
  func studioSheetPlacement(role:String,minimum:NSSize)->some View {
    background(StudioSheetPlacement(role:role,minimum:minimum).frame(width:0,height:0))
  }
}

/// Keeps SwiftUI's sheet lifecycle and approval actions; AppKit owns attachment.
private struct StudioSheetPlacement:NSViewRepresentable {
  let role:String
  let minimum:NSSize
  func makeCoordinator()->Coordinator {Coordinator(role:role,minimum:minimum)}
  func makeNSView(context:Context)->PlacementView {
    let view=PlacementView()
    view.attached={ [weak coordinator=context.coordinator] window in coordinator?.attach(window)}
    return view
  }
  func updateNSView(_ view:PlacementView,context:Context) {}
  static func dismantleNSView(_ view:PlacementView,coordinator:Coordinator) {coordinator.detach()}

  @MainActor final class PlacementView:NSView {
    var attached:((NSWindow?)->Void)?
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();attached?(window)}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
  }
  @MainActor final class Coordinator {
    let role:String
    let minimum:NSSize
    private weak var window:NSWindow?
    private weak var owner:NSWindow?
    private var prepared=false
    private var observers:[NSObjectProtocol]=[]
    init(role:String,minimum:NSSize) {self.role=role;self.minimum=minimum}
    func attach(_ window:NSWindow?) {
      guard self.window !== window else {return}
      detach();self.window=window
      guard window != nil else {return}
      // The hosting view can arrive before AppKit attaches its sheet.
      for name in [NSWindow.didBecomeKeyNotification,NSWindow.willBeginSheetNotification] {
        observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
          MainActor.assumeIsolated {DispatchQueue.main.async { [weak self] in self?.prepare() }}
        })
      }
      observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didEndSheetNotification,object:nil,queue:.main) { [weak self] note in
        let parent=note.object as? NSWindow
        MainActor.assumeIsolated {
          guard let self,parent === self.owner else {return}
          self.detach()
        }
      })
      DispatchQueue.main.async { [weak self] in self?.prepare() }
    }
    private func prepare() {
      guard !prepared,let window,let parent=window.sheetParent else {return}
      prepared=true
      owner=parent
      window.styleMask.insert(.resizable)
      window.contentMinSize=minimum
      StudioWindowPlacement.restoreSheetSize(window,role:role,owner:parent)
    }
    func detach() {
      if prepared,let window {StudioWindowPlacement.save(window,role:role)}
      for observer in observers {NotificationCenter.default.removeObserver(observer)}
      observers=[];prepared=false;window=nil;owner=nil
    }
  }
}
