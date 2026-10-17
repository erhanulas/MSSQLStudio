import AppKit
import SQLServerKit

struct TableDesignPlan:Identifiable {
  let id=UUID()
  let revision:UUID
  let original:TableDefinition?
  let schema:String
  let name:String
  let sql:String
  let changedTypes:Set<String>
}
@MainActor final class TableDesignerModel:NSObject,ObservableObject,NSWindowDelegate {
  static var activeApplications=0
  @Published var schema="dbo" {didSet {changed()}}
  @Published var name="NewTable" {didSet {changed()}}
  @Published var columns:[SQLServerKit.TableColumn]=[.init(id:-1,name:"Id",type:"int",nullable:false,identity:true)] {didSet {changed()}}
  @Published var primary:Set<Int>=[-1] {didSet {changed()}}
  @Published var structure=TableStructureDraft() {didSet {changed()}}
  @Published private(set) var original:TableDefinition?
  @Published private(set) var selectedDefinition:ManagedDefinition?
  @Published private(set) var structureEditable=true
  @Published private(set) var types:[TableDataType]=TableDataType.builtins
  @Published private(set) var ready=false
  @Published private(set) var busy=false
  @Published private(set) var unverified=false
  @Published var error=""
  @Published var message=""
  @Published var requestedColumnFocus:Int?
  private var structureBaseline=TableStructureDraft()
  private var revision=UUID()
  private var closed=false
  private var loading=false
  private var applying=false
  private var attempted:Set<UUID>=[]
  private let initialKind:String
  private let loadTable:(() async throws -> TableDefinition)?
  private let loadTypes:() async throws -> [TableDataType]
  private let reloadTable:((String,String) async throws -> TableDefinition)?
  private let writer:((TableDesignPlan) async throws -> TableDefinition)?
  let objectID:Int?
  init(initialKind:String="",objectID:Int?=nil,load:(() async throws -> TableDefinition)?=nil,
    loadTypes:@escaping () async throws -> [TableDataType]={[]},reload:((String,String) async throws -> TableDefinition)?=nil,
    apply:((TableDesignPlan) async throws -> TableDefinition)?=nil) {
    self.initialKind=initialKind;self.objectID=objectID;loadTable=load;self.loadTypes=loadTypes;reloadTable=reload;writer=apply
    super.init();newStructure(kind:initialKind.isEmpty ? "INDEX":initialKind)
  }
  private func changed() {revision=UUID();message=""}
  var primaryNames:[String] {
    let oldIDs=original?.primaryKey.compactMap {key in original?.columns.first(where:{$0.name==key})?.id} ?? []
    let ids=oldIDs.filter {primary.contains($0)}+columns.filter {primary.contains($0.id) && !oldIDs.contains($0.id)}.map(\.id)
    return ids.compactMap {id in columns.first(where:{$0.id==id})?.name}
  }
  var columnsChanged:Bool {original.map {$0.columns != columns || $0.primaryKey != primaryNames} ?? true}
  var structureChanged:Bool {structure != structureBaseline}
  var hasChanges:Bool {columnsChanged || structureChanged}
  private var hasUnnamedColumn:Bool {columns.contains {$0.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}}
  var canAddColumn:Bool {ready && !closed && !busy && !unverified && !hasUnnamedColumn}
  @discardableResult func addColumn()->Int? {
    guard canAddColumn else {return nil}
    let id=min(0,columns.map(\.id).min() ?? 0)-1
    columns.append(.init(id:id,name:""));requestedColumnFocus=id
    return id
  }
  var canPrepare:Bool {!closed && ready && !busy && !unverified && !hasUnnamedColumn && hasChanges}
  var canApply:Bool {canPrepare && writer != nil}
  var isNew:Bool {original==nil && loadTable==nil}
  func isCurrent(_ plan:TableDesignPlan)->Bool {!closed && plan.revision==revision && !attempted.contains(plan.id)}
  func load() async {
    guard !ready,!loading,!closed else {return}
    loading=true;defer {loading=false}
    ready=false
    do {
      let custom=try await loadTypes()
      try Task.checkCancellation()
      let table=try await loadTable?()
      try Task.checkCancellation();guard !closed else {return}
      types=TableDataType.builtins+custom
      if let table {accept(table)}
      ready=true;error=""
    } catch is CancellationError {} catch {self.error=error.localizedDescription}
  }
  private func accept(_ table:TableDefinition,preferredSelection:String?=nil) {
    requestedColumnFocus=nil
    original=table;schema=table.schema;name=table.name;columns=table.columns
    primary=Set(table.columns.filter {table.primaryKey.contains($0.name)}.map(\.id))
    let selected=preferredSelection ?? selectedDefinition?.name
    if let object=table.definitions.first(where:{$0.name==selected}) {select(object)} else {newStructure(kind:structure.kind)}
    unverified=false
  }
  func select(_ object:ManagedDefinition) {
    selectedDefinition=object;if !unverified {error=""}
    do {structure=try TableStructureDraft(object);structureBaseline=structure;structureEditable=true}
    catch {structureEditable=false;structure=TableStructureDraft(kind:object.kind);structure.name=object.name;structureBaseline=structure;self.error=error.localizedDescription}
  }
  func newStructure(kind:String?=nil) {
    selectedDefinition=nil;structureEditable=true;structure=TableStructureDraft(kind:kind ?? structure.kind);structureBaseline=structure;if !unverified {error=""}
  }
  func prepare() throws -> TableDesignPlan {
    guard canPrepare else {throw SQLFailure("Uygulanacak değişiklik yok veya güncel metadata gerekli.")}
    if structureChanged,let original {
      if original.definitions.contains(where:{$0.name.caseInsensitiveCompare(structure.name) == .orderedSame && $0.id != selectedDefinition?.id}) {throw SQLFailure("Bu adla bir nesne zaten var; mevcut nesneyi seçerek düzenleyin.")}
      if structure.kind=="PK",selectedDefinition?.kind != "PK",!original.primaryKey.isEmpty {throw SQLFailure("Tabloda primary key var; mevcut anahtarı seçerek düzenleyin.")}
    }
    var statements:[String]=[]
    let qualified=SQL.identifier(schema)+"."+SQL.identifier(name)
    if let original,let objectID=original.objectID ?? objectID {statements.append("IF ISNULL(OBJECT_ID(\(SQL.literal(original.qualified)), N'U'), -1) <> \(objectID) THROW 51002, N'Tablo değişmiş; tasarımı yenileyin.', 1;")}
    if structureChanged,let selectedDefinition {statements.append(structure.dropSQL(table:qualified,original:selectedDefinition))}
    if columnsChanged {
      if structureChanged,selectedDefinition?.kind == "PK",original?.primaryKey != primaryNames {throw SQLFailure("Primary key’i Columns veya Keys bölümünden düzenleyin; ikisini ayrı uygulayın.")}
      statements.append(try ObjectScripts.tableChangeBody(original:original,schema:schema,name:name,columns:columns,primaryKey:primaryNames,allowedTypes:Set(types.map(\.defaultSQL))))
    }
    if structureChanged {
      guard structureEditable else {throw SQLFailure("Bu nesneyi SQL editöründe düzenleyin.")}
      statements.append(try structure.createSQL(table:qualified,columns:columns.map(\.name)))
    }
    return TableDesignPlan(revision:revision,original:original,schema:schema,name:name,sql:ObjectScripts.transaction(statements.joined(separator:"\n\n")),changedTypes:Set(columns.filter {column in original?.columns.first(where:{$0.id==column.id})?.type != column.type}.map(\.type)))
  }
  func apply(_ plan:TableDesignPlan) async -> Bool {
    guard canApply,isCurrent(plan),let writer else {return false}
    attempted.insert(plan.id);busy=true;applying=true;error="";Self.activeApplications+=1
    defer {busy=false;applying=false;Self.activeApplications-=1}
    do {
      let selected=structureChanged ? structure.name:selectedDefinition?.name
      let updated=try await writer(plan)
      guard !closed,plan.revision==revision else {throw SQLFailure("Tasarım bağlamı değişti; sunucudan yenileyin.")}
      accept(updated,preferredSelection:selected);ready=true;message="Değişiklikler uygulandı; güncel tablo bilgileri alındı."
      return true
    } catch {unverified=true;self.error=error.localizedDescription;return false}
  }
  func reload() async {
    if !ready {await load();return}
    guard !busy,let reloadTable else {return}
    busy=true;defer {busy=false}
    do {
      let custom=try await loadTypes(),table=try await reloadTable(schema,name)
      try Task.checkCancellation();guard !closed else {return}
      types=TableDataType.builtins+custom;accept(table);ready=true;error="";message="Tablo bilgileri sunucudan yenilendi."
    } catch is CancellationError {} catch {self.error=error.localizedDescription}
  }
  func close() {guard !applying else {return};closed=true;revision=UUID()}
  func windowWillClose(_ notification:Notification) {closed=true;revision=UUID()}
  func windowShouldClose(_ sender:NSWindow)->Bool {if applying {NSSound.beep();return false};return true}
}
