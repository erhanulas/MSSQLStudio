import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class FavoriteQueriesModel:ObservableObject {
  @Published private(set) var items:[FavoriteQuery]=[]
  @Published var error=""
  private let store:FavoriteQueryStore
  init(url:URL) {store=FavoriteQueryStore(url:url)}
  func load() async {
    do {items=try await store.load();error=""} catch {self.error=error.localizedDescription}
  }
  func save(_ value:FavoriteQuery) async throws {items=try await store.save(value);error=""}
  func remove(_ id:UUID) async {
    do {items=try await store.remove(id);error=""} catch {self.error=error.localizedDescription}
  }
}

extension StudioState {
  @discardableResult func openFavorite(_ favorite:FavoriteQuery,contextServerID:UUID?,contextDatabase:String) throws -> QueryDocument {
    try favorite.validate()
    let target=favorite.scope == .global ? contextServerID:favorite.serverID
    guard let server=servers.first(where:{$0.id == target}) else {throw SQLFailure("Favorinin hedef bağlantısını önce Explorer’a ekleyin veya seçin.")}
    let database=favorite.scope == .database ? favorite.database! : favorite.scope == .connection && favorite.serverID != contextServerID ? server.profile.database:contextDatabase
    guard !database.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw SQLFailure("Hedef veritabanını seçin.")}
    return newQuery(server:server,database:database,text:favorite.sql,title:favorite.name,run:false)
  }
}

struct FavoriteQueriesPanel:View {
  let state:StudioState
  @ObservedObject var model:FavoriteQueriesModel
  @State var contextServerID:UUID?
  @State var contextDatabase:String
  var didOpen:()->Void = {}
  @State private var all=false
  @State private var search=""
  @State private var selected:UUID?
  @State private var edit:FavoriteQuery?
  @State private var creating=false
  @State private var deleting=false
  @State private var openError=""
  private var current:FavoriteQuery? {visible.first {$0.id == selected}}
  private var visible:[FavoriteQuery] {model.items.filter {(all || $0.visible(serverID:contextServerID,database:contextDatabase)) && (search.isEmpty || $0.name.localizedStandardContains(search))}}
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Favori Sorgular",icon:"star",subtitle:"Adlandır, kapsamını seç ve tekrar kullan")
      HStack {
        Picker("Explorer bağlantısı",selection:$contextServerID) {
          Text("Bağlantı seçin").tag(nil as UUID?)
          ForEach(state.servers) {Text($0.profile.name).tag(Optional($0.id))}
        }.frame(maxWidth:360)
        HStack {Text("Veritabanı").foregroundStyle(.secondary);TextField("Hedef veritabanı",text:$contextDatabase).accessibilityLabel("Hedef veritabanı")}
      }.onChange(of:contextServerID) {_,id in contextDatabase=state.servers.first {$0.id == id}?.profile.database ?? ""}
      HStack {
        TextField("Favori adı ara",text:$search)
        Toggle("Bütün kapsamlar",isOn:$all).fixedSize()
        StudioActionButton("Yeni",icon:"plus") {creating=true}
      }
      HSplitView {
        List(visible,selection:$selected) {item in
          VStack(alignment:.leading,spacing:4) {
            Label(item.name,systemImage:item.scope == .global ? "globe":item.scope == .connection ? "server.rack":"externaldrive")
            Text(scopeLabel(item)).font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical,5).tag(item.id)
        }.frame(minWidth:230,idealWidth:280,maxWidth:360).accessibilityIdentifier("favoriteList")
        VStack(alignment:.leading,spacing:12) {
          if let current {
            Text(current.name).font(.system(size:17,weight:.semibold))
            Text(scopeLabel(current)).foregroundStyle(.secondary)
            SQLReadOnlyPreview(sql:current.sql).frame(minHeight:200)
            Text("Açılacak hedef: "+targetLabel(current)).font(.caption).foregroundStyle(.secondary)
          } else {StudioEmptyState(title:"Bir favori seçin",icon:"star",detail:"Genel favoriler her bağlantıda, bağlantı ve veritabanı favorileri kendi kapsamlarında görünür.")}
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
      }
      if !model.error.isEmpty {Text(model.error).foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled)}
      if !openError.isEmpty {Text(openError).foregroundStyle(Color(nsColor:StudioTheme.danger))}
      HStack {
        StudioActionButton("Düzenle",icon:"pencil") {edit=current}.disabled(current == nil)
        StudioActionButton("Sil",icon:"trash",tint:Color(nsColor:StudioTheme.danger)) {deleting=true}.disabled(current == nil)
        Spacer()
        StudioActionButton("Sorguda Aç",icon:"arrow.up.right.square") {
          guard let current else {return}
          do {try state.openFavorite(current,contextServerID:contextServerID,contextDatabase:targetDatabase(current));openError="";didOpen()}
          catch {openError=error.localizedDescription}
        }.buttonStyle(StudioPrimaryButton()).disabled(current == nil).accessibilityIdentifier("favoriteOpen")
      }
      Text("Favoriler bu Mac’te saklanır. Sorguda Aç yeni bir sekme açar; SQL otomatik çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task {await model.load()}
      .sheet(isPresented:$creating) {FavoriteQueryEditor(model:model,servers:state.servers,contextServerID:contextServerID,database:contextDatabase,close:{creating=false})}
      .sheet(item:$edit) {favorite in FavoriteQueryEditor(model:model,servers:state.servers,contextServerID:contextServerID,database:contextDatabase,favorite:favorite,close:{edit=nil})}
      .confirmationDialog("Seçili favori silinsin mi?",isPresented:$deleting,titleVisibility:.visible) {
        Button("Favoriyi Sil",role:.destructive) {if let current {Task {await model.remove(current.id);selected=nil}}}
        Button("Vazgeç",role:.cancel) {}
      }
  }
  private func scopeLabel(_ favorite:FavoriteQuery) -> String {
    guard favorite.scope != .global else {return "Genel · Tüm bağlantılar"}
    let server=state.servers.first {$0.id == favorite.serverID}?.profile.name ?? "Explorer’da bulunmayan bağlantı"
    return favorite.scope == .connection ? "Bağlantı · "+server:"Veritabanı · "+server+" / "+(favorite.database ?? "")
  }
  private func targetDatabase(_ favorite:FavoriteQuery) -> String {
    if favorite.scope == .database {return favorite.database ?? ""}
    if favorite.scope == .global || favorite.serverID == contextServerID {return contextDatabase}
    return state.servers.first {$0.id == favorite.serverID}?.profile.database ?? ""
  }
  private func targetLabel(_ favorite:FavoriteQuery) -> String {
    let id=favorite.scope == .global ? contextServerID:favorite.serverID
    return (state.servers.first {$0.id == id}?.profile.name ?? "Bağlantı seçilmedi")+" / "+targetDatabase(favorite)
  }
}

