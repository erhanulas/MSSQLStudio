import Foundation
import SQLServerKit

@MainActor final class TableDesignerApplication {
  private let node:TreeNode
  private let server:ConnectedServer
  private let database:String
  private let generation:UUID
  init(node:TreeNode) {self.node=node;server=node.server;database=node.database;generation=node.server.generation}
  func loadTypes() async throws -> [TableDataType] {
    guard current() else {throw SQLFailure("Bağlantı değişti; tasarımı yeniden açın.")}
    let result=try TableDataType.decode(await server.catalog(TableDataType.query,database:database))
    guard current() else {throw CancellationError()}
    return result
  }
  private func current()->Bool {server.online && server.generation==generation && !Task.isCancelled}
  func apply(_ plan:TableDesignPlan,writer:((String) async throws -> Execution)?=nil) async throws -> TableDefinition {
    guard current(),writer != nil || server.catalogFixture==nil && server.asyncCatalogFixture==nil else {throw SQLFailure("Bağlantı değişmiş veya izole önizleme; SQL gönderilmedi.")}
    if let original=plan.original {
      let live=try await load(schema:plan.schema,name:plan.name,recordIndex:false)
      var a=original,b=live
      a.definitions.sort {$0.name<$1.name};b.definitions.sort {$0.name<$1.name}
      guard a==b else {throw SQLFailure("Tablo başka bir oturumda değişti; tasarımı sunucudan yenileyin.")}
    }
    let types=try await loadTypes()
    // Plans are immutable UI snapshots; types are read again on the same database.
    for type in plan.changedTypes {_ = try ObjectScripts.validatedType(type,allowedTypes:Set(types.map(\.defaultSQL)))}
    guard current() else {throw SQLFailure("Bağlantı veya veri tipi bağlamı değişti; SQL gönderilmedi.")}
    var limits=Limits();limits.timeout=120
    do {
      let result:Execution
      if let writer {result=try await writer(plan.sql)} else {result=try await server.catalog(plan.sql,database:database,limits:limits)}
      guard result.failure==nil,!result.partial,!result.stoppedEarly,current() else {throw SQLFailure("Gönderim sonucu doğrulanamadı.")}
    } catch {throw SQLFailure("Değişiklik sonucu doğrulanamadı; otomatik yeniden gönderilmedi. Sunucudan yenileyin. "+error.localizedDescription)}
    NotificationCenter.default.post(name:.init("studioManagedObjectCompleted"),object:node,userInfo:["refreshTable":true,"schema":plan.schema,"name":plan.name,"generation":generation])
    if server.allowsDefinitionIndex(database) {server.definitionIndex.refreshAfterDDL(database:database)}
    do {return try await load(schema:plan.schema,name:plan.name)}
    catch {throw SQLFailure("Değişiklik gönderildi; güncel tasarım okunamadı. Sunucudan yenileyin. "+error.localizedDescription)}
  }
  func load(schema:String,name:String,recordIndex:Bool=true) async throws -> TableDefinition {
    guard current() else {throw SQLFailure("Bağlantı değişti; tasarımı yeniden açın.")}
    let lookup=try await node.server.catalog("SELECT OBJECT_ID(\(SQL.literal(SQL.identifier(schema)+"."+SQL.identifier(name))), N'U');",database:node.database)
    guard !lookup.partial,!lookup.stoppedEarly,lookup.failure==nil,let row=lookup.results.first?.values.first,let value=row.first ?? nil,let id=Int(value),id>0 else {throw SQLFailure("Güncel tablo kimliği alınamadı.")}
    var table=try ObjectMetadata.decode(await node.server.catalog(ObjectMetadata.table(id),database:node.database),schema:schema,name:name)
    table.objectID=id
    guard current() else {throw CancellationError()}
    if recordIndex,node.server.allowsDefinitionIndex(node.database) {
      let snapshot=table
      let value=try await Task.detached(priority:.utility) {try snapshot.createScript()}.value
      await node.server.definitionIndex.record(.init(id:id,schema:schema,name:name,type:"U",sql:value,fetchedAt:Date()),database:node.database,generation:generation)
    }
    return table
  }
}
