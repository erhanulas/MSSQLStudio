import AppKit
import SwiftUI
import SQLServerKit

@MainActor struct SchemaEndpoint {
  let server: ConnectedServer
  let database: String
  var id: String {server.id.uuidString+"|"+database}
  var title: String {server.profile.name+" / "+database}
  func sameDatabase(as other:Self)->Bool {
    let a=server.profile,b=other.server.profile
    return a.host.caseInsensitiveCompare(b.host) == .orderedSame && a.port==b.port && database.caseInsensitiveCompare(other.database) == .orderedSame
  }
}
@MainActor final class SchemaComparisonModel: ObservableObject {
  typealias Reader = @MainActor @Sendable (SchemaEndpoint,String) async throws -> Execution
  let endpoints: [SchemaEndpoint]
  @Published var sourceID: String
  @Published var targetID: String
  @Published private(set) var differences: [SchemaDifference]=[]
  @Published private(set) var visible: [SchemaDifference]=[]
  @Published private(set) var busy=false
  @Published private(set) var applying=false
  @Published private(set) var message="İki veritabanı seçip Karşılaştır’a basın."
  @Published private(set) var error=""
  @Published var search="" {didSet {filter()}}
  @Published var kind="Tüm türler" {didSet {filter()}}
  @Published var onlyDifferences=true {didSet {filter()}}
  @Published var marked=Set<SchemaObjectKey>()
  @Published var focused: SchemaObjectKey?
  @Published private(set) var sourceSQL=""
  @Published private(set) var targetSQL=""
  @Published private(set) var detailLoading=false
  @Published private(set) var detailSummary="Bir nesne seçin."
  @Published private(set) var detailReady=false
  private(set) var sourceSnapshot: SchemaSnapshot?
  private(set) var targetSnapshot: SchemaSnapshot?
  private var sourceGeneration:UUID?,targetGeneration:UUID?
  private var contextCurrent:Bool {sourceGeneration != nil && targetGeneration != nil && sourceGeneration==source?.server.generation && targetGeneration==target?.server.generation}
  private var cache: [String:SchemaObjectContent]=[:]
  private var revision=UUID(),detailRevision=UUID()
  static private(set) var activeApplications=0
  var cancelOperation:(()->Void)?
  private var comparisonTask:Task<Void,Never>?
  func startComparison() {comparisonTask?.cancel();comparisonTask=Task {await compare()}}
  private let reader: Reader
  private let writer: Reader
  init(endpoints:[SchemaEndpoint],sourceID:String?=nil,targetID:String?=nil,reader:Reader?=nil,writer:Reader?=nil) {
    self.endpoints=endpoints
    let initialSource=sourceID ?? endpoints.first?.id ?? ""
    self.sourceID=initialSource
    self.targetID=targetID ?? endpoints.first(where:{$0.id != initialSource})?.id ?? ""
    self.reader=reader ?? {endpoint,sql in if let fixture=endpoint.server.schemaComparisonFixture {return try fixture(endpoint.database,sql)};return try await endpoint.server.catalog(sql,database:endpoint.database,limits:SchemaComparison.limits)}
    self.writer=writer ?? {endpoint,sql in guard endpoint.server.schemaComparisonFixture == nil else {throw SQLFailure("Çevrimdışı önizleme; SQL gönderilmez.")};var l=SchemaComparison.limits;l.timeout=120;return try await endpoint.server.catalog(sql,database:endpoint.database,limits:l)}
  }
  var source: SchemaEndpoint? {endpoints.first {$0.id==sourceID}}
  var target: SchemaEndpoint? {endpoints.first {$0.id==targetID}}
  var validPair: Bool {guard let source,let target else {return false};return source.server.online && target.server.online && !source.sameDatabase(as:target)}
  var currentDifference: SchemaDifference? {differences.first {$0.key==focused}}
  func invalidate() {
    revision=UUID();detailRevision=UUID();sourceGeneration=nil;targetGeneration=nil;differences=[];visible=[];marked=[];focused=nil;sourceSnapshot=nil;targetSnapshot=nil;cache=[:];sourceSQL="";targetSQL="";detailReady=false;detailLoading=false;error="";message="Seçim değişti. Yeniden karşılaştırın."
  }
  func cancel() {guard !applying else {return};comparisonTask?.cancel();cancelOperation?();invalidate();busy=false;message="Karşılaştırma iptal edildi."}
  func filter() {
    let text=search.trimmingCharacters(in:.whitespacesAndNewlines)
    visible=differences.filter {(!onlyDifferences || $0.status != .equal) && (kind=="Tüm türler" || ($0.source ?? $0.target)?.kind==kind) && (text.isEmpty || $0.key.qualified.localizedStandardContains(text))}
  }
  func compare() async {
    guard !busy,!applying,validPair,let source,let target else {return}
    invalidate();busy=true;message="DDL özetleri okunuyor…"
    let token=revision,sg=source.server.generation,tg=target.server.generation
    defer {if token==revision {busy=false}}
    do {
      async let a=reader(source,SchemaComparison.inventory())
      async let b=reader(target,SchemaComparison.inventory())
      let (ar,br)=try await (a,b)
      try Task.checkCancellation()
      let pair=try await Task.detached(priority:.userInitiated) {() throws -> (SchemaSnapshot,SchemaSnapshot,[SchemaDifference]) in
        let left=try SchemaComparison.decode(ar),right=try SchemaComparison.decode(br)
        return (left,right,try SchemaComparison.compare(source:left,target:right))
      }.value
      guard token==revision,sg==source.server.generation,tg==target.server.generation else {return}
      message="Farklı modüllerin kodları doğrulanıyor…"
      let keys=pair.2.filter {$0.status == .changed && $0.source?.type != "U" && $0.source?.type != "SN"}.map(\.key)
      async let refinedA=refine(pair.0,keys:keys,endpoint:source)
      async let refinedB=refine(pair.1,keys:keys,endpoint:target)
      let (left,right)=try await (refinedA,refinedB)
      guard token==revision,sg==source.server.generation,tg==target.server.generation else {return}
      let final=try await Task.detached(priority:.userInitiated) {try SchemaComparison.compare(source:left,target:right)}.value
      guard token==revision else {return}
      sourceSnapshot=left;targetSnapshot=right;sourceGeneration=sg;targetGeneration=tg;differences=final;filter()
      let count=differences.filter {$0.status != .equal}.count
      message="\(differences.count) nesne · \(count) fark / incelenecek nesne · \(differences.count-count) aynı"
    } catch {
      guard token==revision else {return};self.error=error is CancellationError ? "İşlem iptal edildi.":error.localizedDescription;message="Karşılaştırma tamamlanamadı."
    }
  }
  private func refine(_ snapshot:SchemaSnapshot,keys:[SchemaObjectKey],endpoint:SchemaEndpoint) async throws -> SchemaSnapshot {
    var result=snapshot
    for offset in stride(from:0,to:keys.count,by:64) {
      try Task.checkCancellation()
      let objects=keys[offset..<min(offset+64,keys.count)].compactMap {snapshot.objects[$0]}
      let execution=try await reader(endpoint,SchemaComparison.refinementQuery(objects))
      let previous=result
      result=try await Task.detached(priority:.userInitiated) {try SchemaComparison.refine(previous,objects:objects,result:execution)}.value
    }
    return result
  }
  private func readContent(_ object:SchemaObject,endpoint:SchemaEndpoint,expected:SchemaSnapshot,fresh:Bool=false) async throws -> SchemaObjectContent {
    let key=endpoint.id+"|"+String(object.objectID)+"|"+(object.digest ?? "")
    if !fresh,let hit=cache[key] {return hit}
    let result=try await reader(endpoint,SchemaComparison.contentQuery(object))
    let snapshot=try SchemaComparison.decode(await reader(endpoint,SchemaComparison.inventory(keys:[object.key])))
    try SchemaMigration.validateBaseline(expected,current:snapshot,keys:[object.key])
    let content=try await Task.detached(priority:.userInitiated) {try SchemaComparison.decodeContent(result,object:object)}.value
    if content.sql.utf8.count<2*1024*1024 {if cache.count>=24 {cache.removeAll()};cache[key]=content}
    return content
  }
  func loadDetail() async {
    detailRevision=UUID();let token=detailRevision
    sourceSQL="";targetSQL="";detailReady=false;detailSummary="Tanımlar okunuyor…"
    guard let difference=currentDifference,let source,let target,let a=sourceSnapshot,let b=targetSnapshot else {detailSummary="Bir nesne seçin.";return}
    guard contextCurrent else {detailSummary="Bağlantı değişti. Yeniden karşılaştırın.";return}
    detailLoading=true;let context=revision
    defer {if token==detailRevision {detailLoading=false}}
    do {
      var left="-- Kaynakta bu nesne yok.",right="-- Hedefte bu nesne yok."
      if let object=difference.source {left=try await readContent(object,endpoint:source,expected:a).sql}
      if let object=difference.target {right=try await readContent(object,endpoint:target,expected:b).sql}
      try Task.checkCancellation()
      guard token==detailRevision,context==revision else {return}
      sourceSQL=left;targetSQL=right;detailReady=true
      detailSummary=difference.status.rawValue+" · "+difference.key.qualified
      let issues=[difference.source?.issue,difference.target?.issue].compactMap {$0}.filter {!$0.isEmpty}
      if !issues.isEmpty {detailSummary+=" · "+issues.joined(separator:" · ")}
    } catch {guard token==detailRevision,context==revision else {return};detailSummary=error.localizedDescription}
  }
  func preparePlan() async -> SchemaMigrationPlan? {
    guard !busy,!applying,validPair,let source,let target,let a=sourceSnapshot,let b=targetSnapshot else {return nil}
    guard contextCurrent else {error="Bağlantı değişti. Yeniden karşılaştırın.";return nil}
    busy=true;error="";message="Seçilen nesnelerin taşıma önizlemesi hazırlanıyor…"
    let token=revision,selection=marked
    defer {if token==revision {busy=false}}
    do {
      let keys=try SchemaMigration.orderedKeys(selection,source:a,target:b)
      var left:[SchemaObjectKey:SchemaObjectContent]=[:],right:[SchemaObjectKey:SchemaObjectContent]=[:]
      for key in keys {
        try Task.checkCancellation()
        guard token==revision else {throw CancellationError()}
        if let object=a.objects[key] {left[key]=try await readContent(object,endpoint:source,expected:a)}
        if let object=b.objects[key] {right[key]=try await readContent(object,endpoint:target,expected:b)}
      }
      let plan=try await Task.detached(priority:.userInitiated) {try SchemaMigration.plan(selected:selection,source:a,target:b,sourceContent:left,targetContent:right)}.value
      guard token==revision else {return nil}
      message="\(keys.count) nesne · Hedef: \(target.title) · Henüz gönderilmedi"
      return plan
    } catch {guard token==revision else {return nil};self.error=error.localizedDescription;message="Önizleme oluşturulamadı.";return nil}
  }
  func apply(_ plan:SchemaMigrationPlan,sourceID:String,targetID:String) async {
    guard !busy,!applying,self.sourceID==sourceID,self.targetID==targetID,validPair,let source,let target,
      let a=sourceSnapshot,let b=targetSnapshot else {error="Karşılaştırma bağlamı değişti; yeniden önizleyin.";return}
    guard contextCurrent else {error="Bağlantı değişti. Yeniden karşılaştırın.";return}
    applying=true;Self.activeApplications+=1;var holdsApplication=true;defer {if holdsApplication {Self.activeApplications-=1}};error="";message="Hedef doğrulanıyor ve değişiklikler uygulanıyor…"
    let sg=source.server.generation,tg=target.server.generation
    do {
      try SchemaMigration.validateBaseline(plan.source,current:a,keys:plan.keys)
      try SchemaMigration.validateBaseline(plan.target,current:b,keys:plan.keys)
      async let ar=reader(source,SchemaComparison.inventory())
      async let br=reader(target,SchemaComparison.inventory())
      let (freshA,freshB)=try await (ar,br)
      let currentA=try SchemaComparison.decode(freshA),currentB=try SchemaComparison.decode(freshB)
      try SchemaMigration.validateBaseline(plan.source,current:currentA,keys:plan.keys)
      try SchemaMigration.validateBaseline(plan.target,current:currentB,keys:plan.keys)
      _=try SchemaMigration.orderedKeys(Set(plan.keys),source:currentA,target:currentB)
      guard sg==source.server.generation,tg==target.server.generation,source.server.online,target.server.online else {throw SQLFailure("Bağlantı değişti; yeniden karşılaştırın.")}
      let result=try await writer(target,plan.sql)
      guard !result.partial,!result.stoppedEarly else {throw SQLFailure("Gönderim sonucu tamamlanmadı. Otomatik tekrar yapılmadı; hedefi yeniden karşılaştırın.")}
      NotificationCenter.default.post(name:.init("studioSchemaComparedApplied"),object:target.server,userInfo:["database":target.database])
      applying=false;Self.activeApplications-=1;holdsApplication=false
      await compare()
      message="\(plan.keys.count) nesne hedefe uygulandı. "+message
    } catch {
      applying=false;self.error=error.localizedDescription+"\nOtomatik tekrar yapılmadı. Ağ kesildiyse sonucu hedefte yeniden karşılaştırın.";message="Taşıma tamamlanamadı."
    }
  }
}

