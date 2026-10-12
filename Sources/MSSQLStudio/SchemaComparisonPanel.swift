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
enum SchemaDetailMode: String,CaseIterable {case code="Kod Farkı",columns="Kolonlar"}

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
  @Published private(set) var detailComparison: SQLTextDiff.Comparison?
  @Published private(set) var columnDifferences:[SchemaColumnDifference]=[]
  @Published private(set) var columnsReady=false
  @Published private(set) var detailNotice=""
  @Published private(set) var diffTruncated=false
  @Published var detailMode=SchemaDetailMode.code
  @Published var columnOnlyDifferences=true
  @Published var changeIndex=0
  var changedGroups:[Int] {detailComparison.map {SQLInlineDiffView.changeRows(in:$0)} ?? []}
  var visibleColumns:[SchemaColumnDifference] {columnOnlyDifferences ? columnDifferences.filter {!$0.isEqual}:columnDifferences}
  var hasColumns:Bool {["U","V"].contains((currentDifference?.source ?? currentDifference?.target)?.type ?? "")}
  var columnChangeCount:Int {columnDifferences.filter {!$0.isEqual}.count}
  var columnSummary:String {columnsReady ? "\(columnDifferences.count) kolon · \(columnChangeCount) farklı":detailLoading ? "Kolonlar okunuyor…":"Kolonlar alınamadı"}
  var sameCount:Int {differences.filter {$0.status == .equal}.count}
  var differentCount:Int {differences.count-sameCount}
  func moveChange(_ offset:Int) {guard !changedGroups.isEmpty else {return};changeIndex=(changeIndex+offset+changedGroups.count)%changedGroups.count}
  private(set) var sourceSnapshot: SchemaSnapshot?
  private(set) var targetSnapshot: SchemaSnapshot?
  private var sourceGeneration:UUID?,targetGeneration:UUID?
  private var contextCurrent:Bool {sourceGeneration != nil && targetGeneration != nil && sourceGeneration==source?.server.generation && targetGeneration==target?.server.generation}
  private var cache: [String:SchemaObjectContent]=[:]
  private var columnCache:[String:[SchemaColumn]]=[:]
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
    revision=UUID();detailRevision=UUID();sourceGeneration=nil;targetGeneration=nil;differences=[];visible=[];marked=[];focused=nil;sourceSnapshot=nil;targetSnapshot=nil;cache=[:];columnCache=[:];sourceSQL="";targetSQL="";detailReady=false;detailLoading=false;detailComparison=nil;columnDifferences=[];columnsReady=false;detailNotice="";diffTruncated=false;changeIndex=0;error="";message="Seçim değişti. Yeniden karşılaştırın."
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
      guard token==revision,sg==source.server.generation,tg==target.server.generation else {return}
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
  private func readColumns(_ object:SchemaObject,endpoint:SchemaEndpoint,expected:SchemaSnapshot) async throws -> [SchemaColumn] {
    let key=endpoint.id+"|"+String(object.objectID)+"|"+(object.digest ?? "")
    if let hit=columnCache[key] {return hit}
    let result=try await reader(endpoint,SchemaComparison.columnsQuery(object))
    let snapshot=try SchemaComparison.decode(await reader(endpoint,SchemaComparison.inventory(keys:[object.key])))
    try SchemaMigration.validateBaseline(expected,current:snapshot,keys:[object.key])
    let columns=try await Task.detached(priority:.userInitiated) {try SchemaComparison.decodeColumns(result,object:object)}.value
    let bytes=columns.reduce(0) {$0+$1.name.utf8.count+$1.dataType.utf8.count+$1.attributes.utf8.count+$1.collation.utf8.count+128}
    if bytes<2*1024*1024 {if columnCache.count>=24 {columnCache.removeAll()};columnCache[key]=columns}
    return columns
  }
  private func columnsIfPresent(_ object:SchemaObject?,endpoint:SchemaEndpoint,expected:SchemaSnapshot) async throws -> [SchemaColumn] {
    guard let object else {return []}
    return try await readColumns(object,endpoint:endpoint,expected:expected)
  }
  func loadDetail() async {
    detailRevision=UUID();let token=detailRevision
    sourceSQL="";targetSQL="";detailReady=false;detailLoading=false;detailComparison=nil;columnsReady=false;columnDifferences=[];detailNotice="";diffTruncated=false;changeIndex=0
    guard let difference=currentDifference,let source,let target,let a=sourceSnapshot,let b=targetSnapshot else {detailSummary="Bir nesne seçin.";return}
    guard contextCurrent else {detailSummary="Bağlantı değişti. Yeniden karşılaştırın.";return}
    detailLoading=true;detailSummary=difference.key.qualified;let context=revision
    let columnObject=["U","V"].contains((difference.source ?? difference.target)?.type ?? "")
    detailMode=columnObject ? .columns:.code
    defer {if token==detailRevision {detailLoading=false}}
    do {
      var notices:[String]=[]
      if columnObject {
        do {
          async let sourceColumns=columnsIfPresent(difference.source,endpoint:source,expected:a)
          async let targetColumns=columnsIfPresent(difference.target,endpoint:target,expected:b)
          let (sc,tc)=try await (sourceColumns,targetColumns)
          let rows=try await Task.detached(priority:.userInitiated) {try SchemaComparison.compareColumns(source:sc,target:tc)}.value
          guard token==detailRevision,context==revision else {return}
          guard contextCurrent else {throw SQLFailure("Bağlantı değişti. Yeniden karşılaştırın.")}
          try Task.checkCancellation()
          columnDifferences=rows;columnsReady=true;detailReady=true
        } catch is CancellationError {throw CancellationError()}
        catch {notices.append("Kolonlar: "+error.localizedDescription)}
      }
      var old="-- Hedefte bu nesne yok.",new="-- Kaynakta bu nesne yok."
      var codeFailures:[String]=[]
      for (object,endpoint,snapshot,isSource) in [(difference.target,target,b,false),(difference.source,source,a,true)] {
        guard let object else {continue}
        if object.type=="U",!object.issue.isEmpty {
          codeFailures.append("Özel tablo için SQL üretimi kapalı; kolonları inceleyebilirsiniz.")
          continue
        }
        do {
          let content=try await readContent(object,endpoint:endpoint,expected:snapshot)
          if isSource {new=content.sql} else {old=content.sql}
        } catch is CancellationError {throw CancellationError()}
        catch {codeFailures.append(endpoint.database+": "+error.localizedDescription)}
      }
      try Task.checkCancellation()
      guard token==detailRevision,context==revision else {return}
      guard contextCurrent else {throw SQLFailure("Bağlantı değişti. Yeniden karşılaştırın.")}
      if codeFailures.isEmpty {
        let limitedOld=String(old.prefix(200_000)),limitedNew=String(new.prefix(200_000))
        let comparison=await Task.detached(priority:.userInitiated) {SQLTextDiff.compare(limitedOld,limitedNew)}.value
        guard token==detailRevision,context==revision else {return}
        guard contextCurrent else {throw SQLFailure("Bağlantı değişti. Yeniden karşılaştırın.")}
        try Task.checkCancellation()
        sourceSQL=new;targetSQL=old;detailComparison=comparison;detailReady=true
        diffTruncated=old.count>200_000 || new.count>200_000 || comparison.lines.count>10_000
      }
      detailSummary=difference.key.qualified
      var shown=Set<String>()
      detailNotice=([difference.migrationIssue]+notices+codeFailures).filter {!$0.isEmpty && shown.insert($0).inserted}.joined(separator:" · ")
    } catch {
      guard token==detailRevision,context==revision else {return}
      if !contextCurrent {columnsReady=false;columnDifferences=[];detailReady=false;detailComparison=nil;sourceSQL="";targetSQL=""}
      detailSummary=difference.key.qualified
      detailNotice=error.localizedDescription
    }
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
      guard contextCurrent else {throw SQLFailure("Bağlantı değişti. Yeniden karşılaştırın.")}
      try Task.checkCancellation()
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
  let preview: () -> Void
  let openSQL: (String) -> Void
  var body: some View {
    VStack(alignment:.leading,spacing:10) {
      heading
      endpoints
      filters
      if !model.error.isEmpty {
        Label(model.error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled).lineLimit(3)
      }
      VSplitView {
        objects.frame(minHeight:140,idealHeight:230)
        details.frame(minHeight:250,idealHeight:420)
      }
      footer
    }.padding(14).studioPanel().controlSize(.small)
      .onChange(of:model.sourceID) {_,_ in model.invalidate()}
      .onChange(of:model.targetID) {_,_ in model.invalidate()}
      .task(id:model.focused) {await model.loadDetail()}
  }
  private var heading:some View {
    HStack(spacing:9) {
      Image(systemName:"arrow.left.arrow.right.square").font(.system(size:19,weight:.medium)).foregroundStyle(Color(nsColor:StudioTheme.accent))
      Text("DDL Karşılaştırma").font(.system(size:16,weight:.semibold))
      Spacer(minLength:12)
      if !model.differences.isEmpty {
        metric("İncelenecek",count:model.differentCount,color:StudioTheme.warning)
        metric("Aynı",count:model.sameCount,color:StudioTheme.success)
      }
    }.frame(height:28)
  }
  private var endpoints:some View {
    HStack(spacing:10) {
      endpoint("Kaynak",icon:"arrow.up.forward",selection:$model.sourceID)
      StudioActionButton("Kaynak ve hedefi değiştir",icon:"arrow.left.arrow.right") {
        let old=model.sourceID;model.sourceID=model.targetID;model.targetID=old;model.invalidate()
      }.labelStyle(.iconOnly).disabled(model.busy || model.applying).accessibilityIdentifier("schemaSwap")
      endpoint("Hedef",icon:"arrow.down.forward",selection:$model.targetID)
      if model.busy {ProgressView().controlSize(.small)}
      StudioActionButton(model.busy ? "İptal":"Karşılaştır",icon:model.busy ? "xmark":"arrow.triangle.branch",tint:Color(nsColor:model.busy ? StudioTheme.warning:StudioTheme.success)) {
        if model.busy {model.cancel()} else {model.startComparison()}
      }.disabled((!model.validPair && !model.busy) || model.applying).accessibilityIdentifier("schemaCompare")
    }.studioCard(padding:10)
  }
  private var filters:some View {
    HStack(spacing:10) {
      TextField("Nesne veya şema ara…",text:$model.search).textFieldStyle(.roundedBorder).frame(minWidth:160,maxWidth:300).accessibilityIdentifier("schemaSearch")
      Picker("Nesne türü",selection:$model.kind) {ForEach(["Tüm türler","Tablo","View","Prosedür","Fonksiyon","Trigger","Synonym"],id:\.self) {Text($0)}}.labelsHidden().frame(width:145).accessibilityLabel("Nesne türü")
      Toggle("Yalnız farklar",isOn:$model.onlyDifferences).toggleStyle(.checkbox)
      Spacer(minLength:0)
      Text("\(model.visible.count) nesne · \(model.marked.count) seçili").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      StudioActionButton("Görünen taşınabilir nesneleri seç",icon:"checkmark.square") {
        model.marked.formUnion(model.visible.filter {$0.canStage && !model.marked.contains($0.key)}.prefix(max(0,100-model.marked.count)).map(\.key))
      }.labelStyle(.iconOnly).disabled(model.busy || model.applying).accessibilityIdentifier("schemaSelectVisible")
      StudioActionButton("Seçimi temizle",icon:"minus.square") {model.marked=[]}.labelStyle(.iconOnly).disabled(model.marked.isEmpty || model.applying).accessibilityIdentifier("schemaClearSelection")
    }
  }
  private var objects:some View {
    Table(model.visible,selection:$model.focused) {
      TableColumn("Taşı") {row in
        Toggle("\(row.key.qualified) taşıma için seç",isOn:Binding(get:{model.marked.contains(row.key)},set:{if $0 {if model.marked.count<100 {model.marked.insert(row.key)}} else {model.marked.remove(row.key)};model.focused=row.key}))
          .labelsHidden().toggleStyle(.checkbox).disabled(!row.canStage || model.applying || model.busy).help(row.migrationIssue.isEmpty ? "Taşıma önizlemesine ekle":row.migrationIssue)
      }.width(36)
      TableColumn("Nesne") {row in Label(row.key.qualified,systemImage:symbol(row)).lineLimit(1).help(row.key.qualified)}.width(min:200,ideal:440)
      TableColumn("Tür") {Text(($0.source ?? $0.target)?.kind ?? "")}.width(90)
      TableColumn("Durum") {row in
        Group {
          if model.focused==row.key {Label(row.status.rawValue,systemImage:statusSymbol(row.status))}
          else {Label(row.status.rawValue,systemImage:statusSymbol(row.status)).foregroundStyle(Color(nsColor:tone(row.status)))}
        }.help(row.migrationIssue)
      }.width(min:160,ideal:190)
    }.accessibilityIdentifier("schemaDifferences")
      .overlay {if model.visible.isEmpty && !model.busy {
        StudioEmptyState(title:model.differences.isEmpty ? "Karşılaştırmaya hazır":"Eşleşen nesne yok",icon:model.differences.isEmpty ? "arrow.triangle.branch":"line.3.horizontal.decrease",detail:model.differences.isEmpty ? "Kaynak ve hedefi seçip Karşılaştır’a basın.":"Aramayı veya filtreleri değiştirin.").padding(.top,28)
      }}
  }
  private var details:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack(spacing:10) {
        if model.detailLoading {ProgressView().controlSize(.small)}
        Text(model.detailSummary).font(.system(size:12,weight:.semibold)).lineLimit(1).help(model.detailSummary)
        Spacer(minLength:8)
        if model.hasColumns {
          Picker("Karşılaştırma görünümü",selection:$model.detailMode) {
            ForEach(SchemaDetailMode.allCases,id:\.self) {Text($0.rawValue).tag($0)}
          }.pickerStyle(.segmented).labelsHidden().frame(width:180).accessibilityIdentifier("schemaDetailMode")
        }
        if model.detailMode == .code,let comparison=model.detailComparison {
          Text("−\(comparison.removed)  +\(comparison.added)").monospacedDigit().font(.caption).foregroundStyle(.secondary)
          Text(model.changedGroups.isEmpty ? "Kod aynı":"\(model.changeIndex+1)/\(model.changedGroups.count)").font(.caption).foregroundStyle(.secondary)
          StudioActionButton("Önceki kod farkı",icon:"chevron.up") {model.moveChange(-1)}.labelStyle(.iconOnly).disabled(model.changedGroups.isEmpty).accessibilityIdentifier("schemaPreviousDifference")
          StudioActionButton("Sonraki kod farkı",icon:"chevron.down") {model.moveChange(1)}.labelStyle(.iconOnly).disabled(model.changedGroups.isEmpty).accessibilityIdentifier("schemaNextDifference")
        }
      }.frame(minHeight:28)
      if !model.detailNotice.isEmpty {
        Label(model.detailNotice,systemImage:"info.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).help(model.detailNotice)
      }
      if model.detailMode == .columns,model.hasColumns {
        columns
      } else if let comparison=model.detailComparison {
        HStack(spacing:0) {
          sideTitle("Hedef",name:model.target?.title ?? "",color:StudioTheme.danger)
          sideTitle("Kaynak",name:model.source?.title ?? "",color:StudioTheme.success)
        }
        SQLInlineDiffPreview(comparison:comparison,original:String(model.targetSQL.prefix(200_000)),edited:String(model.sourceSQL.prefix(200_000)),changeIndex:model.changeIndex).accessibilityIdentifier("schemaInlineDiff")
        if model.diffTruncated {Text("Büyük tanım için sınırlı önizleme gösteriliyor; tam kaynak kodunu SQL sekmesinde açabilirsiniz.").font(.caption2).foregroundStyle(.secondary)}
        else if model.changedGroups.isEmpty,model.currentDifference?.status == .changed {
          Text(model.hasColumns ? "SQL kodu aynı; farkları Kolonlar görünümünde inceleyin.":"SQL kodu aynı; nesnenin çalışma durumu veya özellikleri farklı.").font(.caption2).foregroundStyle(.secondary)
        }
      } else {
        StudioEmptyState(title:model.detailLoading ? "Tanım okunuyor…":model.focused == nil ? "Bir nesne seçin":"Kod önizlemesi yok",icon:"doc.text.magnifyingglass",detail:model.focused == nil ? "Kod ve kolon farkları burada gösterilir.":model.detailNotice.isEmpty ? "Nesne bilgisi hazırlanıyor.":"Kolonlar görünümünden yapıyı inceleyebilirsiniz.")
      }
    }.padding(.top,8)
  }
  private var columns:some View {
    VStack(alignment:.leading,spacing:6) {
      HStack {
        Text(model.columnSummary).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Toggle("Yalnız farklı kolonlar",isOn:$model.columnOnlyDifferences).toggleStyle(.checkbox).disabled(!model.columnsReady)
      }
      Table(model.visibleColumns) {
        TableColumn("Kolon") {row in Text(row.name).fontWeight(row.isEqual ? .regular:.medium).lineLimit(1).help(row.name)}.width(min:130,ideal:180)
        TableColumn("Hedef · \(model.target?.database ?? "")") {row in columnValue(row.target,changed:!row.isEqual,source:false)}.width(min:180,ideal:270)
        TableColumn("Kaynak · \(model.source?.database ?? "")") {row in columnValue(row.source,changed:!row.isEqual,source:true)}.width(min:180,ideal:270)
        TableColumn("Fark") {row in Text(row.summary).font(.caption).foregroundStyle(Color(nsColor:row.isEqual ? StudioTheme.muted:StudioTheme.warning)).lineLimit(2).help(row.summary)}.width(min:110,ideal:190)
      }.accessibilityIdentifier("schemaColumns")
        .overlay {if model.columnsReady && model.visibleColumns.isEmpty {Text("Kolon özellikleri aynı").foregroundStyle(.secondary)}}
    }
  }
  private var footer:some View {
    HStack(spacing:10) {
      VStack(alignment:.leading,spacing:3) {
        Text(model.message).font(.caption).lineLimit(1).help(model.message)
        Text("Taşıma yalnız şemayı değiştirir.").font(.caption2).foregroundStyle(.secondary).help("Veri, izin, sahiplik ve extended properties taşınmaz. Mevcut tablo silinmez veya yeniden oluşturulmaz.")
      }
      Spacer(minLength:8)
      if model.applying {ProgressView().controlSize(.small)}
      StudioActionButton("Kaynak SQL’i hedef sekmede aç",icon:"doc.text") {openSQL(model.sourceSQL)}.labelStyle(.iconOnly)
        .disabled(model.detailComparison == nil || model.currentDifference?.source == nil || model.sourceSQL.isEmpty || model.applying).accessibilityIdentifier("schemaOpenSQL")
      StudioActionButton("Taşıma Önizlemesi",icon:"paperplane") {preview()}.buttonStyle(StudioPrimaryButton())
        .disabled(model.marked.isEmpty || model.marked.count>100 || model.busy || model.applying).accessibilityIdentifier("schemaMigrationPreview")
    }
  }
  private func endpoint(_ title:String,icon:String,selection:Binding<String>)->some View {
    HStack(spacing:7) {
      Label(title,systemImage:icon).font(.caption).foregroundStyle(.secondary)
      Picker(title,selection:selection) {Text("Veritabanı seçin").tag("");ForEach(model.endpoints,id:\.id) {Text($0.title).tag($0.id)}}.labelsHidden().accessibilityLabel(title+" veritabanı")
    }.frame(maxWidth:.infinity).disabled(model.busy || model.applying)
  }
  private func metric(_ title:String,count:Int,color:NSColor)->some View {
    HStack(spacing:5) {Circle().fill(Color(nsColor:color)).frame(width:5,height:5);Text("\(count) \(title)").font(.caption).monospacedDigit()}
      .padding(.horizontal,8).padding(.vertical,4).background(Color(nsColor:color).opacity(0.08),in:Capsule())
  }
  private func sideTitle(_ title:String,name:String,color:NSColor)->some View {
    HStack(spacing:6) {Circle().fill(Color(nsColor:color)).frame(width:5,height:5);Text(title).fontWeight(.semibold);Text(name).foregroundStyle(.secondary).lineLimit(1).help(name)}
      .font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,8)
  }
  private func columnValue(_ column:SchemaColumn?,changed:Bool,source:Bool)->some View {
    VStack(alignment:.leading,spacing:2) {
      if let column {
        Text(column.dataType).font(.system(size:12,design:.monospaced)).lineLimit(1)
        Text(columnDetails(column)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      } else {Text("—").foregroundStyle(.secondary)}
    }.frame(minHeight:40,alignment:.leading).padding(.horizontal,4)
      .background(changed ? Color(nsColor:source ? StudioTheme.success:StudioTheme.danger).opacity(0.07):.clear,in:RoundedRectangle(cornerRadius:4))
      .help(column.map {$0.dataType+"\n"+columnDetails($0)} ?? "Bu veritabanında kolon yok")
  }
  private func columnDetails(_ column:SchemaColumn)->String {
    ([column.nullable ? "NULL":"NOT NULL","Sıra \(column.ordinal)",column.userDefined ? column.baseDataType:"",column.collation,column.attributes].filter {!$0.isEmpty}).joined(separator:" · ")
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
    let panel=SchemaComparisonPanel(model:model,preview:{[weak self] in self?.prepare()},openSQL:{[weak model] sql in if let target=model?.target {openSQL(target,sql)}})
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
      ["105","dbo","usp_Encrypted","P",nil,"Tanım şifreli veya görünmüyor."],
      ["106","dbo","Customers","U",String(repeating:source ? "9":"8",count:64),""],
      ["107","dbo","CustomerHistory","U",String(repeating:source ? "7":"6",count:64),"Özel tablo özellikleri için otomatik taşıma kapalı."],
      ["108","dbo","v_Balance","V",String(repeating:source ? "5":"4",count:64),""]]
    func body(_ id:Int)->String {switch id {case 101:return "CREATE PROCEDURE [dbo].[usp_Customers]\nAS\nBEGIN\n    SET NOCOUNT ON;\n    SELECT [CustomerID], [Name]"+(source ? ", [City]":"")+"\n    FROM [dbo].[Customers];\nEND;";case 102:return "CREATE VIEW [dbo].[v_Orders] AS SELECT 1 AS [OrderID];";case 108:return "CREATE VIEW [dbo].[v_Balance] AS SELECT [CustomerID], [Amount] FROM [dbo].[Customers];";case 103:return "CREATE FUNCTION [dbo].[ufn_Total]() RETURNS int AS BEGIN RETURN 42; END;";default:return "CREATE PROCEDURE [dbo].[usp_Legacy] AS SELECT 1;"}}
    var result=Execution()
    if sql.contains("StudioSchemaInventory") {
      result.results=[Rows(values:[["1",database]]),Rows(values:objects),Rows(values:[])]
    } else if sql.contains("StudioSchemaRefinement") {
      let list=sql.components(separatedBy:"IN (").last ?? ""
      let requested=list.prefix {$0 != ")"}
      let ids=requested.split(separator:",").compactMap {Int($0)}
      let rows:[[String?]]=ids.map {id in
        let structure:String?=id==108 ? String(repeating:source ? "2":"1",count:64):id==102 ? String(repeating:"0",count:64):nil
        return [String(id),body(id),"1","1","0",nil,structure]
      }
      result.results=[Rows(values:rows)]
    } else if sql.contains("StudioSchemaColumns") {
      let id=[102,106,107,108].first {sql.contains("=\($0)")} ?? 106
      let type=id==102 || id==108 ? "V":"U"
      func column(_ n:Int,_ name:String,_ type:String,_ length:Int,_ precision:Int=0,_ scale:Int=0,_ nullable:Bool=true)->[String?] {
        [String(n),name,"sys",type,type,"0","0",String(length),String(precision),String(scale),nullable ? "1":"0",type=="nvarchar" ? "Latin1_General_100_CI_AS":nil,"0",nil,nil,nil,"0",nil,"0","0","0","0","","0"]
      }
      var columns=[column(1,id==102 ? "OrderID":"CustomerID","int",4,10,0,false)]
      if id != 102 {
        if type=="U" {columns.append(column(2,"Name","nvarchar",source ? 200:100))}
        columns.append(column(columns.count+1,"Amount","decimal",source ? 13:9,source ? 28:18,source ? 8:2,source))
        if source,type=="U" {columns.append(column(4,"City","nvarchar",100))}
      }
      result.results=[Rows(values:[[String(id),type,"1"]]),Rows(values:columns)]
    } else if sql.contains("sys.computed_columns") {
      let id=sql.contains("=107") ? 107:106
      let columns:[[String?]]=[
        ["1","CustomerID","int","0","0",nil,nil,nil,nil,nil,nil,nil,"0","0","0"],
        ["2","Name",source ? "nvarchar(100)":"nvarchar(50)","1","0",nil,nil,nil,nil,nil,nil,"Latin1_General_100_CI_AS","0","0","0"],
        ["3","Amount",source ? "decimal(28,8)":"decimal(18,2)",source ? "1":"0","0",nil,nil,nil,nil,nil,nil,nil,"0","0","0"]]+(source ? [["4","City","nvarchar(50)","1","0",nil,nil,nil,nil,nil,nil,"Latin1_General_100_CI_AS","0","0","0"]]:[])
      result.results=[Rows(values:columns),Rows(),Rows(),Rows(),Rows(),Rows(),Rows(values:[[id==107 ? "1":"0",nil]])]
    } else if sql.contains("sys.sql_modules") {
      let id=[101,102,103,104,108].first {sql.contains("=\($0)")} ?? 101
      result.results=[Rows(values:[[body(id),"1","1","0",nil]])]
    } else {throw SQLFailure("Çevrimdışı DDL fixture bu sorguyu desteklemiyor.")}
    return result
  }
}
