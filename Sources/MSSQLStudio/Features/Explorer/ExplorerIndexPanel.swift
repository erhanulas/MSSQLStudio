import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct ExplorerIndexPanel: View {
  let server:ConnectedServer
  let databases:[String]
  let refresh:()->Void
  @State private var revision=UUID()
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Label("Yerel indeks",systemImage:"externaldrive").font(.title3.bold())
      Text(server.profile.name).foregroundStyle(.secondary)
      ScrollView {
        VStack(spacing:12) {
          ForEach(databases,id:\.self) {db in ExplorerIndexCard(server:server,database:db).id(revision.uuidString+db)}
        }
      }.frame(maxHeight:420)
      Text("Bu Mac’teki arama ve SQL önerisi önbelleği.").font(.caption).foregroundStyle(.secondary)
      StudioActionButton("Yerel İndeksi Yenile",icon:"arrow.clockwise",tint:.accentColor,action:refresh).disabled(!server.online)
    }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity).studioPanel()
      .onReceive(NotificationCenter.default.publisher(for:.init("catalogIndexUpdated"))) {note in
        if let updated=note.object as? ConnectedServer,updated === server {revision=UUID()}
      }
  }
}

@MainActor private struct ExplorerIndexCard:View {
  let server:ConnectedServer
  let database:String
  @State private var count:Int?
  @State private var objectDate:Date?
  @State private var columnDate:Date?
  @State private var fresh=false
  @State private var loading=true
  @State private var error:String?
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        Label(database,systemImage:"cylinder.split.1x2").font(.headline)
        Spacer()
        if loading {ProgressView().controlSize(.small)}
        else {Label(error != nil ? "Hata" : server.indexingDatabases.contains(database) ? "Hazırlanıyor" : count == nil ? "Hazır değil" : "Hazır",systemImage:error != nil ? "exclamationmark.triangle" : count == nil ? "clock" : "checkmark.circle.fill").foregroundStyle(error != nil ? .orange : count == nil ? .secondary : .green).font(.caption)}
      }
      HStack(alignment:.top,spacing:12) {
        metric("Nesneler",value:count.map(String.init) ?? "—",icon:"square.stack.3d.up",date:objectDate)
        metric("SQL kolonları",value:columnDate == nil ? "Hazır değil" : fresh ? "Güncel" : "Yenileme gerekli",icon:"tablecells",date:columnDate)
      }
      if let error {Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
      if !server.online {Label("Bağlantı kapalı · önbellek bilgisi",systemImage:"network.slash").font(.caption).foregroundStyle(.secondary)}
    }.padding(14).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
      .task {
        do {
          let objects=try await CatalogDiskIndex.shared.status(scope:CatalogDiskIndex.scope(profile:server.profile,database:database))
          let columns=try await SQLCatalogService.shared.cached(profile:server.profile,database:database)
          count=objects?.count;objectDate=objects?.synchronizedAt;columnDate=columns?.snapshot.synchronizedAt;fresh=columns?.fresh == true
          error=server.indexErrors[database]
        } catch {self.error=error.localizedDescription}
        loading=false
      }
  }
  private func metric(_ title:String,value:String,icon:String,date:Date?) -> some View {
    VStack(alignment:.leading,spacing:7) {
      Label(title,systemImage:icon).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.headline)
      Text(date?.formatted(date:.abbreviated,time:.shortened) ?? "Henüz eşitlenmedi").font(.caption2).foregroundStyle(.secondary)
    }.padding(10).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
  }
}

@MainActor struct ExplorerDatabasePanel:View {
  let server:ConnectedServer
  let database:String
  @State private var sections:[(title:String,fields:[(String,String)])]=[]
  @State private var loading=false
  @State private var error:String?
  @State private var revision=UUID()
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      HStack {
        Label(database,systemImage:"cylinder.split.1x2").font(.title2.bold())
        Spacer()
        StudioActionButton("Yenile",icon:"arrow.clockwise",tint:.accentColor) {revision=UUID()}.disabled(loading || !server.online)
      }
      Text(server.profile.name+" · Salt okunur veritabanı bilgileri").foregroundStyle(.secondary)
      Divider()
      if loading {ProgressView("Veritabanı bilgileri yükleniyor…")}
      if let error {Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)}
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          ForEach(sections.indices,id:\.self) {index in
            VStack(alignment:.leading,spacing:12) {
              Label(sections[index].title,systemImage:sections[index].title == "Genel" ? "info.circle" : "doc").font(.headline)
              ForEach(sections[index].fields.indices,id:\.self) {row in
                let field=sections[index].fields[row]
                StudioFormField(field.0) {Text(field.1).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
              }
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
          }
        }
      }
      Spacer(minLength:0)
    }.padding(20).studioPanel().task(id:revision) {await load()}
  }
  private func load() async {
    guard server.online else {error="Sunucu bağlantısı kapalı. Bilgileri yüklemek için yeniden bağlanın.";return}
    loading=true;error=nil
    defer {loading=false}
    do {
      let result=try await server.catalog("SELECT name,state_desc,recovery_model_desc,compatibility_level,collation_name,is_read_only FROM sys.databases WHERE name=\(SQL.literal(database)); SELECT name,type_desc,CAST(size*8.0/1024 AS decimal(18,2)) AS size_mb,physical_name FROM sys.database_files;",database:database)
      guard !Task.isCancelled else {return}
      let general=["Ad","Durum","Kurtarma modeli","Uyumluluk düzeyi","Karşılaştırma düzeni","Salt okunur"]
      let files=["Ad","Tür","Boyut (MB)","Dosya yolu"]
      sections=[]
      for (index,set) in result.results.enumerated() {
        for row in set.values {
          let labels=index == 0 ? general : files
          sections.append((index == 0 ? "Genel" : "Dosya \(sections.count)",row.enumerated().map {offset,value in (offset < labels.count ? labels[offset] : "Değer",value ?? "—")}))
        }
      }
      if sections.isEmpty {error="Veritabanı bilgisi dönmedi; erişim izinlerini kontrol edin."}
    } catch {self.error=error.localizedDescription}
  }
}

private extension View {
  func explorerInfoCard() -> some View {
    background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:8))
      .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:StudioTheme.border),lineWidth:1))
  }
}
