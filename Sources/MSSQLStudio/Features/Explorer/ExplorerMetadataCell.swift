import AppKit
import SQLServerKit

@MainActor final class ExplorerMetadataCell:NSTableCellView {
  var node:TreeNode?
  private var area:NSTrackingArea?
  private var task:Task<Void,Never>?
  override func updateTrackingAreas() {
    super.updateTrackingAreas();if let area {removeTrackingArea(area)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
    addTrackingArea(area);self.area=area
  }
  override func mouseEntered(with event:NSEvent) {
    guard let node,let item=node.item else {return}
    if node.objectFolder == .columns || node.objectFolder == .parameters {
      StudioHoverHelp.shared.schedule(for:self,title:item.name,detail:item.detail);return
    }
    guard node.objectFolder == .functions else {return}
    let revision=StudioHoverHelp.shared.begin(for:self),generation=node.server.generation
    task?.cancel()
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(250))
        guard let self,node.server.online,!Task.isCancelled else {return}
        let info=try await node.server.hoverMetadata.lookup(targets:[[item.schema,item.name]],database:node.database)
        guard !Task.isCancelled,generation==node.server.generation,StudioHoverHelp.shared.revision==revision,window?.isVisible == true,let info else {return}
        StudioHoverHelp.shared.schedule(for:self,title:info.title,detail:info.detail)
      } catch { }
    }
  }
  override func mouseExited(with event:NSEvent) {dismiss()}
  override func mouseDown(with event:NSEvent) {dismiss();super.mouseDown(with:event)}
  override func rightMouseDown(with event:NSEvent) {dismiss();super.rightMouseDown(with:event)}
  override func viewWillMove(toWindow newWindow:NSWindow?) {if newWindow==nil {dismiss()};super.viewWillMove(toWindow:newWindow)}
  private func dismiss() {task?.cancel();task=nil;StudioHoverHelp.shared.hide(for:self)}
  deinit {task?.cancel()}
}
