import AppKit
import SQLServerKit
import SwiftUI

struct StructureObjectsPanel:View {
  @ObservedObject var model:TableDesignerModel
  let open:(String)->Void
  @State private var discardDraft=false
  @State private var pendingObject:ManagedDefinition?
  private let kinds=["INDEX","PK","UQ","FK","CHECK"]
  var body:some View {
    HSplitView {
      VStack(alignment:.leading,spacing:8) {
        HStack {
          Text("Mevcut nesneler").font(.headline)
          Spacer()
          StudioActionButton("Yeni",icon:"plus") {choose(nil)}
            .accessibilityIdentifier("newTableStructureObject")
        }.fixedSize(horizontal:false,vertical:true)
        List(model.original?.definitions ?? []) {object in
          Button {choose(object)} label:{
            HStack(alignment:.top,spacing:8) {
              Image(systemName:object.kind == "PK" || object.kind == "UQ" ? "key.fill":object.kind == "FK" ? "link":"list.bullet.rectangle")
                .foregroundStyle(Color(nsColor:object.kind == "PK" ? StudioTheme.warning:StudioTheme.accent))
              VStack(alignment:.leading,spacing:3) {Text(object.name).lineLimit(2);Text(object.kind).font(.caption).foregroundStyle(.secondary)}
              Spacer(minLength:0)
            }.padding(6).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
              .background(model.selectedDefinition?.id==object.id ? Color(nsColor:StudioTheme.selection):.clear,in:RoundedRectangle(cornerRadius:6))
          }.buttonStyle(.plain).accessibilityIdentifier("tableStructure_"+object.name)
        }
        if let selected=model.selectedDefinition {
          StudioActionButton("Mevcut SQL’i Aç",icon:"doc.text") {open(selected.sql)}
        }
      }.padding(8).frame(minWidth:180,idealWidth:240,maxWidth:320)
      ScrollView {
        VStack(alignment:.leading,spacing:12) {
          HStack {
            Text(model.selectedDefinition == nil ? "Yeni nesne":"Nesne özellikleri").font(.headline)
            Spacer()
            if model.selectedDefinition != nil {Text("Düzenleme").font(.caption).foregroundStyle(.secondary)}
          }
          if model.structureEditable {
            StudioFormField("Tür") {
              StudioSelectionPicker(title:"Nesne türü",selection:$model.structure.kind,options:kinds,label:{kind in
                switch kind {case "PK":return "Primary Key";case "UQ":return "Unique Key";case "FK":return "Foreign Key";case "CHECK":return "Check Constraint";default:return "Index"}
              }).disabled(model.selectedDefinition != nil)
            }
            StudioFormField("Ad") {TextField("Nesne adı",text:$model.structure.name)}
            if model.structure.kind != "CHECK" {keyColumns}
            if model.structure.kind == "INDEX" {
              StudioFormField("Benzersiz") {Toggle("UNIQUE",isOn:$model.structure.unique)}
              StudioFormField("Filtre") {TextField("İsteğe bağlı WHERE koşulu",text:$model.structure.expression)}
            }
            if model.structure.kind == "CHECK" {StudioFormField("CHECK koşulu") {TextField("[Amount] >= 0",text:$model.structure.expression)}}
            if model.structure.kind == "FK" {
              StudioFormField("Hedef şema") {TextField("dbo",text:$model.structure.targetSchema)}
              StudioFormField("Hedef tablo") {TextField("Tablo adı",text:$model.structure.targetTable)}
              StudioFormField("Hedef kolonlar") {TextField("[Id], [Code]",text:$model.structure.targetColumns)}
              StudioFormField("ON DELETE") {actionPicker($model.structure.deleteAction)}
              StudioFormField("ON UPDATE") {actionPicker($model.structure.updateAction)}
            }
            if model.selectedDefinition != nil {
              Text("Görünmeyen indeks/depolama, güven ve devre dışı durum özellikleri korunur. Değişiklik SQL’i mevcut nesneyi kaldırıp yeniden oluşturur.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
          } else {
            StudioEmptyState(title:"SQL editöründe düzenleyin",icon:"doc.text",detail:"Bu nesnenin görsel düzenlemesi desteklenmiyor; mevcut SQL’i açabilirsiniz.")
          }
        }.padding(12)
      }.frame(minWidth:420)
    }.studioConfirmation("Nesne taslağı bırakılsın mı?",isPresented:$discardDraft,role:"discardTableStructureDraft",message:"Başka bir nesneye geçmek bu nesnenin uygulanmamış değişikliklerini bırakır. Columns taslağınız korunur.",actions:[StudioConfirmationAction(title:"Taslağı Bırak",destructive:true) {activate(pendingObject);pendingObject=nil}],cancel:{pendingObject=nil})
      .onChange(of:model.structure.kind) {_,kind in if model.selectedDefinition==nil {model.newStructure(kind:kind)}}
  }
  private func choose(_ object:ManagedDefinition?) {
    if let object,object.id==model.selectedDefinition?.id {return}
    if model.structureChanged {pendingObject=object;discardDraft=true} else {activate(object)}
  }
  private func activate(_ object:ManagedDefinition?) {
    if let object {model.select(object)}
    else {model.newStructure(kind:kinds.contains(model.structure.kind) ? model.structure.kind:"INDEX")}
  }
  private var keyColumns:some View {
    LazyVStack(alignment:.leading,spacing:6) {
      HStack {
        Text("Anahtar kolonları · seçim sırası").font(.caption).frame(maxWidth:.infinity,alignment:.leading)
        if model.structure.kind != "FK" {Text("DESC").font(.caption).frame(width:56)}
        if model.structure.kind == "INDEX" {Text("Include").font(.caption).frame(width:68)}
      }.foregroundStyle(.secondary)
      ForEach(model.columns) {column in
        HStack(spacing:8) {
          Toggle(isOn:membership(column.name,key:true)) {
            HStack(spacing:6) {Text(column.name);if let i=model.structure.keys.firstIndex(of:column.name) {Text("\(i+1)").font(.caption).foregroundStyle(.secondary)}}
          }.frame(maxWidth:.infinity,alignment:.leading)
          if model.structure.kind != "FK" {
            Toggle("Azalan",isOn:Binding(get:{model.structure.descending.contains(column.name)},set:{if $0 {model.structure.descending.insert(column.name)} else {model.structure.descending.remove(column.name)}}))
              .labelsHidden().frame(width:56).disabled(!model.structure.keys.contains(column.name))
          }
          if model.structure.kind == "INDEX" {Toggle("Include",isOn:membership(column.name,key:false)).labelsHidden().frame(width:68)}
        }.padding(.vertical,2)
      }
    }.studioCard(padding:8)
  }
  private func membership(_ name:String,key:Bool)->Binding<Bool> {
    Binding(get:{key ? model.structure.keys.contains(name):model.structure.included.contains(name)},set:{value in
      if key {
        if value {model.structure.keys.append(name);model.structure.included.removeAll {$0==name}}
        else {model.structure.keys.removeAll {$0==name};model.structure.descending.remove(name)}
      } else {
        if value {model.structure.included.append(name);model.structure.keys.removeAll {$0==name};model.structure.descending.remove(name)}
        else {model.structure.included.removeAll {$0==name}}
      }
    })
  }
  private func actionPicker(_ selection:Binding<String>)->some View {
    StudioSelectionPicker(title:"İlişki eylemi",selection:selection,options:["NO ACTION","CASCADE","SET NULL","SET DEFAULT"],label:{$0})
  }
}
