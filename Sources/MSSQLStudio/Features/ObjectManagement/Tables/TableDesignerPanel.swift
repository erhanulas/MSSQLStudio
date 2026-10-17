import AppKit
import SQLServerKit
import SwiftUI

struct TableDesignerPanel: View {
  let server:String
  let database:String
  let initialKind:String
  @State private var tab="columns"
  @State private var selectedColumn=Int.min
  let load:(() async throws -> TableDefinition)?
  let open:(String)->Void
  @StateObject private var model:TableDesignerModel
  @State private var approval:TableDesignPlan?
  @State private var confirmReload=false
  init(server:String,database:String,initialKind:String="",load:(() async throws -> TableDefinition)?=nil,model:TableDesignerModel?=nil,open:@escaping (String)->Void) {
    self.server=server;self.database=database;self.initialKind=initialKind;self.load=load;self.open=open
    _model=StateObject(wrappedValue:model ?? TableDesignerModel(initialKind:initialKind,load:load))
    _tab=State(initialValue:initialKind.isEmpty ? "columns":"management")
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        StudioPanelHeading(title:model.isNew ? "Yeni Tablo":"Tablo Tasarımı",icon:"tablecells",subtitle:server+" · "+database)
        Spacer()
        StudioActionButton("Sunucudan Yenile",icon:"arrow.clockwise") {
          if model.ready && model.hasChanges {confirmReload=true} else {Task {await model.reload()}}
        }.disabled(model.busy || !model.ready && model.error.isEmpty || model.ready && model.isNew && !model.unverified)
      }.fixedSize(horizontal:false,vertical:true)
      HStack(spacing:16) {
        VStack(alignment:.leading,spacing:4) {Text("Şema").font(.caption).foregroundStyle(.secondary);TextField("Şema",text:$model.schema)}
        VStack(alignment:.leading,spacing:4) {Text("Tablo adı").font(.caption).foregroundStyle(.secondary);TextField("Tablo adı",text:$model.name)}
        Text("\(model.columns.count) kolon").font(.caption).foregroundStyle(.secondary).fixedSize()
      }.studioCard().disabled(!model.ready || !model.isNew || model.busy)
      if model.original != nil {
        StudioChoiceTabs(choices:[("columns","Columns","tablecells"),("management","Keys / Indexes / Relationships","link")],selection:$tab).frame(height:36).disabled(model.busy)
      }
      Group {
        if !model.ready {
          if model.error.isEmpty {StudioLoadingView(title:"Tablo bilgileri alınıyor",context:server+" / "+database,phase:"Kolonlar, anahtarlar ve veri tipleri okunuyor…").frame(maxWidth:.infinity,maxHeight:.infinity)}
          else {StudioEmptyState(title:"Tablo bilgileri okunamadı",icon:"tablecells",detail:"Sunucudan Yenile ile tekrar deneyin.").frame(maxWidth:.infinity,maxHeight:.infinity)}
        } else if tab=="management",model.original != nil {StructureObjectsPanel(model:model,open:open)}
        else {columnEditor}
      }.frame(maxWidth:.infinity,maxHeight:.infinity).disabled(model.busy)
      if !model.error.isEmpty {StudioFeedback(message:model.error)}
      if !model.message.isEmpty {StudioFeedback(message:model.message,tone:.success)}
      Text("Otomatik tablo rebuild yapılmaz. Uygula, SQL önizlemesi ve gönderim onayını açar.").font(.caption).foregroundStyle(.secondary)
      HStack(spacing:8) {
        Text(model.hasChanges ? "Bekleyen değişiklikler var":"Değişiklik yok").font(.caption).foregroundStyle(.secondary)
        Spacer()
        StudioActionButton("SQL Editöründe İncele",icon:"doc.text.magnifyingglass",tint:.accentColor) {
          commitFields()
          do {open(try model.prepare().sql);model.error=""} catch {model.error=error.localizedDescription}
        }.disabled(!model.canPrepare).accessibilityIdentifier("tableDesignerReview")
        StudioActionButton("Uygula",icon:"checkmark") {
          commitFields()
          do {approval=try model.prepare();model.error=""} catch {model.error=error.localizedDescription}
        }.buttonStyle(StudioPrimaryButton()).disabled(!model.canApply).accessibilityIdentifier("tableDesignerApply")
      }.fixedSize(horizontal:false,vertical:true)
    }.padding(StudioMetrics.gap).studioPanel().task {await model.load()}
      .onDisappear {model.close()}
      .studioConfirmation("Tasarım sunucudan yenilensin mi?",isPresented:$confirmReload,role:"reloadTableDesigner",message:"Bu penceredeki taslak bırakılacak ve güncel tablo bilgileri sunucudan okunacak.",actions:[StudioConfirmationAction(title:"Yenile",destructive:true) {Task {await model.reload()}}])
      .sheet(item:$approval) {plan in TableDesignReview(model:model,plan:plan,context:server+" / "+database).studioSheetPlacement(role:"tableDesignReview",minimum:NSSize(width:720,height:520))}
  }
  private func commitFields() {NSApp.keyWindow?.makeFirstResponder(nil)}
  private var columnEditor:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Button {
          let id=min(0,model.columns.map(\.id).min() ?? 0)-1
          var name="NewColumn",suffix=2
          while model.columns.contains(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) {name="NewColumn\(suffix)";suffix+=1}
          model.columns.append(SQLServerKit.TableColumn(id:id,name:name));selectedColumn=id
        } label:{Label("Kolon Ekle",systemImage:"plus")}.accessibilityIdentifier("addDesignerColumn")
        Button(role:.destructive) {commitFields();model.columns.removeAll {$0.id==selectedColumn};model.primary.remove(selectedColumn);selectedColumn=Int.min} label:{Label("Seçili Kolonu Kaldır",systemImage:"minus.circle")}.disabled(!model.columns.contains {$0.id==selectedColumn}).accessibilityIdentifier("removeDesignerColumn")
        Spacer()
        Text(model.columns.first(where:{$0.id==selectedColumn}).map {"Seçili: "+$0.name} ?? "Düzenlemek için satıra tıklayın").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }.fixedSize(horizontal:false,vertical:true)
      Divider()
      ScrollViewReader { proxy in
      ScrollView([.horizontal,.vertical]) {
        LazyVStack(alignment:.leading,spacing:6) {
          HStack {Color.clear.frame(width:28,height:1);Text("Kolon adı").frame(width:150);Text("Veri tipi / boyut").frame(width:224);Text("NULL").frame(width:45);Text("PK").frame(width:40);Text("Identity").frame(width:70);Text("Default / computed").frame(width:240,alignment:.leading)}.font(.caption).foregroundStyle(.secondary)
          ForEach($model.columns) { $column in
            TableColumnEditor(column:$column,primary:Binding(get:{model.primary.contains(column.id)},set:{if $0 {model.primary.insert(column.id)} else {model.primary.remove(column.id)}}),choices:model.types,selected:selectedColumn==column.id,existing:model.original?.columns.contains(where:{$0.id==column.id}) == true,generated:model.original?.columns.first(where:{$0.id==column.id})?.generated == true,select:{selectedColumn=column.id})
              .frame(width:945,height:30)
              .padding(.vertical,3).background(selectedColumn == column.id ? Color.accentColor.opacity(0.13) : Color.clear).overlay(alignment:.leading) {if selectedColumn == column.id {Rectangle().fill(Color.accentColor).frame(width:2)}}.contentShape(Rectangle()).simultaneousGesture(TapGesture().onEnded {selectedColumn=column.id}).id(column.id)
          }
        }.padding(.vertical,8)
      }.frame(minHeight:80,maxHeight:.infinity).layoutPriority(-1)
      .onChange(of:model.columns.count) {old,new in if new > old,let selected=model.columns.last,selected.id==selectedColumn {proxy.scrollTo(selected.id,anchor:.bottom)} }
      }
      Text("Identity seed/increment yeni kolonlarda 1,1. Computed/özel üretilen kolon değişikliği SQL editöründe yapılır.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.padding(10).disabled(!model.ready)
  }
}
