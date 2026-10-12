import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor struct SchemaComparisonPanelTests {
  private func model(reader:SchemaComparisonModel.Reader?=nil,writer:SchemaComparisonModel.Reader?=nil)->SchemaComparisonModel {
    let server=SchemaComparisonUIFixture.server()
    let result=SchemaComparisonModel(endpoints:[.init(server:server,database:"SourceDB"),.init(server:server,database:"TargetDB")],reader:reader,writer:writer)
    result.targetID=result.endpoints[1].id // Tests consciously select the target after the blank initial state.
    return result
  }
  @Test func targetStartsBlankAndOnlyTheFocusedEligibleObjectCanBePrepared() async throws {
    let server=SchemaComparisonUIFixture.server()
    let endpoints=[SchemaEndpoint(server:server,database:"SourceDB"),SchemaEndpoint(server:server,database:"TargetDB")]
    var reads=0
    let model=SchemaComparisonModel(endpoints:endpoints,sourceID:endpoints[0].id,reader:{endpoint,sql in reads+=1;return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    #expect(model.sourceID==endpoints[0].id && model.targetID.isEmpty && model.target==nil)
    #expect(!model.validPair && !model.canPreparePlan)
    await model.compare();#expect(reads==0 && model.differences.isEmpty)
    model.targetID=endpoints[1].id;await model.compare()
    let none=await model.preparePlan();#expect(!model.canPreparePlan && none==nil)
    model.focused=model.visible.first {$0.key.name=="usp_Legacy"}?.key
    let ineligible=await model.preparePlan();#expect(!model.canPreparePlan && ineligible==nil)
    let procedure=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.focused=procedure;#expect(model.canPreparePlan)
    let plan=try #require(await model.preparePlan());#expect(plan.keys==[procedure])
    model.focused=model.visible.first {$0.key.name=="ufn_Total"}?.key
    let function=try #require(await model.preparePlan())
    #expect(function.keys.count==1 && function.keys[0].name=="ufn_Total" && !function.keys.contains(procedure))
    model.targetID="" // A programmatic context change is guarded even before the view invalidates.
    #expect(!model.canPreparePlan)
  }
  @Test func focusChangesWhilePreparingCannotPresentThePreviousObjectsPlan() async throws {
    let model=model(reader:{endpoint,sql in
      if !sql.contains("StudioSchemaInventory") && !sql.contains("StudioSchemaRefinement") {try await Task.sleep(for:.milliseconds(40))}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    })
    await model.compare()
    model.focused=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    let task=Task {await model.preparePlan()}
    try await Task.sleep(for:.milliseconds(10));#expect(model.busy)
    model.focused=try #require(model.visible.first {$0.key.name=="ufn_Total"}).key
    #expect(await task.value==nil && !model.busy && model.error.contains("Seçim değişti"))
  }
  @Test func externallyPreparedMultipleObjectMigrationIsRejectedBeforeAnyWrite() async throws {
    var writes=0
    let model=model(writer:{_,_ in writes+=1;return Execution()})
    await model.compare()
    let source=try #require(model.sourceSnapshot),target=try #require(model.targetSnapshot)
    let keys=Set(model.visible.filter {["usp_Customers","ufn_Total"].contains($0.key.name)}.map(\.key))
    var left:[SchemaObjectKey:SchemaObjectContent]=[:],right:[SchemaObjectKey:SchemaObjectContent]=[:]
    for key in keys {
      let object=try #require(source.objects[key])
      left[key]=try SchemaComparison.decodeContent(SchemaComparisonUIFixture.catalog("SourceDB",SchemaComparison.contentQuery(object)),object:object)
      if let old=target.objects[key] {right[key]=try SchemaComparison.decodeContent(SchemaComparisonUIFixture.catalog("TargetDB",SchemaComparison.contentQuery(old)),object:old)}
    }
    let plan=try SchemaMigration.plan(selected:keys,source:source,target:target,sourceContent:left,targetContent:right)
    #expect(plan.keys.count==2)
    await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    #expect(writes==0 && model.error.contains("yalnız bir nesne") && !model.applying)
    #expect(SchemaComparisonModel.activeApplications==0)
  }
  @Test func successfulApplyReconcilesOnlySelectedObjectAndPreservesOtherRowsFiltersAndCaches() async throws {
    var committed=false,writes=0,calls:[(String,String)]=[]
    let model=model(reader:{endpoint,sql in
      calls.append((endpoint.database,sql))
      var result=try SchemaComparisonUIFixture.catalog(committed && endpoint.database=="TargetDB" ? "SourceDB":endpoint.database,sql)
      if sql.contains("StudioSchemaInventory") {
        result.results[2]=Rows(values:result.results[1].values.compactMap {row -> [String?]? in
          guard ["usp_Customers","v_ActiveBalance"].contains(row[2] ?? "") else {return nil}
          return ["dbo",row[2],"dbo","Customers","0"]
        })
      }
      return result
    },writer:{endpoint,_ in #expect(endpoint.database=="TargetDB");writes+=1;committed=true;return Execution()})
    await model.compare()
    let other=try #require(model.visible.first {$0.key.name=="v_ActiveBalance"}).key
    model.focused=other;await model.loadDetail() // Both content and column caches must survive an unrelated write.
    let selected=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.focused=selected;await model.loadDetail()
    model.search="dbo";model.detailMode = .code
    let beforeSource=try #require(model.sourceSnapshot),beforeTarget=try #require(model.targetSnapshot)
    let statuses=Dictionary(uniqueKeysWithValues:model.differences.filter {$0.key != selected}.map {($0.key,$0.status)})
    let plan=try #require(await model.preparePlan()),start=calls.count
    await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    let after=Array(calls.dropFirst(start)),inventories=after.filter {$0.1.contains("StudioSchemaInventory")}
    #expect(writes==1 && model.error.isEmpty && !model.applying && !model.busy)
    #expect(inventories.count==4 && after.count==4) // Preflight and reconciliation, no full compare/refinement needed.
    #expect(inventories.allSatisfy {$0.1.contains("(s.name=N'dbo' AND o.name=N'usp_Customers')")})
    #expect(model.differences.count==10 && model.differentCount==5 && model.sameCount==4)
    #expect(model.differences.first {$0.key==selected}?.status == .equal && !model.visible.contains {$0.key==selected})
    #expect(model.focused==nil && model.search=="dbo" && model.kind=="Tüm türler" && model.detailMode == .code)
    #expect(model.message.contains("usp_Customers") && model.message.contains("hedefe uygulandı"))
    for key in statuses.keys {
      #expect(model.sourceSnapshot?.objects[key]==beforeSource.objects[key])
      #expect(model.targetSnapshot?.objects[key]==beforeTarget.objects[key])
      #expect(model.sourceSnapshot?.dependencies[key]==beforeSource.dependencies[key])
      #expect(model.targetSnapshot?.dependencies[key]==beforeTarget.dependencies[key])
      #expect(model.differences.first {$0.key==key}?.status==statuses[key])
    }
    let cachedReads=calls.count
    model.focused=other;await model.loadDetail()
    #expect(calls.count==cachedReads && model.columnsReady && model.detailReady)
    #expect(SchemaComparisonModel.activeApplications==0)
  }
  @Test func creatingSourceOnlyObjectMergesItsFreshTargetIdentityWithoutReplacingUnrelatedTargetObjects() async throws {
    var committed=false,writes=0
    let selected=SchemaObjectKey(schema:"dbo",name:"ufn_Total")
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(committed && endpoint.database=="TargetDB" ? "SourceDB":endpoint.database,sql)
      if committed,endpoint.database=="TargetDB",sql.contains("StudioSchemaInventory") {
        var rows=Array(result.results[1].values)
        for i in rows.indices where rows[i][2]==selected.name {rows[i][0]="903"}
        result.results[1]=Rows(values:rows)
      }
      return result
    },writer:{_,_ in writes+=1;committed=true;return Execution()})
    await model.compare();model.focused=selected
    let original=try #require(model.targetSnapshot),plan=try #require(await model.preparePlan())
    #expect(plan.target.objects[selected]==nil && plan.keys==[selected])
    await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    #expect(writes==1 && model.error.isEmpty && model.targetSnapshot?.objects[selected]?.objectID==903)
    #expect(model.differences.first {$0.key==selected}?.status == .equal && model.focused==nil)
    #expect(model.targetSnapshot?.objects.count==original.objects.count+1)
    for (key,object) in original.objects {#expect(model.targetSnapshot?.objects[key]==object)}
    #expect(model.targetSnapshot?.objects.keys.contains { $0.name=="usp_Legacy" }==true)
  }
  @Test(arguments:[false,true]) func preflightChecksFreshDirectDependenciesWithoutReloadingTheWholeCatalog(renamed:Bool) async throws {
    var changed=false,writes=0,calls:[(String,String)]=[]
    let selected=SchemaObjectKey(schema:"dbo",name:"usp_Customers")
    let dependency=SchemaObjectKey(schema:"dbo",name:renamed ? "CustomerHistory":"Customers")
    let model=model(reader:{endpoint,sql in
      calls.append((endpoint.database,sql))
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if sql.contains("StudioSchemaInventory") {
        if endpoint.database=="SourceDB",result.results[1].values.contains(where:{$0[2]==selected.name}) {
          result.results[2]=Rows(values:[["dbo",selected.name,"dbo",changed ? dependency.name:"Customers","0"]])
        } else if endpoint.database=="TargetDB",changed {
          result.results[1]=Rows(values:result.results[1].values.filter {$0[2] != dependency.name})
        }
      }
      return result
    },writer:{_,_ in writes+=1;return Execution()})
    await model.compare();model.focused=selected
    let plan=try #require(await model.preparePlan()),start=calls.count
    changed=true;await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    let scoped=Array(calls.dropFirst(start))
    #expect(writes==0 && model.error.contains(dependency.qualified) && model.error.contains("hedefte yok"))
    #expect(scoped.count==2 && scoped.allSatisfy {$0.1.contains("StudioSchemaInventory")})
    #expect(scoped[0].0=="SourceDB" && scoped[0].1.contains("o.name=N'usp_Customers'"))
    #expect(scoped[1].0=="TargetDB" && scoped[1].1.contains("o.name="+SQL.literal(dependency.name)))
    #expect(model.visible.contains {$0.key==selected} && model.differences.count==10)
    #expect(!model.applying && SchemaComparisonModel.activeApplications==0)
  }
  @Test func committedWriteWithFailedReconciliationKeepsOtherRowsAndNeverAdvertisesTheOldRowAsCurrent() async throws {
    var committed=false,writes=0,calls:[String]=[]
    let model=model(reader:{endpoint,sql in
      calls.append(sql)
      if committed,endpoint.database=="TargetDB",sql.contains("StudioSchemaInventory") {throw SQLFailure("Yeniden okuma başarısız.")}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    },writer:{_,_ in writes+=1;committed=true;return Execution()})
    await model.compare()
    let selected=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.focused=selected;await model.loadDetail();model.search="dbo";model.detailMode = .code
    let others=model.differences.filter {$0.key != selected}.map(\.key)
    let plan=try #require(await model.preparePlan()),start=calls.count
    await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    #expect(writes==1 && model.message.contains("hedefe uygulandı") && !model.message.contains("tamamlanamadı"))
    #expect(model.error.contains("hedefe uygulandı") && model.error.contains("tekrar gönderilmedi"))
    #expect(model.differences.map(\.key)==others && model.sourceSnapshot?.objects[selected]==nil && model.targetSnapshot?.objects[selected]==nil)
    #expect(model.focused==nil && !model.detailReady && model.sourceSQL.isEmpty && !model.canPreparePlan)
    #expect(model.search=="dbo" && model.detailMode == .code && !model.applying && SchemaComparisonModel.activeApplications==0)
    #expect(calls.dropFirst(start).count==4 && calls.dropFirst(start).allSatisfy {$0.contains("o.name=N'usp_Customers'")})
    #expect(await model.preparePlan()==nil && writes==1)
  }
  @Test(arguments:["partial","generation","offline"]) func uncertainOrDisconnectedApplyCannotReuseAStaleSelectedComparison(outcome:String) async throws {
    var writes=0
    let model=model(writer:{endpoint,_ in
      writes+=1
      var result=Execution()
      if outcome=="partial" {result.partial=true}
      if outcome=="generation" {endpoint.server.generation=UUID()}
      if outcome=="offline" {endpoint.server.online=false}
      return result
    })
    await model.compare()
    let selected=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.focused=selected;let plan=try #require(await model.preparePlan())
    await model.apply(plan,sourceID:model.sourceID,targetID:model.targetID)
    #expect(writes==1 && !model.error.isEmpty && !model.applying && SchemaComparisonModel.activeApplications==0)
    #expect(!model.differences.contains {$0.key==selected} && model.focused==nil && !model.canPreparePlan)
    #expect(model.differences.count==9 && model.sourceSnapshot?.objects[selected]==nil && model.targetSnapshot?.objects[selected]==nil)
    if outcome=="partial" {#expect(model.message=="Taşıma sonucu doğrulanamadı.")}
    else {#expect(model.message.contains("hedefe uygulandı") && model.error.contains("tekrar gönderilmedi"))}
  }
  @Test func compareFilterLazyDetailAndPlanUseIndependentMetadataOnly() async throws {
    var calls:[String]=[]
    let model=model(reader:{endpoint,sql in calls.append(sql);return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    await model.compare()
    #expect(model.differences.count==10 && model.visible.count==6)
    #expect(model.differentCount==6 && model.sameCount==3 && model.unavailableCount==1)
    #expect(model.message.contains("1 karşılaştırılamadı"))
    #expect(calls.filter {$0.contains("StudioSchemaInventory")}.count==2)
    #expect(calls.filter {$0.contains("StudioSchemaRefinement")}.count==2)
    #expect(!model.detailReady && !model.busy && model.error.isEmpty)
    model.search="Total";#expect(model.visible.count==1 && model.visible.first?.status == .sourceOnly)
    model.search="";model.kind="View";#expect(model.visible.count==1)
    #expect(model.visible.first?.key.name=="v_ActiveBalance")
    model.kind="Tablo";#expect(Set(model.visible.map(\.key.name))==["Customers","CustomerHistory"])
    model.kind="Tüm türler"
    let row=try #require(model.differences.first {$0.key.name=="usp_Customers"})
    model.focused=row.key;await model.loadDetail()
    #expect(model.detailReady && model.sourceSQL.contains("[City]") && !model.targetSQL.contains("[City]"))
    #expect(model.detailComparison?.added==2 && model.detailComparison?.removed==1)
    #expect(model.changedGroups.count==2 && model.sourceSQL.contains("\r\n"))
    let count=calls.count;await model.loadDetail();#expect(calls.count==count)
    model.focused=row.key
    let plan=try #require(await model.preparePlan())
    #expect(plan.sql.contains("ALTER PROCEDURE") && plan.sql.contains("[City]"))
    #expect(model.target?.database=="TargetDB" && !model.applying)
  }
  @Test func applyRevalidatesAndWritesOnlyToNamedTargetAndBlocksConcurrentDrift() async throws {
    var drift=false,writes:[String]=[]
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if drift,endpoint.database=="TargetDB",sql.contains("StudioSchemaInventory") {
        var rows=Array(result.results[1].values);rows[0][4]=String(repeating:"f",count:64);result.results[1]=Rows(values:rows)
      }
      return result
    },writer:{endpoint,sql in writes.append(endpoint.database+"|"+sql);return Execution()})
    await model.compare();let row=try #require(model.differences.first {$0.key.name=="usp_Customers"});model.focused=row.key
    let plan=try #require(await model.preparePlan()),source=model.sourceID,target=model.targetID
    drift=true;await model.apply(plan,sourceID:source,targetID:target)
    #expect(writes.isEmpty && model.error.contains("değişti") && !model.applying)
    drift=false;await model.compare();model.focused=row.key
    let fresh=try #require(await model.preparePlan());await model.apply(fresh,sourceID:source,targetID:target)
    #expect(writes.count==1 && writes[0].hasPrefix("TargetDB|"))
    #expect(writes[0].contains("ROLLBACK TRANSACTION") && !model.applying)
    #expect(SchemaComparisonModel.activeApplications==0)
    model.focused=row.key;let stale=try #require(await model.preparePlan())
    model.target?.server.generation=UUID()
    await model.apply(stale,sourceID:source,targetID:target)
    #expect(writes.count==1 && model.error.contains("Bağlantı değişti"))
  }
  @Test func cancellationInvalidatesDelayedResultsAndPairChangesInvalidatePreview() async throws {
    let model=model(reader:{endpoint,sql in try await Task.sleep(for:.milliseconds(40));return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    model.startComparison();try await Task.sleep(for:.milliseconds(10));model.cancel()
    try await Task.sleep(for:.milliseconds(100))
    #expect(model.differences.isEmpty && !model.busy)
    await model.compare();let row=try #require(model.differences.first {$0.canStage});model.focused=row.key
    let plan=try #require(await model.preparePlan()),oldSource=model.sourceID,oldTarget=model.targetID
    model.targetID=model.sourceID;model.invalidate()
    #expect(!model.validPair && model.focused==nil && !model.detailReady)
    await model.apply(plan,sourceID:oldSource,targetID:oldTarget)
    #expect(model.error.contains("bağlamı değişti"))
  }
  @Test func tableAndViewColumnsAreLazyAndIndependentOfSafeMigrationScripting() async throws {
    var queries:[String]=[]
    let model=model(reader:{endpoint,sql in queries.append(sql);return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    await model.compare()
    #expect(!queries.contains {$0.contains("StudioSchemaColumns")})
    let table=try #require(model.differences.first {$0.key.name=="Customers"})
    model.focused=table.key;await model.loadDetail()
    #expect(model.columnsReady && model.detailMode == .columns && model.columnChangeCount==3)
    let amount=try #require(model.columnDifferences.first {$0.name=="Amount"})
    #expect(amount.source?.dataType=="decimal(28,8)" && amount.target?.dataType=="decimal(18,2)")
    #expect(amount.changes.contains(.dataType) && amount.changes.contains(.nullability))
    #expect(model.columnDifferences.first {$0.name=="City"}?.changes.contains(.added)==true)
    #expect(model.detailComparison != nil && model.sourceSQL.contains("decimal(28,8)"))
    let reads=queries.count;await model.loadDetail();#expect(queries.count==reads)
    let special=try #require(model.differences.first {$0.key.name=="CustomerHistory"})
    #expect(special.status == .changed && !special.canStage)
    model.focused=special.key;await model.loadDetail()
    #expect(model.columnsReady && model.detailReady && model.columnChangeCount==3)
    #expect(model.detailComparison==nil && model.detailNotice.localizedCaseInsensitiveContains("özel tablo"))
    let view=try #require(model.differences.first {$0.key.name=="v_Balance"})
    #expect(view.status == .equal && !view.canStage && !view.migrationIssue.isEmpty)
    model.focused=view.key;await model.loadDetail()
    #expect(model.columnsReady && model.columnChangeCount==1)
    #expect(model.detailComparison?.added==0 && model.detailComparison?.removed==0)
    #expect(model.detailMode == .columns && model.detailNotice.contains("View kodu aynı"))
  }
  @Test func onlyVerifiedDifferencesAreListedEvenAfterChangingFiltersOrRecomparing() async throws {
    let model=model();await model.compare()
    let excluded:Set<String>=["v_Balance","v_Orders","CustomersIndexOnly","usp_Encrypted"]
    #expect(model.visible.allSatisfy {!excluded.contains($0.key.name)})
    model.search="IndexOnly";#expect(model.visible.isEmpty)
    model.search="";model.kind="View";#expect(model.visible.map(\.key.name)==["v_ActiveBalance"])
    await model.compare();#expect(model.visible.map(\.key.name)==["v_ActiveBalance"])
    let identical=self.model(reader:{_,sql in try SchemaComparisonUIFixture.catalog("SourceDB",sql)})
    await identical.compare()
    #expect(identical.visible.isEmpty && identical.differentCount==0 && identical.unavailableCount==1)
    #expect(identical.sameCount==identical.differences.count-1)
    #expect(identical.sourceSnapshot != nil && identical.error.isEmpty)
  }
  @Test func viewProjectionAdditionAppearsInFilteredListAndInlineCode() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      let source=endpoint.database=="SourceDB"
      let rows=["CREATE VIEW dbo.v_ActiveBalance AS","SELECT A.CustomerID, C.InvoiceDate,  -- Fatura tarihi"]+(source ? ["    C.INCKEYNO AS ExternalOrderId,"]:[])+["    A.Amount","FROM dbo.Customers A JOIN dbo.Orders C ON C.CustomerID=A.CustomerID;"]
      let definition=rows.map {$0+(source ? "    ":"  ")}.joined(separator:source ? "\n":"\r\n")
      if sql.contains("StudioSchemaRefinement") {
        var rows=Array(result.results[0].values)
        for i in rows.indices where rows[i][0]=="109" {rows[i][1]=definition;rows[i][6]=String(repeating:"0",count:64)}
        result.results[0]=Rows(values:rows)
      } else if sql.contains("sys.sql_modules"),sql.contains("=109") {
        result.results[0]=Rows(values:[[definition,"1","1","0",nil]])
      }
      return result
    })
    model.kind="View";await model.compare()
    let row=try #require(model.visible.first {$0.key.name=="v_ActiveBalance"})
    #expect(row.status == .changed && row.canStage)
    #expect(!model.visible.contains {$0.key.name=="v_Balance"})
    model.detailMode = .code;model.focused=row.key;await model.loadDetail()
    #expect(model.sourceSQL.contains("C.INCKEYNO AS ExternalOrderId"))
    #expect(!model.targetSQL.contains("ExternalOrderId") && model.changedGroups.count==1)
    let comparison=try #require(model.detailComparison)
    #expect(comparison.added==1 && comparison.removed==0)
    #expect(comparison.lines.filter(\.changed).count==1)
    #expect(comparison.lines.first(where:\.changed)?.new?.contains("ExternalOrderId")==true)
    #expect(model.targetSQL.contains("\r\n") && !model.sourceSQL.contains("\r\n"))
    #expect(model.detailMode == .code && model.error.isEmpty)
  }
  @Test func readableViewWithMissingServerHashReportsFailureInsteadOfAnEmptyDifferenceList() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if sql.contains("StudioSchemaInventory") {
        var rows=Array(result.results[1].values)
        for i in rows.indices where rows[i][0]=="109" {rows[i][4]=nil}
        result.results[1]=Rows(values:rows)
      }
      return result
    })
    model.kind="View";await model.compare()
    #expect(model.error.contains("DDL özeti hesaplanamadı") && model.error.contains("v_ActiveBalance"))
    #expect(model.visible.isEmpty && model.differences.isEmpty && model.sourceSnapshot==nil)
    #expect(model.message=="Karşılaştırma tamamlanamadı." && !model.busy)
  }
  @Test func proceduresFunctionsAndTriggersUseWhitespaceAwareInlineComparison() async throws {
    let headers:[String:String]=[
      "P":"CREATE PROCEDURE dbo.usp_Customers",
      "FN":"CREATE FUNCTION dbo.usp_Customers() RETURNS int",
      "IF":"CREATE FUNCTION dbo.usp_Customers() RETURNS TABLE",
      "TF":"CREATE FUNCTION dbo.usp_Customers() RETURNS @rows TABLE (Value int)",
      "TR":"CREATE TRIGGER dbo.usp_Customers ON dbo.Customers AFTER INSERT",
      "TRD":"CREATE TRIGGER usp_Customers ON DATABASE FOR CREATE_TABLE"]
    for type in ["P","FN","IF","TF","TR","TRD"] {
      let model=model(reader:{endpoint,sql in
        // Reuse the procedure fixture's body for this synthetic DB trigger while
        // retaining the real requested trigger identity in the returned rows.
        let fixtureSQL=type=="TRD" ? sql.replacingOccurrences(of:"(s.name=N'' AND o.name=N'usp_Customers')",with:"(s.name=N'dbo' AND o.name=N'usp_Customers')"):sql
        var result=try SchemaComparisonUIFixture.catalog(endpoint.database,fixtureSQL)
        let source=endpoint.database=="SourceDB",value=source ? "2":"1"
        let rows=[headers[type]!,"AS",type=="IF" ? "RETURN":"BEGIN",type=="FN" ? "    RETURN \(value);":"    SELECT \(value) AS [Value];"]+(type=="IF" ? []:["END;"])
        let definition=rows.map {$0+(source ? "   ":"")}.joined(separator:source ? "\r\n":"\n")
        let parent:String?=type=="TRD" ? "DATABASE":type=="TR" ? "[dbo].[Customers]":nil
        if sql.contains("StudioSchemaInventory") {
          var values=Array(result.results[1].values)
          for i in values.indices where values[i][0]=="101" {values[i][1]=type=="TRD" ? "":"dbo";values[i][3]=type}
          result.results[1]=Rows(values:values)
        } else if sql.contains("StudioSchemaRefinement") {
          var values=Array(result.results[0].values)
          for i in values.indices where values[i][0]=="101" {values[i][1]=definition;values[i][5]=parent}
          result.results[0]=Rows(values:values)
        } else if sql.contains("sys.sql_modules"),sql.contains("=101") {result.results[0]=Rows(values:[[definition,"1","1","0",parent]])}
        return result
      })
      await model.compare()
      let row=try #require(model.visible.first {$0.key.name=="usp_Customers"})
      #expect(row.source?.type==type && row.source?.usesSQLCodeComparison==true)
      model.focused=row.key;await model.loadDetail()
      let comparison=try #require(model.detailComparison)
      #expect(comparison.added==1 && comparison.removed==1 && !comparison.simplified)
      #expect(comparison.lines.filter(\.changed).count==1 && model.changedGroups.count==1)
      #expect(model.sourceSQL.contains("\r\n") && !model.targetSQL.contains("\r\n"))
      #expect(model.error.isEmpty && model.detailNotice.isEmpty)
    }
  }
  @Test func detailModePersistsAcrossObjectsRecomparisonAndDelayedLoads() async throws {
    var delay=false
    let model=model(reader:{endpoint,sql in
      if delay,sql.contains("StudioSchemaColumns") {try await Task.sleep(for:.milliseconds(40))}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    })
    await model.compare()
    let table=try #require(model.visible.first {$0.key.name=="Customers"}).key
    let special=try #require(model.visible.first {$0.key.name=="CustomerHistory"}).key
    let view=try #require(model.visible.first {$0.key.name=="v_ActiveBalance"}).key
    let procedure=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.detailMode = .code
    for key in [table,view,procedure,table] {
      model.focused=key;await model.loadDetail()
      #expect(model.detailMode == .code && model.effectiveDetailMode == .code)
    }
    model.detailMode = .columns
    model.focused=procedure;await model.loadDetail()
    #expect(model.detailMode == .columns && model.effectiveDetailMode == .code && model.detailComparison != nil)
    model.focused=view;await model.loadDetail()
    #expect(model.detailMode == .columns && model.effectiveDetailMode == .columns && model.columnsReady)
    await model.compare()
    #expect(model.detailMode == .columns)
    delay=true;model.focused=special
    let loading=Task {await model.loadDetail()};try await Task.sleep(for:.milliseconds(10))
    #expect(model.detailLoading)
    model.detailMode = .code;await loading.value
    #expect(model.detailMode == .code && model.effectiveDetailMode == .code)
    model.focused=nil;await model.loadDetail()
    #expect(model.detailMode == .code)
    model.invalidate();#expect(model.detailMode == .code)
  }
  @Test func clearingSelectionAndChangingConnectionDuringDetailNeverPublishesStalePreview() async throws {
    let model=model(reader:{endpoint,sql in
      if !sql.contains("StudioSchemaInventory") && !sql.contains("StudioSchemaRefinement") {try await Task.sleep(for:.milliseconds(40))}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    })
    await model.compare();model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key
    let delayed=Task {await model.loadDetail()}
    try await Task.sleep(for:.milliseconds(10))
    #expect(model.detailLoading)
    model.focused=nil;await model.loadDetail();await delayed.value
    #expect(!model.detailLoading && !model.detailReady && model.sourceSQL.isEmpty && model.detailComparison==nil)
    model.focused=model.differences.first {$0.key.name=="Customers"}?.key
    let stale=Task {await model.loadDetail()};try await Task.sleep(for:.milliseconds(10))
    model.source?.server.generation=UUID();await stale.value
    #expect(!model.detailLoading && !model.detailReady && !model.columnsReady)
    #expect(model.sourceSQL.isEmpty && model.columnDifferences.isEmpty && model.detailNotice.contains("Bağlantı değişti"))
    await model.compare();model.focused=try #require(model.differences.first {$0.key.name=="usp_Customers"}).key
    let preview=Task {await model.preparePlan()};try await Task.sleep(for:.milliseconds(10))
    model.target?.server.generation=UUID()
    #expect(await preview.value==nil && model.error.contains("Bağlantı değişti"))
  }
  @Test func partialColumnMetadataDoesNotHideReadableViewCodeOrClaimEqualColumns() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if sql.contains("StudioSchemaColumns") {result.partial=true}
      return result
    })
    await model.compare();model.focused=model.visible.first {$0.key.name=="v_ActiveBalance"}?.key
    await model.loadDetail()
    #expect(!model.columnsReady && model.columnDifferences.isEmpty && model.columnSummary=="Kolonlar alınamadı")
    #expect(model.detailComparison != nil && model.detailReady && model.detailNotice.contains("Kolonlar:"))
  }
  @Test func explorerSelectsTwoDatabaseNodesAndRejectsMixedSelection() throws {
    _=NSApplication.shared
    let state=StudioState(),server=SchemaComparisonUIFixture.server();server.online=false;state.servers=[server]
    let controller=WorkbenchController(state:state);_ = controller.view
    func descendants(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(descendants)}
    let outline=try #require(descendants(controller.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let folder=try #require(root.children.first {if case .folder(.databases)=$0.kind {return true};return false})
    outline.expandItem(folder)
    let nodes=folder.children.filter {if case .database=$0.kind {return true};return false}
    #expect(nodes.count==2)
    let indexes=IndexSet(nodes.map {outline.row(forItem:$0)})
    #expect(outline.allowsMultipleSelection)
    #expect(controller.outlineView(outline,selectionIndexesForProposedSelection:indexes)==indexes)
    var mixed=indexes;mixed.insert(0)
    #expect(controller.outlineView(outline,selectionIndexesForProposedSelection:mixed).count==1)
    server.online=true
    #expect(controller.schemaEndpoints(for:nodes).map(\.database)==["SourceDB","TargetDB"])
    outline.selectRowIndexes(indexes,byExtendingSelection:false);state.changed?()
    #expect(outline.selectedRowIndexes.count==2)
    state.changed=nil
  }
  @Test func panelHasBoundedNativeLayoutAndAccessibleActions() async throws {
    _=NSApplication.shared
    let model=model();await model.compare()
    model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key;await model.loadDetail()
    let panel=SchemaComparisonPanel(model:model,preview:{},openSQL:{_ in})
    let hosting=NSHostingView(rootView:panel)
    let window=NSWindow(contentRect:NSRect(x:-1800,y:-1800,width:1000,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.contentView=hosting;hosting.frame=NSRect(x:0,y:0,width:1000,height:680);hosting.layoutSubtreeIfNeeded()
    #expect(hosting.fittingSize.width<=1000)
    #expect(window.contentView?.bounds.height==680)
    try await Task.sleep(for:.milliseconds(50));hosting.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let inline=try #require(descendants(hosting).compactMap {$0 as? SQLInlineDiffView}.first)
    let frame=hosting.convert(inline.bounds,from:inline)
    #expect(frame.minX>=0 && frame.maxX<=1000 && frame.minY>=0 && frame.maxY<=680)
    #expect(frame.height>=300)
    #expect(inline.leftText.string.contains("SELECT") && inline.rightText.string.contains("[City]"))
    window.contentView=nil
    let controller=SchemaComparisonWindow(model:model,openSQL:{_,_ in})
    let comparison=try #require(controller.window)
    let initialSize=try #require(comparison.contentView).bounds.size
    #expect(initialSize==NSSize(width:1280,height:850))
    model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key
    await model.loadDetail()
    comparison.contentView?.layoutSubtreeIfNeeded()
    #expect(comparison.contentView?.bounds.size==initialSize)
    controller.close()
  }
}