struct SchemaComparisonPanel: View {
  @ObservedObject var model: SchemaComparisonModel
  let review: (String,String,String,String?) -> Void
  let preview: () -> Void
  let openSQL: (String) -> Void
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Veritabanı DDL Karşılaştırma",icon:"arrow.left.arrow.right.square",subtitle:"Nesne tanımlarını karşılaştırın, seçilen değişiklikleri hedefe taşıyın.")
      HStack(spacing:12) {
        endpoint("Kaynak",selection:$model.sourceID)
        StudioActionButton("Yönü Değiştir",icon:"arrow.left.arrow.right") {let old=model.sourceID;model.sourceID=model.targetID;model.targetID=old;model.invalidate()}.disabled(model.busy || model.applying)
        endpoint("Hedef",selection:$model.targetID)
        StudioActionButton("Karşılaştır",icon:"arrow.triangle.branch",tint:Color(nsColor:StudioTheme.success)) {model.startComparison()}.disabled(!model.validPair || model.busy || model.applying).accessibilityIdentifier("schemaCompare")
        if model.busy {ProgressView().controlSize(.small);StudioActionButton("İptal",icon:"xmark") {model.cancel()}}
      }.studioCard()
      HStack {
        TextField("Nesne veya şema ara…",text:$model.search).textFieldStyle(.roundedBorder).frame(maxWidth:300).accessibilityIdentifier("schemaSearch")
        Picker("Tür",selection:$model.kind) {ForEach(["Tüm türler","Tablo","View","Prosedür","Fonksiyon","Trigger","Synonym"],id:\.self) {Text($0)}}.frame(width:190)
        Toggle("Yalnız farklar",isOn:$model.onlyDifferences).toggleStyle(.checkbox)
        Spacer()
        Text("\(model.marked.count) seçili").foregroundStyle(.secondary)
        StudioActionButton("Görünenleri Seç",icon:"checkmark.square") {model.marked.formUnion(model.visible.filter { $0.canStage && !model.marked.contains($0.key) }.prefix(max(0,100-model.marked.count)).map(\.key))}.disabled(model.busy || model.applying)
        StudioActionButton("Seçimi Temizle",icon:"minus.square") {model.marked=[]}.disabled(model.applying)
      }
      if !model.error.isEmpty {Text(model.error).foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled).lineLimit(5)}
      VSplitView {
        Table(model.visible,selection:$model.focused) {
          TableColumn("Taşı") {row in
            Toggle("\(row.key.qualified) taşıma için seç",isOn:Binding(get:{model.marked.contains(row.key)},set:{if $0 {if model.marked.count<100 {model.marked.insert(row.key)}} else {model.marked.remove(row.key)};model.focused=row.key})).labelsHidden().toggleStyle(.checkbox).disabled(!row.canStage || model.applying || model.busy)
          }.width(40)
          TableColumn("Nesne") {row in Label(row.key.qualified,systemImage:symbol(row)).lineLimit(1).help(row.key.qualified)}.width(min:210,ideal:400)
          TableColumn("Tür") {Text(($0.source ?? $0.target)?.kind ?? "")}.width(95)
          TableColumn("Durum") {row in Label(row.status.rawValue,systemImage:statusSymbol(row.status)).foregroundStyle(Color(nsColor:tone(row.status))).help([row.source?.issue,row.target?.issue].compactMap {$0}.filter {!$0.isEmpty}.joined(separator:"\n"))}.width(min:160,ideal:190)
        }.frame(minHeight:160).accessibilityIdentifier("schemaDifferences")
        VStack(alignment:.leading,spacing:8) {
          HStack {
            if model.detailLoading {ProgressView().controlSize(.small)}
            Text(model.detailSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            StudioActionButton("Satır Farkları",icon:"text.magnifyingglass") {review(model.detailSummary,model.targetSQL,model.sourceSQL,nil)}.disabled(!model.detailReady || model.applying).accessibilityIdentifier("schemaLineDiff")
          }
          HSplitView {
            definition(title:model.target?.title ?? "Hedef",sql:model.targetSQL)
            definition(title:model.source?.title ?? "Kaynak",sql:model.sourceSQL)
          }.frame(minHeight:170)
        }.padding(.top,10).frame(minHeight:210)
      }
      HStack {
        VStack(alignment:.leading,spacing:4) {
          Text(model.message).font(.caption).textSelection(.enabled)
          Text("Veri, izin ve extended properties taşınmaz. Mevcut tablo silinmez/yeniden oluşturulmaz. Büyük farklarda Satır Farkları’nı açın.").font(.caption2).foregroundStyle(.secondary)
        }
        Spacer()
        if model.applying {ProgressView().controlSize(.small)}
        StudioActionButton("Hedefte SQL Sekmesi Aç",icon:"doc.text") {openSQL(model.sourceSQL)}.disabled(!model.detailReady || model.sourceSQL.isEmpty || model.applying)
        StudioActionButton("Taşıma Önizlemesi",icon:"paperplane") {preview()}.buttonStyle(StudioPrimaryButton()).disabled(model.marked.isEmpty || model.marked.count>100 || model.busy || model.applying).accessibilityIdentifier("schemaMigrationPreview")
      }
    }.padding(18).studioPanel()
      .onChange(of:model.sourceID) {_,_ in model.invalidate()}
      .onChange(of:model.targetID) {_,_ in model.invalidate()}
      .task(id:model.focused) {await model.loadDetail()}
  }
  private func endpoint(_ title:String,selection:Binding<String>)->some View {
    VStack(alignment:.leading,spacing:4) {Text(title).font(.caption).foregroundStyle(.secondary);Picker(title,selection:selection) {Text("Veritabanı seçin").tag("");ForEach(model.endpoints,id:\.id) {Text($0.title).tag($0.id)}}.labelsHidden().accessibilityLabel(title+" veritabanı")}.frame(maxWidth:.infinity).disabled(model.busy || model.applying)
  }
  private func definition(title:String,sql:String)->some View {
    VStack(alignment:.leading,spacing:6) {Text(title).font(.caption.weight(.semibold));SQLReadOnlyPreview(sql:String(sql.prefix(200_000))).frame(maxWidth:.infinity,maxHeight:.infinity)}.padding(8).frame(minWidth:250)
  }
  private func symbol(_ row:SchemaDifference)->String {switch (row.source ?? row.target)?.type {case "U":return "tablecells";case "V":return "eye";case "TR","TRD","TA":return "bolt";case "P","PC":return "gearshape.2";case "SN":return "link";default:return "function"}}
  private func statusSymbol(_ status:SchemaDifference.Status)->String {switch status {case .equal:return "equal.circle";case .changed:return "plusminus.circle";case .sourceOnly:return "plus.circle";case .targetOnly:return "minus.circle";default:return "exclamationmark.triangle"}}
  private func tone(_ status:SchemaDifference.Status)->NSColor {switch status {case .equal:return StudioTheme.success;case .changed:return StudioTheme.warning;case .sourceOnly:return StudioTheme.accent;case .targetOnly:return .secondaryLabelColor;default:return StudioTheme.danger}}
}

