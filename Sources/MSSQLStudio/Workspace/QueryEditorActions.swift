import AppKit

/// Owned by a single query; hosting/detaching moves these controls with that query.
@MainActor final class QueryEditorActions:NSStackView {
  let document:QueryDocument
  private let focus:()->Void
  private let formatSQL:()->Void
  let run=StudioToolbarButton(symbol:"play",label:"Çalıştır",tone:.success)
  let cancel=StudioToolbarButton(symbol:"stop.fill",label:"İptal",tone:.neutral)
  let plan=StudioToolbarButton(symbol:"point.3.connected.trianglepath.dotted",label:"Tahmini Plan",tone:.neutral)
  let formatButton=StudioToolbarButton(symbol:"text.alignleft",label:"Formatla",tone:.neutral)
  init(document:QueryDocument,focus:@escaping ()->Void,format:@escaping ()->Void) {
    self.document=document;self.focus=focus;formatSQL=format
    super.init(frame:.zero)
    orientation = .horizontal;spacing=2;alignment = .centerY
    for (button,selector,id) in [(run,#selector(execute),"editorRun"),(cancel,#selector(stop),"editorCancel"),(plan,#selector(estimatedPlan),"editorPlan"),(formatButton,#selector(formatSelection),"editorFormat")] {
      button.target=self;button.action=selector;button.flat=true;button.setAccessibilityIdentifier(id);addArrangedSubview(button)
    }
    refresh()
    NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:GridShortcuts.changed,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  @objc func refresh() {
    run.isEnabled=document.canExecute;plan.isEnabled=document.canExecute
    cancel.isEnabled=document.busy;formatButton.isEnabled=document.offlinePreview == nil && !document.definitionLoading
    for (button,title,action) in [(run,"Çalıştır",GridShortcuts.Action.execute),(cancel,"İptal",.cancelQuery),(plan,"Tahmini Plan",.estimatedPlan),(formatButton,"Formatla",.format)] {
      let binding=GridShortcuts.binding(action);button.toolTip=title+(binding.key.isEmpty ? "":" · "+binding.label)
    }
    for button in [run,cancel,plan,formatButton] {button.refreshStyle()}
  }
  @objc private func execute() {guard document.canExecute else {return};focus();document.execute()}
  @objc private func stop() {guard document.busy else {return};document.cancel()}
  @objc private func estimatedPlan() {guard document.canExecute else {return};focus();document.execute(estimated:true)}
  @objc private func formatSelection() {guard formatButton.isEnabled else {return};formatSQL()}
}
