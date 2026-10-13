import AppKit
import SwiftUI
import SQLServerKit

struct SQLParameterHelp:View {
  let name:String
  let parameters:[RoutineParameter]
  let active:Int?
  let status:String?
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Image(systemName:"list.number").foregroundStyle(Color(nsColor:StudioTheme.accent))
        Text(name).font(.system(size:12,weight:.semibold,design:.monospaced)).lineLimit(1).truncationMode(.middle)
        Spacer()
        Text(GridShortcuts.binding(.parameterInfo).label+" · esc").font(.system(size:10)).foregroundStyle(.secondary)
      }
      Divider()
      if let status {Text(status).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
      else if parameters.isEmpty {Text("Parametre almıyor").font(.system(size:12)).foregroundStyle(.secondary)}
      else {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment:.leading,spacing:2) {
              ForEach(Array(parameters.enumerated()),id: \.element.id) { index,p in
                HStack(spacing:8) {
                  Text(String(index+1)).frame(width:20).foregroundStyle(.secondary)
                  Text(p.name).fontWeight(active == index ? .bold:.medium)
                  Text(p.type+(p.output ? " OUTPUT":"")+(p.tableType ? " READONLY":"")).foregroundStyle(.secondary)
                  Spacer(minLength:0)
                }.font(.system(size:11,design:.monospaced)).padding(.horizontal,6).padding(.vertical,5)
                  .background(active == index ? Color(nsColor:StudioTheme.accent).opacity(0.16):.clear,in:RoundedRectangle(cornerRadius:5)).id(index)
              }
            }
          }.onAppear {if let active {proxy.scrollTo(active,anchor:.center)}}
            .onChange(of:active) {_,value in if let value {proxy.scrollTo(value,anchor:.center)}}
        }
      }
    }.padding(12).background(Color(nsColor:StudioTheme.panel)).accessibilityIdentifier("sqlParameterInfo")
  }
}
