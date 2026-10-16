import AppKit
import SwiftUI

/// Preserve the original Settings Picker presentation for every small option list.
struct StudioSelectionPicker<Value:Equatable>:View {
  let title:String
  @Binding var selection:Value
  let options:[Value]
  let label:(Value)->String
  var body:some View {
    Picker(title,selection:Binding(get:{options.firstIndex(of:selection) ?? -1},set:{index in
      if options.indices.contains(index) {selection=options[index]}
    })) {
      ForEach(options.indices,id:\.self) {index in Text(label(options[index])).tag(index)}
    }.labelsHidden().accessibilityLabel(title)
  }
}

/// AppKit host of that same SwiftUI Picker; filter indices and target/action stay native.
@MainActor final class StudioSelectionControl:NSControl {
  private var host:NSHostingView<AnyView>?
  private(set) var itemTitles:[String]=[]
  private(set) var indexOfSelectedItem = -1
  private var pickerTitle=""
  override var isEnabled:Bool {didSet {updateContent()}}
  convenience init() {self.init(frame:.zero)}
  override init(frame:NSRect) {
    super.init(frame:frame)
    let host=NSHostingView(rootView:content());host.sizingOptions=[]
    self.host=host;host.translatesAutoresizingMaskIntoConstraints=false;addSubview(host)
    NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo:leadingAnchor),host.trailingAnchor.constraint(equalTo:trailingAnchor),host.topAnchor.constraint(equalTo:topAnchor),host.bottomAnchor.constraint(equalTo:bottomAnchor)])
    setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
  }
  required init?(coder:NSCoder) {fatalError()}
  override var intrinsicContentSize:NSSize {NSSize(width:142,height:StudioMetrics.controlHeight)}
  override func setAccessibilityLabel(_ label:String?) {
    super.setAccessibilityLabel(label);pickerTitle=label ?? "";updateContent()
  }
  func addItems(withTitles titles:[String]) {
    itemTitles.append(contentsOf:titles)
    if indexOfSelectedItem<0 && !itemTitles.isEmpty {indexOfSelectedItem=0}
    updateContent()
  }
  func selectItem(at index:Int) {
    guard itemTitles.indices.contains(index) else {return}
    indexOfSelectedItem=index;updateContent()
  }
  private func content()->AnyView {
    AnyView(StudioSelectionPicker(title:pickerTitle,selection:Binding(get:{[weak self] in self?.indexOfSelectedItem ?? -1},set:{[weak self] index in
      guard let self,itemTitles.indices.contains(index) else {return}
      selectItem(at:index);sendAction(action,to:target)
    }),options:Array(itemTitles.indices),label:{[titles=itemTitles] in titles[$0]}).disabled(!isEnabled))
  }
  private func updateContent() {host?.rootView=content()}
}