@MainActor final class SchemaComparisonWindow: NSWindowController,NSWindowDelegate {
  let model: SchemaComparisonModel
  private var operation: Task<Void,Never>?
  private var review: ModuleReviewController?
  init(model:SchemaComparisonModel,openSQL:@escaping (SchemaEndpoint,String)->Void) {
    self.model=model
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    super.init(window:window)
    model.cancelOperation={[weak self] in self?.operation?.cancel()}
    window.title="DDL Karşılaştırma";window.minSize=NSSize(width:1000,height:680);window.delegate=self
    let panel=SchemaComparisonPanel(model:model,review:{[weak self] title,old,new,sql in self?.showReview(title:title,old:old,new:new,sql:sql)},preview:{[weak self] in self?.prepare()},openSQL:{[weak model] sql in if let target=model?.target {openSQL(target,sql)}})
    let hosting=NSHostingController(rootView:panel)
    hosting.sizingOptions=[]
    window.contentViewController=hosting
    window.setContentSize(NSSize(width:1280,height:850))
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  private func prepare() {
    operation=Task {[weak self] in
      guard let self,let plan=await model.preparePlan(),!Task.isCancelled else {return}
      let target=model.target?.title ?? "",sourceID=model.sourceID,targetID=model.targetID
      showReview(title:"\(model.source?.title ?? "") → \(target) · \(plan.keys.count) nesne\n"+plan.warnings.joined(separator:"\n"),old:plan.originalSQL,new:plan.desiredSQL,sql:plan.sql,approve:{[weak self] in
        guard let self else {return};operation=Task {await self.model.apply(plan,sourceID:sourceID,targetID:targetID)}
      })
    }
  }
  private func showReview(title:String,old:String,new:String,sql:String?,approve:(()->Void)?=nil) {
    guard let window,review==nil else {return}
    review=ModuleReviewController(parent:window,title:title,original:old,edited:new,canApply:approve != nil,leftTitle:model.target?.title ?? "Hedef",rightTitle:model.source?.title ?? "Kaynak",executionSQL:sql,approved:{approve?()},finished:{[weak self] in self?.review=nil})
  }
  func windowShouldClose(_ sender:NSWindow)->Bool {if model.applying {NSSound.beep();return false};operation?.cancel();model.cancel();return true}
}
/// Entirely offline fixture. SQL application is explicitly rejected by the model's default writer.
@MainActor enum SchemaComparisonUIFixture {
  static func server()->ConnectedServer {
    let server=ConnectedServer(profile:ServerProfile(name:"DDL Demo"),password:"")
    server.catalogFixture=ObjectManagementUIFixture.catalog
    server.schemaComparisonFixture=catalog
    server.databases=[CatalogItem(id:5,name:"SourceDB"),CatalogItem(id:6,name:"TargetDB")]
    return server
  }
  static func catalog(_ database:String,_ sql:String) throws -> Execution {
    let source=database=="SourceDB"
    let objects:[[String?]]=[
      ["101","dbo","usp_Customers","P",String(repeating:source ? "a":"b",count:64),""],
      ["102","dbo","v_Orders","V",String(repeating:"c",count:64),""],
      source ? ["103","dbo","ufn_Total","FN",String(repeating:"d",count:64),""]:["104","dbo","usp_Legacy","P",String(repeating:"e",count:64),""],
      ["105","dbo","usp_Encrypted","P",nil,"Tanım şifreli veya görünmüyor."]]
    func body(_ id:Int)->String {switch id {case 101:return "CREATE PROCEDURE [dbo].[usp_Customers]\nAS\nBEGIN\n    SET NOCOUNT ON;\n    SELECT [CustomerID], [Name]"+(source ? ", [City]":"")+"\n    FROM [dbo].[Customers];\nEND;";case 102:return "CREATE VIEW [dbo].[v_Orders] AS SELECT 1 AS [OrderID];";case 103:return "CREATE FUNCTION [dbo].[ufn_Total]() RETURNS int AS BEGIN RETURN 42; END;";default:return "CREATE PROCEDURE [dbo].[usp_Legacy] AS SELECT 1;"}}
    var result=Execution()
    if sql.contains("StudioSchemaInventory") {
      result.results=[Rows(values:[["1",database]]),Rows(values:objects),Rows(values:[])]
    } else if sql.contains("StudioSchemaRefinement") {
      result.results=[Rows(values:[["101",body(101),"1","1","0",nil]])]
    } else if sql.contains("sys.sql_modules") {
      let id=[101,102,103,104].first {sql.contains("=\($0)")} ?? 101
      result.results=[Rows(values:[[body(id),"1","1","0",nil]])]
    } else {throw SQLFailure("Çevrimdışı DDL fixture bu sorguyu desteklemiyor.")}
    return result
  }
}
