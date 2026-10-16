import SwiftUI
import SQLServerKit

struct ProfilerColumnFilter:View {
  @ObservedObject var model:ProfilerModel
  let column:SQLProfilerFiltering.Column
  let close:()->Void
  @State private var value=""
  @State private var comparison:SQLProfilerFiltering.Comparison = .contains
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      Text(column.title).fontWeight(.medium)
      Picker("Koşul",selection:$comparison) {ForEach(column.operators) {Text($0.title).tag($0)}}
      TextField("Filtre değeri",text:$value).textFieldStyle(.roundedBorder).onSubmit(apply)
      HStack {
        Button("Kaldır") {model.displayFilter.rules.removeAll {$0.column==column};close()}.buttonStyle(StudioSecondaryButton())
        Spacer()
        Button("Uygula",action:apply).buttonStyle(StudioPrimaryButton()).disabled(value.isEmpty || (model.displayFilter.rules.count>=20 && !model.displayFilter.rules.contains {$0.column==column}))
      }
    }.padding(12).frame(width:280).onAppear {
      let rule=model.displayFilter.rules.first {$0.column==column}
      value=rule?.value ?? "";comparison=rule?.comparison ?? column.operators[0]
    }
  }
  private func apply() {
    guard !value.isEmpty else {return}
    var filter=model.displayFilter
    if let index=filter.rules.firstIndex(where:{$0.column==column}) {filter.rules[index].comparison=comparison;filter.rules[index].value=value}
    else {guard filter.rules.count<20 else {return};filter.rules.append(.init(column:column,comparison:comparison,value:value))}
    model.displayFilter=filter;close()
  }
}
