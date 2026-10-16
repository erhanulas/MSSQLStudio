import AppKit
import SQLServerKit
import SwiftUI

/// Synthetic screen catalogue used only by tests or the isolated UI-smoke branch.
/// Every catalogue request is intercepted; actions never submit real SQL.
@MainActor enum StudioDesignFixture {
  enum Screen: String, CaseIterable, Identifiable {
    case connections, history, favorites, favoriteEditor, templates, assistant, about
    case table, newTable, tableStructure, view, newView, index, data, procedure, scalarFunction, tableFunction, synonym, rename, delete, properties, permissions
    case job, agentAction, agentGeneral, agentSteps, agentSchedules, agentNotifications, agentAlerts, agentTargets
    case step, advancedStep, readOnlyStep, schedule, pickSchedule, agentHistory, agentActivity
    case profiler, activity, samples, diagnostics, databaseFiles, schema, explorerIndex, databaseProperties
    case settingsAppearance, settingsEditor, settingsShortcuts, settingsWorkspace, settingsUpdates, settingsSecurity
    case resultLoading, resultRefresh, columnSearch, columnFilter, dataReview, offlineDefinition, parameters, feedback
    var id: String {rawValue}
    var size: NSSize {
      switch self {
      case .connections: NSSize(width:1080,height:700)
      case .history: NSSize(width:820,height:560)
      case .favorites: NSSize(width:900,height:660)
      case .assistant: NSSize(width:620,height:600)
      case .index,.job: NSSize(width:620,height:560)
      case .pickSchedule: NSSize(width:620,height:420)
      case .table,.newTable,.tableStructure: NSSize(width:800,height:600)
      case .agentGeneral,.agentSteps,.agentSchedules,.agentNotifications,.agentAlerts,.agentTargets: NSSize(width:1000,height:680)
      case .agentHistory: NSSize(width:960,height:640)
      case .agentActivity: NSSize(width:1060,height:640)
      case .profiler: NSSize(width:960,height:640)
      case .activity,.samples,.diagnostics,.databaseFiles: NSSize(width:1060,height:680)
      case .schema: NSSize(width:1100,height:720)
      case .settingsAppearance,.settingsEditor,.settingsShortcuts,.settingsWorkspace,.settingsUpdates,.settingsSecurity: NSSize(width:820,height:620)
      case .columnFilter: NSSize(width:380,height:480)
      case .resultLoading: NSSize(width:480,height:420)
      case .resultRefresh: NSSize(width:440,height:220)
      case .columnSearch: NSSize(width:420,height:440)
      case .parameters: NSSize(width:480,height:220)
      case .feedback: NSSize(width:620,height:300)
      case .favoriteEditor: NSSize(width:620,height:540)
      case .step,.advancedStep,.readOnlyStep: NSSize(width:700,height:500)
      case .about: NSSize(width:620,height:460)
      default: NSSize(width:620,height:480)
      }
    }
  }
  static func server() -> ConnectedServer {
    let server=ConnectedServer(profile:ServerProfile(name:"Design Fixture",host:"offline-fixture.invalid"),password:"")
    server.online=false
    server.catalogFixture=ObjectManagementUIFixture.catalog
    server.databases=[CatalogItem(id:1,name:"master"),CatalogItem(id:5,name:"DemoDB"),CatalogItem(id:6,name:"Reporting")]
    return server
  }
  static func make(_ screen:Screen) async throws -> AnyView {
    let server=server(),state=StudioState()
    state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server]
    let sql="SELECT CustomerID, Name\nFROM dbo.Customers\nWHERE Active = 1;"
    let table=try ObjectMetadata.decode(ObjectManagementUIFixture.catalog(ObjectMetadata.table(1001)),schema:"dbo",name:"Customers")
    let rows=Rows(fields:[Field("CustomerID",type:4),Field("Name")],values:[["1","Example One"],["2","Example Two"],["3",nil]])
    let routine=[RoutineParameter(id:1,name:"@City",type:"nvarchar(50)"),RoutineParameter(id:2,name:"@Count",type:"int",output:true)]
    let step=SQLAgent.Step(id:1,name:"Read customers",subsystem:"TSQL",database:"DemoDB",command:sql)
    var schedule=SQLAgent.Schedule(id:27,name:"Daily customers",enabled:true,frequency:"8",time:"090000")
    schedule.interval=62;schedule.startDate=20261014
    let doc=QueryDocument(server:server,database:"DemoDB",title:"Synthetic view")
    doc.sql="CREATE VIEW dbo.ActiveCustomers AS\n"+sql
    func show<V:View>(_ view:V)->AnyView {AnyView(view)}
    switch screen {
    case .connections: return show(ConnectionManager(servers:[server],initial:server,connect:{_,_,_ in},save:{_,_,_,_ in},loadingChanged:{_ in},cancel:{}))
    case .history:
      state.history=(0..<30).map {QueryRecord(server:server.profile.name,database:"DemoDB",text:sql,serverID:server.id,rowCount:3,seconds:Double($0)/100,status:$0 % 3 == 0 ? "Hata":"Başarılı")}
      return show(HistoryPanel(state:state,open:{_ in},insert:{_ in}))
    case .favorites,.favoriteEditor:
      let model=FavoriteQueriesModel(url:state.folder.appendingPathComponent("design-favorites-\(UUID().uuidString).json"))
      if screen == .favoriteEditor {return show(FavoriteQueryEditor(model:model,servers:[server],contextServerID:server.id,database:"DemoDB",sql:sql,name:"Active customers",close:{}))}
      return show(FavoriteQueriesPanel(state:state,model:model,contextServerID:server.id,contextDatabase:"DemoDB",insert:{_ in},editFavorite:{_,_,_ in}))
    case .templates: return show(TemplatesPanel(templates:[SQLTemplate(id:"sample",name:"Customer lookup",description:"Sentetik SQL şablonu",sql:sql)],open:{_ in}))
    case .assistant: return show(AssistantPanel(sql:sql,open:{_ in}))
    case .about: return show(AboutPanel(identity:ApplicationIdentity(info:Bundle.main.infoDictionary ?? [:]),checkUpdates:{}))
    case .table,.newTable,.tableStructure: return show(TableDesignerPanel(server:server.profile.name,database:"DemoDB",initialKind:screen == .tableStructure ? "FK":"",load:screen == .newTable ? nil:{table},open:{_ in}))
    case .view,.newView: return show(ViewDesignerPanel(document:doc,load:screen == .view ? {doc.sql}:nil,open:{_ in}))
    case .index: return show(IndexPanel(table:table.qualified,load:{table.columns.map {CatalogItem(id:$0.id,name:$0.name,detail:$0.type)}},open:{_ in}))
    case .data: return show(DataEditorPanel(load:{(table,[DataEditRow(original:["1","Example One","1","0x01"],values:["1","Example One","1","0x01"])])},open:{_ in}))
    case .procedure,.scalarFunction,.tableFunction: return show(RoutineInvocationPanel(qualified:"[dbo].[SalesByCity]",function:screen != .procedure,tableValued:screen == .tableFunction,load:{routine},open:{_ in}))
    case .synonym: return show(SynonymDesignerPanel(schema:"dbo",name:"CustomerAlias",existing:true,load:{"[DemoDB].[dbo].[Customers]"},open:{_ in}))
    case .rename: return show(RenameObjectPanel(qualified:table.qualified,name:table.name,open:{_ in}))
    case .delete: return show(DeleteObjectPanel(qualified:table.qualified,warning:"DROP TABLE tabloyu ve içindeki verileri kaldırır.",load:{ObjectManagementUIFixture.catalog("sys.sql_expression_dependencies")},open:{}))
    case .properties,.permissions: return show(ObjectPropertiesPanel(qualified:table.qualified,load:{ObjectManagementUIFixture.catalog("HAS_PERMS_BY_NAME")},open:{_ in},page:screen == .permissions ? 1:0))
    case .agentAction: return show(AgentActionPanel(server:server,name:"Demo Nightly",action:.start,open:{_ in}))
    case .job: return show(JobPanel(databases:["master","DemoDB"],open:{_ in}))
    case .agentGeneral,.agentSteps,.agentSchedules,.agentNotifications,.agentAlerts,.agentTargets:
      let pages:[Screen:String]=[.agentGeneral:"Genel",.agentSteps:"Adımlar",.agentSchedules:"Zamanlamalar",.agentNotifications:"Bildirimler",.agentAlerts:"Uyarılar",.agentTargets:"Hedefler"]
      return show(AgentPropertiesPanel(server:server,name:"Demo Nightly",initialPage:pages[screen]!,open:{_ in}))
    case .step,.advancedStep,.readOnlyStep:
      var value=step;if screen == .readOnlyStep {value.subsystem="CmdExec"}
      return show(AgentStepEditor(server:server,step:value,steps:[step],isNew:false,initialPage:screen == .advancedStep ? "Gelişmiş":"Genel",open:{_ in}))
    case .schedule: return show(AgentScheduleEditor(schedule:schedule,isNew:false,open:{_ in}))
    case .pickSchedule: return show(AgentPickSchedule(server:server,attached:[],open:{_ in}))
    case .agentHistory: return show(AgentHistoryPanel(server:server,job:"Demo Nightly",includeSteps:true))
    case .agentActivity: return show(AgentActivityPanel(server:server,history:{_ in},properties:{_ in},action:{_,_ in}))
    case .profiler:
      let model=ProfilerModel(server:server,executor:{sql in
        var result=Execution()
        if sql.contains("SELECT t.target_data") {
          let xml="<RingBufferTarget totalEventsProcessed=\"1\" droppedCount=\"0\"><event name=\"sql_batch_completed\" timestamp=\"2026-10-16T12:00:00Z\"><data name=\"batch_text\"><value>SELECT * FROM dbo.Demo;</value></data><action name=\"event_sequence\"><value>0</value></action></event></RingBufferTarget>"
          result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[xml,"0"]])]
        }
        return result
      },disconnect:{})
      let name=SQLProfiler.sessionName(UUID())
      await model.start(name:name,confirmedSQL:try model.preview(name:name))
      for _ in 0..<100 where model.lastRead==nil {try await Task.sleep(for:.milliseconds(2))}
      _ = await model.stop()
      return show(ProfilerPanel(model:model,background:{}))
    case .activity,.samples,.diagnostics:
      let model=ActivityMonitorModel(server:server)
      await model.load(includeDiagnostics:true)
      return show(ActivityMonitorPanel(model:model,initialMode:screen == .activity ? 0:screen == .samples ? 1:2,openTable:{}))
    case .databaseFiles:
      let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in DatabaseFilesUIFixture.catalog(sql,database:database)})
      await model.refresh()
      return show(DatabaseFilesPanel(model:model,openQuery:{}))
    case .schema:
      let schemaServer=SchemaComparisonUIFixture.server()
      let endpoints=[SchemaEndpoint(server:schemaServer,database:"SourceDB"),SchemaEndpoint(server:schemaServer,database:"TargetDB")]
      let model=SchemaComparisonModel(endpoints:endpoints,sourceID:endpoints[0].id,targetID:endpoints[1].id)
      await model.compare();model.focused=model.visible.first?.key;await model.loadDetail()
      return show(SchemaComparisonPanel(model:model,preview:{},openSQL:{_ in}))
    case .explorerIndex: return show(ExplorerIndexPanel(server:server,databases:["DemoDB"],refresh:{},setDefinitionIndex:{_,_ in}))
    case .databaseProperties:
      server.online=true
      server.catalogFixture={_ in
        var result=Execution();result.results=[Rows(values:[["DemoDB","ONLINE","FULL","160","Turkish_100_CI_AS","0"]]),Rows(values:[["DemoDB_Data","ROWS","8192.00","/offline-fixture/DemoDB.mdf"]])];return result
      }
      return show(ExplorerDatabasePanel(server:server,database:"DemoDB"))
    case .settingsAppearance,.settingsEditor,.settingsShortcuts,.settingsWorkspace,.settingsUpdates,.settingsSecurity:
      let sections:[Screen:SettingsSection]=[.settingsAppearance:.appearance,.settingsEditor:.editor,.settingsShortcuts:.shortcuts,.settingsWorkspace:.workspace,.settingsUpdates:.updates,.settingsSecurity:.security]
      return show(SettingsPanel(state:state,initialTab:sections[screen]!))
    case .resultLoading: return show(ResultLoadingPanel(rows:50000,refresh:0,apply:{_,_,_ in}))
    case .resultRefresh: return show(ResultRefreshPanel(seconds:15,apply:{_ in}))
    case .columnSearch: return show(ResultColumnSearch(columns:rows.fields.enumerated().map {ResultColumnChoice(id:$0.offset,name:$0.element.name,type:$0.element.dataType,hidden:false)},select:{_ in}))
    case .columnFilter: return show(ColumnFilterPanel(rows:rows,column:1,initial:ColumnRule(),apply:{_ in}))
    case .dataReview: return show(DataChangesPreview(sql:"BEGIN TRANSACTION;\nUPDATE dbo.Customers SET Name=N'Example' WHERE CustomerID=1;\nCOMMIT;",target:table.qualified,submit:{}))
    case .offlineDefinition: return show(InlineOfflineDefinitionView(preview:.init(server:server,database:"DemoDB",value:.init(id:1002,schema:"dbo",name:"ActiveCustomers",type:"V",sql:doc.sql,fetchedAt:Date())),back:{},navigate:{_ in}))
    case .parameters: return show(SQLParameterHelp(name:"dbo.SalesByCity",parameters:routine,active:0,status:nil))
    case .feedback: return show(VStack(spacing:12) {StudioFeedback(message:"Bağlantı zaman aşımına uğradı. "+String(repeating:"Ayrıntılı sunucu hatası. ",count:100));StudioFeedback(message:"Kısmi metadata · Önceki veriler korunuyor.",tone:.warning);StudioFeedback(message:"İşlem tamamlandı.",tone:.success);Spacer()}.padding(12).studioPanel())
    }
  }
}

struct StudioDesignGallery:View {
  @State private var selected=StudioDesignFixture.Screen.table
  @State private var content:AnyView?
  @State private var error=""
  var body:some View {
    VStack(spacing:0) {
      HStack {
        Text("İzole tasarım kontrolü").font(.headline)
        Picker("Ekran",selection:$selected) {ForEach(StudioDesignFixture.Screen.allCases) {Text($0.rawValue).tag($0)}}.frame(width:300)
        Spacer()
        Button("Açık") {StudioTheme.apply("light")}
        Button("Koyu") {StudioTheme.apply("dark")}
      }.padding(8)
      Divider()
      if let content {content}
      else {ProgressView()}
      if !error.isEmpty {Text(error)}
    }.task(id:selected) {
      content=nil
      do {let view=try await StudioDesignFixture.make(selected);try Task.checkCancellation();content=view}
      catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
