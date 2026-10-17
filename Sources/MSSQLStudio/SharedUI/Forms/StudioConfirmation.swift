import AppKit
import SwiftUI

struct StudioConfirmationAction {
  let title:String
  var destructive=false
  let perform:()->Void
}

extension View {
  func studioConfirmation(_ title:String,isPresented:Binding<Bool>,role:String,message:String,
    actions:[StudioConfirmationAction],cancel:@escaping ()->Void={}) -> some View {
    background(StudioConfirmation(title:title,isPresented:isPresented,role:role,message:message,actions:actions,cancel:cancel).frame(width:0,height:0))
  }
}

/// SwiftUI owns intent; the native sheet shares placement with other confirmations.
private struct StudioConfirmation:NSViewRepresentable {
  let title:String
  @Binding var isPresented:Bool
  let role:String
  let message:String
  let actions:[StudioConfirmationAction]
  let cancel:()->Void
  func makeCoordinator()->Coordinator {Coordinator()}
  func makeNSView(context:Context)->AnchorView {
    let view=AnchorView()
    view.attached={ [weak coordinator=context.coordinator] in coordinator?.schedulePresentation()}
    context.coordinator.view=view
    return view
  }
  func updateNSView(_ view:AnchorView,context:Context) {
    context.coordinator.presentation=self
    context.coordinator.schedulePresentation()
  }
  static func dismantleNSView(_ view:AnchorView,coordinator:Coordinator) {coordinator.dismiss()}

  @MainActor final class AnchorView:NSView {
    var attached:(()->Void)?
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();attached?()}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
  }
  @MainActor final class Coordinator {
    weak var view:AnchorView?
    var presentation:StudioConfirmation?
    private var alert:StudioAlert?
    private weak var owner:NSWindow?
    private var scheduled=false
    func schedulePresentation() {
      guard !scheduled else {return}
      scheduled=true
      DispatchQueue.main.async { [weak self] in
        guard let self else {return}
        self.scheduled=false
        self.presentIfNeeded()
      }
    }
    private func presentIfNeeded() {
      guard let presentation,presentation.isPresented else {dismiss();return}
      guard alert==nil,let parent=view?.window else {return}
      let alert=StudioAlert(role:presentation.role)
      alert.messageText=presentation.title;alert.informativeText=presentation.message
      let cancel=alert.addButton(withTitle:"Vazgeç")
      cancel.keyEquivalent="\u{1b}"
      for action in presentation.actions {
        let button=alert.addButton(withTitle:action.title)
        if action.destructive {button.hasDestructiveAction=true}
      }
      self.alert=alert
      owner=parent
      alert.beginSheetModal(for:parent) { [weak self] response in
        guard let self,self.alert === alert else {return}
        self.alert=nil;self.owner=nil
        // A dismissal or a stale view must never approve the operation.
        guard self.presentation?.isPresented==true else {return}
        presentation.isPresented=false
        let index=response.rawValue-NSApplication.ModalResponse.alertFirstButtonReturn.rawValue-1
        if presentation.actions.indices.contains(index) {presentation.actions[index].perform()}
        else {presentation.cancel()}
      }
      // NSAlert may clear the default when Cancel also has the Escape shortcut.
      alert.window.defaultButtonCell=cancel.cell as? NSButtonCell
    }
    func dismiss() {
      guard let alert else {return}
      let parent=owner ?? alert.window.sheetParent
      self.alert=nil
      owner=nil
      parent?.endSheet(alert.window,returnCode:.abort)
      alert.window.orderOut(nil)
    }
  }
}
