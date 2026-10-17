import SwiftUI
import SQLServerKit

struct ColumnDataTypePicker:View {
  @Binding var type:String
  let choices:[TableDataType]
  var selectionChanged:()->Void={}
  private var base:String {TableDataType.baseName(type)}
  private var choice:TableDataType? {choices.first {$0.name.caseInsensitiveCompare(base) == .orderedSame}}
  private var parameters:[String] {
    guard let open=type.firstIndex(of:"("),type.hasSuffix(")") else {return []}
    return type[type.index(after:open)..<type.index(before:type.endIndex)].split(separator:",",omittingEmptySubsequences:false).map(String.init)
  }
  private func parameter(_ index:Int)->Binding<String> {
    Binding(get:{parameters.indices.contains(index) ? parameters[index]:""},set:{value in
      var values=parameters
      while values.count<=index {values.append("")}
      values[index]=value
      selectionChanged()
      type=base+"("+values.joined(separator:",")+")"
    })
  }
  var body:some View {
    HStack(spacing:4) {
      StudioSearchablePicker(title:"Veri tipi",values:choices.map(\.name),emptyTitle:"Veri tipi seçin",selection:Binding(get:{choice?.name ?? base},set:{name in
        selectionChanged()
        if let selected=choices.first(where:{$0.name==name}),selected.name != choice?.name {type=selected.defaultSQL}
      })).frame(width:136)
      if let choice,choice.parameters != .none {
        TextField(choice.parameters == .precision ? "p":"Boyut",text:parameter(0)).frame(width:44)
          .accessibilityLabel(choice.parameters == .precision ? "Precision":"Uzunluk veya scale")
        if choice.parameters == .precision {TextField("s",text:parameter(1)).frame(width:32).accessibilityLabel("Scale")}
      }
    }.frame(width:224,alignment:.leading)
  }
}
