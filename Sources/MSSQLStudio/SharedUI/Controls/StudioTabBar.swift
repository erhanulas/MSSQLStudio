import SwiftUI

/// Compact full-area navigation with explicit selection and native button focus.
struct StudioTabBar:View {
  enum Tone {
    case accent,success,warning,danger
    @MainActor var color:NSColor {
      switch self {
      case .accent:StudioTheme.accent
      case .success:StudioTheme.success
      case .warning:StudioTheme.warning
      case .danger:StudioTheme.danger
      }
    }
  }
  struct Item:Identifiable {
    let id:Int
    let title:String
    let icon:String
    var count:Int?=nil
    var tone:Tone?=nil
  }
  let items:[Item]
  @Binding var selection:Int
  @State private var hovered:Int?
  @State private var themeRevision=0
  @Environment(\.colorScheme) private var colorScheme
  var body:some View {
    let _=themeRevision
    let _=colorScheme
    return HStack(spacing:4) {
      ForEach(items) {item in
        let selected=selection==item.id
        Button {selection=item.id} label: {
          HStack(spacing:6) {
            Image(systemName:item.icon).font(.system(size:12))
              .foregroundStyle(Color(nsColor:item.tone?.color ?? (selected ? StudioTheme.accent:StudioTheme.muted)))
            Text(item.title).font(.system(size:12,weight:selected ? .semibold:.regular)).lineLimit(1)
            if let count=item.count {
              let emphasized=count>0 && item.tone != nil
              let badgeColor=emphasized ? item.tone!.color:StudioTheme.muted
              Text(String(count)).font(.system(size:10,weight:emphasized ? .semibold:.medium)).monospacedDigit()
                .foregroundStyle(Color(nsColor:emphasized ? badgeColor:selected ? StudioTheme.accent:StudioTheme.muted))
                .padding(.horizontal,5).padding(.vertical,2)
                .background(Color(nsColor:badgeColor).opacity(emphasized ? 0.14:0.09),in:Capsule())
            }
          }.foregroundStyle(Color(nsColor:selected ? StudioTheme.accent:StudioTheme.muted))
            .padding(.horizontal,10).frame(height:30).frame(maxWidth:.infinity)
            .background(Color(nsColor:selected ? StudioTheme.selection:hovered==item.id ? StudioTheme.canvas:StudioTheme.panel),in:RoundedRectangle(cornerRadius:StudioMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius:StudioMetrics.controlRadius).stroke(Color(nsColor:selected ? StudioTheme.accent.withAlphaComponent(0.25):.clear),lineWidth:1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).studioHelp(item.title).onHover {hovered=$0 ? item.id:nil}.accessibilityLabel(item.title)
          .accessibilityValue(item.count.map {"\($0) kayıt"} ?? "")
          .accessibilityAddTraits(selected ? [.isSelected]:[])
      }
    }.padding(4)
      .background(Color(nsColor:StudioTheme.panel),in:RoundedRectangle(cornerRadius:StudioMetrics.cardRadius))
      .onReceive(NotificationCenter.default.publisher(for:StudioTheme.changed)) {_ in themeRevision+=1}
  }
}

/// AppKit adapter uses the same surface and selection presentation as SwiftUI tabs.
@MainActor final class StudioTabControl:NSControl {
  var selectedSegment:Int=0 {didSet {updateContent()}}
  private var host:NSHostingView<StudioTabBar>?
  private let items:[StudioTabBar.Item]
  init(items:[StudioTabBar.Item]) {
    self.items=items
    super.init(frame:.zero)
    let host=NSHostingView(rootView:content())
    self.host=host;host.translatesAutoresizingMaskIntoConstraints=false;addSubview(host)
    NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo:leadingAnchor),host.trailingAnchor.constraint(equalTo:trailingAnchor),host.topAnchor.constraint(equalTo:topAnchor),host.bottomAnchor.constraint(equalTo:bottomAnchor),heightAnchor.constraint(equalToConstant:38)])
  }
  required init?(coder:NSCoder) {fatalError()}
  private func content()->StudioTabBar {
    StudioTabBar(items:items,selection:Binding(get:{[weak self] in self?.selectedSegment ?? 0},set:{[weak self] value in
      guard let self else {return}
      selectedSegment=value;sendAction(action,to:target)
    }))
  }
  private func updateContent() {host?.rootView=content()}
}

struct StudioChoiceTabs<Value:Equatable>:View {
  let choices:[(Value,String,String)]
  @Binding var selection:Value
  var body:some View {
    StudioTabBar(items:choices.enumerated().map {.init(id:$0.offset,title:$0.element.1,icon:$0.element.2)},selection:Binding(get:{choices.firstIndex(where:{$0.0==selection}) ?? 0},set:{if choices.indices.contains($0) {selection=choices[$0].0}}))
  }
}
