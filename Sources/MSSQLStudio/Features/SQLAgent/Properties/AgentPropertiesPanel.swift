import AppKit
import SQLServerKit
import SwiftUI

struct AgentPropertiesPanel:View {
  static let refreshRequested=Notification.Name("studioAgentPropertiesRefreshRequested")
  let server:ConnectedServer
  let name:String
  let open:(String)->Void
  var history:()->Void = {}
  @State private var job:SQLAgent.Job?
  @State private var loadedServerGeneration:UUID?
  @State private var title=""
  @State private var description=""
  @State private var owner=""
  @State private var category=""
  @State private var startStep=1
  @State private var enabled=false
  @State private var steps:[SQLAgent.Step]=[]
  @State private var schedules:[SQLAgent.Schedule]=[]
  @State private var selected:Int?
  @State private var selectedSchedule:Int?
  @State private var editingStep:SQLAgent.Step?
  @State private var editingSchedule:SQLAgent.Schedule?
  @State private var newStep=false
  @State private var newSchedule=false
  @State private var page="Genel"
  @State private var emailLevel=0
  @State private var emailOperator=""
  @State private var eventLogLevel=0
  @State private var deleteLevel=0
  @State private var error=""
  @State private var loading=true
  @State private var generation=0
  @State private var pendingStatements:[String]=[]
  @State private var confirmSave=false
  @State private var savedMessage=""
  @State private var confirmRefresh=false
  @State private var confirmDeleteStep=false
  @State private var confirmDetach=false
  @State private var pickSchedule=false
  private let pages=["Genel","Adımlar","Zamanlamalar","Uyarılar","Bildirimler","Hedefler"]
  init(server:ConnectedServer,name:String,initialPage:String="Genel",open:@escaping (String)->Void,history:@escaping ()->Void = {}) {
    self.server=server;self.name=name;self.open=open;self.history=history
    _page=State(initialValue:initialPage)
  }
  private func pageIcon(_ page: String) -> String {
    switch page {
    case "Genel": return "slider.horizontal.3"
    case "Adımlar": return "list.number"
    case "Zamanlamalar": return "calendar"
    case "Bildirimler": return "bell"
    case "Uyarılar": return "exclamationmark.triangle"
    default: return "server.rack"
    }
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        StudioPanelHeading(title:"Job Properties",icon:"gearshape.2",subtitle:server.profile.name+" · "+(job?.name ?? name))
        Spacer()
        StudioActionButton("Geçmiş", icon:"clock.arrow.circlepath", tint:.accentColor,action:history).accessibilityIdentifier("agentPropertiesHistory")
        StudioActionButton("Yenile", icon:"arrow.clockwise", tint:.accentColor) {confirmRefresh=true}.disabled(loading)
      }
      if loading {ProgressView().controlSize(.small)}
      if !error.isEmpty {StudioFeedback(message:error)}
      if !savedMessage.isEmpty {StudioFeedback(message:savedMessage,tone:.success)}
      HSplitView {
        VStack(alignment:.leading) {
          Text("İş ayarları").font(.caption).foregroundStyle(.secondary).padding(.horizontal,10)
          ForEach(pages,id:\.self) {item in
            StudioNavigationItem(title: item, icon: pageIcon(item), selected: page == item) { page = item }
              .accessibilityIdentifier("agentPage" + item)
          }
          Spacer()
          Text("\(server.profile.name)\nmsdb").font(.caption).foregroundStyle(.secondary).padding(10)
        }.padding(6).background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: StudioMetrics.cardRadius)).frame(minWidth:155,idealWidth:170,maxWidth:220)
        Group {
          switch page {
          case "Genel":generalPage
          case "Adımlar":stepsPage
          case "Zamanlamalar":schedulesPage
          case "Bildirimler":notificationsPage
          case "Uyarılar":AgentRelatedPage(server:server,name:job?.name ?? name,targets:false)
          default:AgentRelatedPage(server:server,name:job?.name ?? name,targets:true)
          }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(12).disabled(job == nil || loading)
      }
      Divider()
      HStack {
        Text("Kaydet, onayınızla değişiklikleri sunucuya gönderir ve güncel Job bilgilerini yeniden okur.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Group {
          StudioActionButton("Kaydet", icon:"square.and.arrow.down") {preparePage()}.buttonStyle(StudioPrimaryButton()).disabled(job == nil || loading || !hasDraft).accessibilityIdentifier("agentPropertiesScript")
        }
      }
    }.padding(StudioMetrics.gap).studioPanel().task(id:generation) {await load()}
      .onReceive(NotificationCenter.default.publisher(for:Self.refreshRequested)) {notification in
        guard notification.object as? UUID == server.id,notification.userInfo?["name"] as? String == name,!loading else {return}
        if let job,title != job.name || description != job.description || enabled != job.enabled || owner != job.owner || category != job.category || startStep != job.startStep || emailLevel != job.emailLevel || emailOperator != job.emailOperator || eventLogLevel != job.eventLogLevel || deleteLevel != job.deleteLevel {confirmRefresh=true}
        else {generation+=1}
      }
      .studioConfirmation("Job değişiklikleri sunucuya kaydedilsin mi?",isPresented:$confirmSave,role:"saveAgentJob",
        message:server.profile.name+" / msdb · "+(job?.name ?? name),
        actions:[StudioConfirmationAction(title:"Kaydet") {save()}],cancel:{pendingStatements=[]})
      .studioConfirmation("Kaydedilmemiş alanlar sunucudaki değerlerle değiştirilsin mi?",isPresented:$confirmRefresh,role:"refreshAgentJob",message:"",
        actions:[StudioConfirmationAction(title:"Sunucudan Yenile",destructive:true) {generation+=1}])
      .studioConfirmation("Adım silinsin mi?",isPresented:$confirmDeleteStep,role:"deleteAgentStep",
        message:"Adım numaraları ve akış hedefleri değişebilir; adımın çıktı günlüğü de silinir.",
        actions:[StudioConfirmationAction(title:"Adımı Sil",destructive:true) {if let job,let selected {stage {try SQLAgent.deleteStep(jobID:job.id,stepID:selected)}}}])
      .studioConfirmation("Zamanlama işten ayrılsın mı?",isPresented:$confirmDetach,role:"detachAgentSchedule",
        message:"Yalnız bu işle bağlantısı kaldırılacak. Paylaşılan zamanlama silinmez.",
        actions:[StudioConfirmationAction(title:"İşten Ayır") {if let job,let selectedSchedule {stage {try SQLAgent.detachSchedule(jobID:job.id,scheduleID:selectedSchedule)}}}])
      .sheet(isPresented:$pickSchedule) {
        AgentPickSchedule(server:server,attached:Set(schedules.map(\.id))) {schedule in
          guard let job else {return};stage {try SQLAgent.attachSchedule(jobID:job.id,scheduleID:schedule.id)};pickSchedule=false
        }.studioSheetPlacement(role:"agentPickSchedule",minimum:NSSize(width:620,height:420))
      }
      .sheet(item:$editingStep) {step in
        AgentStepEditor(server:server,step:step,steps:steps,isNew:newStep) {edited in
          guard let job else {return}
          stage {try SQLAgent.stepScript(jobID:job.id,step:edited,existingIDs:Set(steps.map(\.id)),isNew:newStep)}
          selected=edited.id;editingStep=nil
        }.studioSheetPlacement(role:"agentStepEditor",minimum:NSSize(width:700,height:500))
      }
      .sheet(item:$editingSchedule) {schedule in
        AgentScheduleEditor(schedule:schedule,isNew:newSchedule,submitTitle:"Kaydet") {edited in
          guard let job else {return}
          stage {try SQLAgent.scheduleScript(edited,jobID:newSchedule ? job.id:nil)}
          editingSchedule=nil
        }.studioSheetPlacement(role:"agentScheduleEditor",minimum:NSSize(width:620,height:480))
      }
  }
  private var generalPage:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:14) {
        Text("Genel").font(.title2)
        StudioFormField("Ad") {TextField("İş adı",text:$title).accessibilityIdentifier("agentJobName")}
        StudioFormField("Sahip") {TextField("Login adı",text:$owner)}
        StudioFormField("Kategori") {TextField("Kategori",text:$category)}
        Toggle("Enabled · İş etkin",isOn:$enabled)
        Text("Açıklama").font(.headline)
        TextEditor(text:$description).frame(minHeight:140).studioEditor()
        Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:8) {
          GridRow {Text("Oluşturulma");Text(SQLAgent.displayDate(job?.created ?? ""))}
          GridRow {Text("Son değişiklik");Text(SQLAgent.displayDate(job?.modified ?? ""))}
          GridRow {Text("Son çalışma");Text(SQLAgent.displayDate(job?.lastRun ?? ""))}
          GridRow {Text("Son sonuç");AgentStatus(status:job?.lastStatus ?? -1)}
          GridRow {Text("Durum");Text(job?.state ?? "")}
        }.foregroundStyle(.secondary).textSelection(.enabled)
        Text("Sahip değişikliği için sysadmin yetkisi gerekir. Etkinliği kapatmak çalışan işi durdurmaz.").font(.caption).foregroundStyle(.secondary)
      }.padding(4)
    }
  }
  private var stepsPage:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Adımlar").font(.title2)
      Table(steps,selection:$selected) {
        TableColumn("#") {Text("\($0.id)")}.width(32)
        TableColumn("Ad",value:\.name)
        TableColumn("Tür",value:\.subsystem).width(80)
        TableColumn("Başarıda") {Text(SQLAgent.flowLabel($0.successAction,step:$0.successStep))}
        TableColumn("Hatada") {Text(SQLAgent.flowLabel($0.failAction,step:$0.failStep))}
        TableColumn("Tekrar") {Text("\($0.retryAttempts) / \($0.retryInterval) dk")}.width(85)
      }.accessibilityIdentifier("agentStepsTable").contextMenu(forSelectionType:Int.self,menu:{ids in
        StudioActionButton("Düzenle…", icon:"pencil", tint:.accentColor) {newStep=false;editingStep=steps.first {ids.contains($0.id)}}.disabled(ids.isEmpty)
        StudioActionButton("Sil…", icon:"trash", tint:.red) {selected=ids.first;confirmDeleteStep=true}.disabled(ids.isEmpty)
      },primaryAction:{ids in newStep=false;editingStep=steps.first {ids.contains($0.id)}})
      HStack {
        StudioActionButton("Yeni…", icon:"plus", tint:.accentColor) {newStep=true;editingStep=SQLAgent.Step(id:(steps.map(\.id).max() ?? 0)+1,name:"Yeni adım",subsystem:"TSQL",database:"master",command:"")}.accessibilityIdentifier("agentNewStep")
        StudioActionButton("Düzenle…", icon:"pencil", tint:.accentColor) {newStep=false;editingStep=steps.first {$0.id == selected}}.disabled(selected == nil).accessibilityIdentifier("agentEditStep")
        StudioActionButton("Sil…", icon:"trash", tint:.red) {confirmDeleteStep=true}.disabled(selected == nil)
        Spacer()
      }
      StudioFormField("Başlangıç adımı") {Picker("Başlangıç adımı",selection:$startStep) {ForEach(steps) {Text("\($0.id) · \($0.name)").tag($0.id)}}.labelsHidden()}.accessibilityIdentifier("agentStartStep")
      Text("T-SQL adımları Genel/Gelişmiş sayfalarından düzenlenir. Diğer adım türlerinin komutları salt okunur görüntülenir.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var schedulesPage:some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Zamanlamalar").font(.title2)
      Table(schedules,selection:$selectedSchedule) {
        TableColumn("Ad",value:\.name)
        TableColumn("Etkin") {Text($0.enabled ? "Evet":"Hayır")}.width(55)
        TableColumn("Tekrar",value:\.summary)
        TableColumn("Bağlı iş") {Text("\($0.jobCount)")}.width(65)
      }.accessibilityIdentifier("agentSchedulesTable").contextMenu(forSelectionType:Int.self,menu:{ids in
        StudioActionButton("Düzenle…", icon:"pencil", tint:.accentColor) {newSchedule=false;editingSchedule=schedules.first {ids.contains($0.id)}}.disabled(ids.isEmpty)
      },primaryAction:{ids in newSchedule=false;editingSchedule=schedules.first {ids.contains($0.id)}})
      HStack {
        StudioActionButton("Yeni…", icon:"plus", tint:.accentColor) {newSchedule=true;var s=SQLAgent.Schedule(id:0,name:"Yeni zamanlama",enabled:true,frequency:"4",time:"090000");let f=DateFormatter();f.dateFormat="yyyyMMdd";s.startDate=Int(f.string(from:Date())) ?? 19900101;editingSchedule=s}
        StudioActionButton("Düzenle…", icon:"pencil", tint:.accentColor) {newSchedule=false;editingSchedule=schedules.first {$0.id == selectedSchedule}}.disabled(selectedSchedule == nil).accessibilityIdentifier("agentEditSchedule")
        StudioActionButton("Mevcut Zamanlamayı Seç…", icon:"calendar.badge.plus", tint:.accentColor) {pickSchedule=true}
        StudioActionButton("İşten Ayır…", icon:"link", tint:.orange) {confirmDetach=true}.disabled(selectedSchedule == nil)
        Spacer()
      }
      Text("Paylaşılan zamanlamayı düzenlemek bağlı bütün işleri etkiler. İşten Ayır, zamanlamayı silmeden yalnız bu işle bağlantısını kaldırır.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var notificationsPage:some View {
    VStack(alignment:.leading,spacing:16) {
      Text("Bildirimler").font(.title2)
      conditionPicker("E-posta",value:$emailLevel)
      StudioFormField("Operatör") {TextField("SQL Server Agent operatör adı",text:$emailOperator)}.disabled(emailLevel == 0)
      Text("E-posta için sunucuda Database Mail ve Agent mail ayarları yapılandırılmış olmalı. Bu ekran operatörün adını kullanır.").font(.caption).foregroundStyle(.secondary)
      conditionPicker("Uygulama olay günlüğü",value:$eventLogLevel)
      Divider()
      conditionPicker("İşi otomatik sil",value:$deleteLevel)
      if deleteLevel != 0 {Label("Seçilen koşulda iş ve geçmişi otomatik silinir.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)}
      Text("Mevcut pager/net send ayarları değiştirilmez. Bildirim gönderimi sunucuda gerçekleşir.").font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
  }
  private func conditionPicker(_ title:String,value:Binding<Int>)->some View {
    StudioFormField(title) {Picker(title,selection:value) {Text("Hiçbir zaman").tag(0);Text("Başarılı olduğunda").tag(1);Text("Başarısız olduğunda").tag(2);Text("Tamamlandığında").tag(3)}.labelsHidden()}
  }
  private func load() async {
    let token=server.generation
    loadedServerGeneration=nil;loading=true;error="";savedMessage="";defer {loading=false}
    do {
      let query=try job.map {try SQLAgent.details(id:$0.id)} ?? SQLAgent.details(name:name)
      let output=try await server.catalog(query,database:"msdb")
      let result=try await Task.detached(priority:.userInitiated) {try SQLAgent.decodeDetails(output)}.value
      try Task.checkCancellation()
      guard token==server.generation else {throw CancellationError()}
      loadedServerGeneration=token
      apply(result)
    } catch is CancellationError {} catch {job=nil;self.error=error.localizedDescription}
  }
  private var hasDraft:Bool {
    guard let job else {return false}
    return title != job.name || description != job.description || enabled != job.enabled || owner != job.owner || category != job.category || startStep != job.startStep || emailLevel != job.emailLevel || emailOperator != job.emailOperator || eventLogLevel != job.eventLogLevel || deleteLevel != job.deleteLevel
  }
  private func draftStatements() throws -> [String] {
    guard let job else {return []}
    var statements:[String]=[]
    if title != job.name || description != job.description || enabled != job.enabled || owner != job.owner || category != job.category || startStep != job.startStep {
      statements.append(try SQLAgent.generalScript(job,name:title,description:description,enabled:enabled,owner:owner,category:category,startStep:startStep,stepIDs:Set(steps.map(\.id))))
    }
    if emailLevel != job.emailLevel || emailOperator != job.emailOperator || eventLogLevel != job.eventLogLevel || deleteLevel != job.deleteLevel {
      statements.append(try SQLAgent.notifications(jobID:job.id,emailLevel:emailLevel,operatorName:emailOperator,eventLogLevel:eventLogLevel,deleteLevel:deleteLevel))
    }
    return statements
  }
  private func stage(_ generate:()throws->String) {
    do {try stageStatements(draftStatements()+[generate()])} catch {self.error=error.localizedDescription}
  }
  private func stageStatements(_ statements:[String]) throws {
    guard !loading,let job else {return}
    guard loadedServerGeneration==server.generation else {throw SQLFailure("Bağlantı değişti; kaydetmeden önce Job bilgilerini yenileyin.")}
    _=try SQLAgent.checkedScript(statements,job:job)
    error="";savedMessage="";pendingStatements=statements;confirmSave=true
  }
  private func apply(_ result:(SQLAgent.Job,[SQLAgent.Step],[SQLAgent.Schedule])) {
    job=result.0;steps=result.1;schedules=result.2;title=result.0.name;description=result.0.description;enabled=result.0.enabled
    owner=result.0.owner;category=result.0.category;startStep=result.0.startStep;emailLevel=result.0.emailLevel;emailOperator=result.0.emailOperator;eventLogLevel=result.0.eventLogLevel;deleteLevel=result.0.deleteLevel
    if !steps.contains(where:{$0.id==selected}) {selected=steps.first?.id}
    if !schedules.contains(where:{$0.id==selectedSchedule}) {selectedSchedule=schedules.first?.id}
  }
  private func save() {
    guard !loading,let job,!pendingStatements.isEmpty else {return}
    guard loadedServerGeneration==server.generation else {error="Bağlantı değişti; Job bilgilerini yenileyin.";pendingStatements=[];return}
    let statements=pendingStatements,token=server.generation
    pendingStatements=[];loading=true;error="";savedMessage=""
    Task { @MainActor in
      defer {loading=false}
      do {
        let result=try await SQLAgent.saveProperties(statements:statements,job:job) {sql in
          guard await MainActor.run(body:{server.generation==token}) else {throw SQLFailure("Bağlantı değişti; Job işlemi durduruldu.")}
          return try await server.catalog(sql,database:"msdb")
        }
        guard token==server.generation else {throw SQLFailure("Bağlantı değişti; Job bilgilerini yenileyin.")}
        apply(result);savedMessage="Kaydedildi · Sunucudaki güncel bilgiler yüklendi."
        NotificationCenter.default.post(name:.init("studioAgentChanged"),object:server)
      } catch {self.error=error.localizedDescription}
    }
  }
  private func preparePage() {
    do {try stageStatements(draftStatements())} catch {self.error=error.localizedDescription}
  }
}
