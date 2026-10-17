import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class ActivitySQLTextPreviewModel:ObservableObject {
  typealias Reader=@MainActor (String,Limits) async throws -> Execution
  @Published private(set) var text=""
  @Published private(set) var loading=false
  @Published private(set) var error=""
  @Published private(set) var complete=false
  private(set) var identity=""
  private let server:ConnectedServer
  private let reader:Reader
  private var task:Task<Void,Never>?
  private var pending:(handle:String,generation:UUID,revision:UUID)?
  private var revision=UUID()
  init(server:ConnectedServer,reader:Reader?=nil) {
    self.server=server
    self.reader=reader ?? { [weak server] sql,limits in
      guard let server,server.online else {throw SQLFailure("Bağlantı kapalı.")}
      return try await server.catalog(sql,database:"master",limits:limits)
    }
  }
  deinit {task?.cancel()}
  static func identity(handle:String?,generation:UUID)->String {generation.uuidString+"|"+(handle ?? "")}
  func show(handle:String?,prefix:String,generation:UUID) {
    let key=Self.identity(handle:handle,generation:generation)
    guard identity != key else {if handle?.isEmpty != false {text=prefix};return}
    identity=key;revision=UUID();task?.cancel();pending=nil
    text=prefix;error="";complete=false;loading=false
    guard let handle,!handle.isEmpty else {error="Tam SQL metni için DBA listesini yenileyin.";return}
    loading=true;pending=(handle,generation,revision);startPending()
  }
  func cancel() {revision=UUID();identity="";pending=nil;task?.cancel();loading=false}
  private func startPending() {
    guard task==nil,let request=pending else {return}
    pending=nil
    let reader=reader
    task=Task { [weak self] in
      var result:Result<String,Error>
      do {
        let sql=try ActivitySQLText.sql(handle:request.handle)
        var limits=Limits();limits.rows=2;limits.resultSets=1;limits.totalBytes=4*1024*1024;limits.timeout=10
        result = .success(try ActivitySQLText.decode(await reader(sql,limits)))
      } catch {result = .failure(error)}
      guard let self else {return}
      if revision==request.revision,server.generation==request.generation,server.online,!Task.isCancelled {
        switch result {
        case .success(let sql):text=sql;complete=true;error=""
        case .failure(let failure):error=failure.localizedDescription
        }
        loading=false
      } else if revision==request.revision {loading=false;error="Bağlantı değişti; DBA listesini yenileyin."}
      task=nil;startPending()
    }
  }
}

struct ActivitySQLTextPreview:View {
  let server:ConnectedServer
  let handle:String?
  let prefix:String
  @StateObject private var model:ActivitySQLTextPreviewModel
  init(server:ConnectedServer,handle:String?,prefix:String) {
    self.server=server;self.handle=handle;self.prefix=prefix
    _model=StateObject(wrappedValue:ActivitySQLTextPreviewModel(server:server))
  }
  private var identity:String {ActivitySQLTextPreviewModel.identity(handle:handle,generation:server.generation)}
  private var current:Bool {model.identity==identity}
  private var sql:String {current && handle?.isEmpty == false ? model.text:prefix}
  var body:some View {
    VStack(alignment:.leading,spacing:4) {
      HStack {
        Text(current && !model.error.isEmpty ? "SQL · Tam metin okunamadı":current && model.complete ? "SQL · Tam batch / modül metni":"SQL · Örnek metin")
          .font(.caption2).foregroundStyle(current && !model.error.isEmpty ? Color(nsColor:StudioTheme.warning):.secondary)
          .lineLimit(1).studioHelp(current ? model.error:"")
        Spacer(minLength:0)
        Button {NSPasteboard.general.clearContents();NSPasteboard.general.setString(sql,forType:.string)} label: {Image(systemName:"doc.on.doc")}
          .buttonStyle(.borderless).disabled(!current || sql.isEmpty || model.loading)
          .accessibilityIdentifier("activityCopySQL").accessibilityLabel(current && model.complete ? "SQL’i Kopyala":"Örneği Kopyala")
          .studioHelp(current && model.complete ? "Tam SQL metnini kopyala":"Görünen kısa örneği kopyala")
      }
      SQLReadOnlyPreview(sql:sql.isEmpty ? "-- SQL metni sağlanmadı veya okunamıyor.":sql)
        .frame(minHeight:100,idealHeight:115,maxHeight:150)
        .overlay {
          if current && model.loading {StudioLoadingView(title:"SQL metni alınıyor",context:server.profile.name,phase:"Seçili örneğin tam batch / modül metni okunuyor…").frame(maxWidth:320)}
        }
    }
    .onAppear {model.show(handle:handle,prefix:prefix,generation:server.generation)}
    .onChange(of:identity) {_,_ in model.show(handle:handle,prefix:prefix,generation:server.generation)}
    .onDisappear {model.cancel()}
  }
}
