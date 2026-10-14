import AppKit

@MainActor final class StudioCommandOutlineView:NSOutlineView {
  var shortcutMenu:(()->NSMenu?)?
  override func performKeyEquivalent(with event:NSEvent)->Bool {
    if window?.firstResponder === self,StudioCommandCatalog.dispatch(event,to:self,menu:{shortcutMenu?()}) {return true}
    return super.performKeyEquivalent(with:event)
  }
  override func keyDown(with event:NSEvent) {
    if StudioCommandCatalog.dispatch(event,to:self,menu:{shortcutMenu?()}) {return}
    super.keyDown(with:event)
  }
}
