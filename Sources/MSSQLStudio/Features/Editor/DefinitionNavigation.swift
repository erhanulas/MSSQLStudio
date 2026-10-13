import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  func openEditorDefinition(_ symbol: CatalogSymbol, document: QueryDocument) {
    let server=document.server,db=document.database,generation=document.server.generation
    if let existing=state.documents.first(where: {$0.server === server && $0.database == db && $0.definitionSymbol?.schema == symbol.schema && $0.definitionSymbol?.name == symbol.name}) {
      state.active=existing;state.changed?()
      detached[existing.id]?.showWindow(nil)
      if existing.definitionError == nil {return}
      state.active=document
      _=state.close(existing)
    }
    let target=state.newQuery(server:server,database:db,title:(symbol.kind == "USER_TABLE" ? "CREATE · ":"ALTER · ")+symbol.name,startConnection:false)
    target.definitionSymbol=symbol;target.definitionLoading=true;target.changed?()
    target.definitionTask=Task { [weak self,weak target] in
      guard let self,let target else {return}
      @MainActor func current()->Bool {!Task.isCancelled && state.documents.contains(where: {$0 === target}) && target.database == db && target.server === server}
      defer {target.definitionTask=nil}
      do {
        let result=try await server.catalog("SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID(\(SQL.literal(symbol.schema))) AND name=\(SQL.literal(symbol.name));",database:db)
        guard current() else {return}
        guard server.generation == generation else {throw SQLFailure("Bağlantı değişti; nesne tanımını yeniden açın.")}
        guard let rawID=result.results.first?.values.first?.first,let rawID,let id=Int(rawID) else {throw SQLFailure("Nesne bulunamadı; DDL indeksini yenileyin.")}
        let key=ObjectEditorKey(serverID:server.id,database:db,objectID:id)
        if let existing=state.documents.first(where: {$0 !== target && $0.objectEditorKey == key}) {
          target.definitionLoading=false;_=state.close(target)
          _=activateObjectEditor(server:server,database:db,objectID:id)
          existing.definitionSymbol=symbol;return
        }
        target.objectEditorKey=key
        let sql:String,original:String?
        if symbol.kind == "USER_TABLE" {
          let table=try ObjectMetadata.decode(await server.catalog(ObjectMetadata.table(id),database:db),schema:symbol.schema,name:symbol.name)
          sql=try table.createScript();original=nil
        } else {
          let result=try await server.catalog(Catalog.definition(id),database:db)
          guard let text=result.results.first?.values.first?.first,let text else {throw SQLFailure("Tanım alınamadı; VIEW DEFINITION iznini veya şifreli modülü kontrol edin.")}
          sql=ModuleEditing.alter(text);original=text
        }
        guard current() else {return}
        guard server.generation == generation else {throw SQLFailure("Bağlantı değişti; nesne tanımını yeniden açın.")}
        target.sql=sql;target.savedText=sql
        if let original {target.moduleOriginal=original;target.moduleInitialSQL=sql;target.moduleObjectID=id}
        target.definitionLoading=false;target.changed?();target.connect()
      } catch {
        guard current() else {return}
        target.definitionLoading=false;target.definitionError=error.localizedDescription;target.changed?()
      }
    }
  }
}