struct FavoriteQueryEditor:View {
  @ObservedObject var model:FavoriteQueriesModel
  let servers:[ConnectedServer]
  let close:()->Void
  private let id:UUID
  @State private var name:String
  @State private var sql:String
  @State private var scope:FavoriteQuery.Scope
  @State private var serverID:UUID?
  @State private var database:String
  @State private var saving=false
  @State private var error=""
  init(model:FavoriteQueriesModel,servers:[ConnectedServer],contextServerID:UUID?,database:String,favorite:FavoriteQuery?=nil,sql:String="",name:String="",close:@escaping ()->Void) {
    self.model=model;self.servers=servers;self.close=close;id=favorite?.id ?? UUID()
    _name=State(initialValue:favorite?.name ?? name);_sql=State(initialValue:favorite?.sql ?? sql)
    _scope=State(initialValue:favorite?.scope ?? (contextServerID == nil ? .global:database.isEmpty ? .connection:.database))
    _serverID=State(initialValue:favorite?.serverID ?? contextServerID);_database=State(initialValue:favorite?.database ?? database)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Favori Sorgu",icon:"star",subtitle:"SQL’e bir ad ve kullanım kapsamı ver")
      StudioFormField("Ad") {TextField("Örneğin günlük satış özeti",text:$name).accessibilityIdentifier("favoriteName")}
      StudioFormField("Kapsam") {Picker("Kapsam",selection:$scope) {Text("Genel").tag(FavoriteQuery.Scope.global);Text("Explorer bağlantısı").tag(FavoriteQuery.Scope.connection);Text("Veritabanı").tag(FavoriteQuery.Scope.database)}.labelsHidden()}
      if scope != .global {
        StudioFormField("Explorer bağlantısı") {Picker("Explorer bağlantısı",selection:$serverID) {
          Text("Bağlantı seçin").tag(nil as UUID?)
          if let serverID,!servers.contains(where:{$0.id == serverID}) {Text("Explorer’da bulunmayan bağlantı").tag(Optional(serverID))}
          ForEach(servers) {Text($0.profile.name).tag(Optional($0.id))}
        }.labelsHidden()}
      }
      if scope == .database {StudioFormField("Veritabanı") {TextField("Veritabanı adı",text:$database)}}
      Text("SQL").fontWeight(.semibold)
      AgentCommandEditor(text:$sql).studioEditor().frame(minHeight:220)
      if !error.isEmpty {Text(error).foregroundStyle(Color(nsColor:StudioTheme.danger))}
      HStack {
        StudioActionButton("Vazgeç",icon:"xmark") {close()}.disabled(saving)
        Spacer()
        StudioActionButton("Favoriyi Kaydet",icon:"star.fill") {
          do {
            let value=try FavoriteQuery(id:id,name:name,sql:sql,scope:scope,serverID:serverID,database:database)
            saving=true
            Task {do {try await model.save(value);close()} catch {self.error=error.localizedDescription};saving=false}
          } catch {self.error=error.localizedDescription}
        }.buttonStyle(StudioPrimaryButton()).disabled(saving).accessibilityIdentifier("favoriteSave")
      }
    }.padding(20).frame(width:720,height:660).studioPanel()
  }
}
