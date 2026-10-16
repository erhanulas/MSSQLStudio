import SwiftUI

/// Compact full-area navigation with explicit selection and native button focus.
struct StudioTabBar:View {
  struct Item:Identifiable {
    let id:Int
    let title:String
    let icon:String
    var count:Int?=nil
  }
  let items:[Item]
  @Binding var selection:Int
  @State private var hovered:Int?
  var body:some View {
    HStack(spacing:4) {
      ForEach(items) {item in
        let selected=selection==item.id
        Button {selection=item.id} label: {
          HStack(spacing:6) {
            Image(systemName:item.icon).font(.system(size:12))
            Text(item.title).font(.system(size:12,weight:selected ? .semibold:.regular)).lineLimit(1)
            if let count=item.count {
              Text(String(count)).font(.system(size:10,weight:.medium)).monospacedDigit()
                .padding(.horizontal,5).padding(.vertical,2)
                .background(Color(nsColor:StudioTheme.muted).opacity(0.09),in:Capsule())
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
  }
}
