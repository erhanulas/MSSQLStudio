import AppKit

extension WorkbenchController {
  @objc func pinActiveTab() {performTabCommand(0)}
  @objc func closeRightTabs() {performTabCommand(2)}
  @objc func closeLeftTabs() {performTabCommand(3)}
  @objc func closeOtherTabs() {performTabCommand(4)}
  @objc func closeAllTabs() {guard commandDocument != nil else {return};requestCloseAllTabs()}
  private func performTabCommand(_ tag:Int) {
    guard let document=commandDocument,
      let item=tabMenu(for:document).items.first(where:{$0.tag==tag && $0.action==Selector(("tabMenuAction:"))}),let action=item.action else {return}
    _ = NSApp.sendAction(action,to:self,from:item)
  }
}
