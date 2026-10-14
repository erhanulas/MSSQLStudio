import AppKit
import SQLServerKit
import SwiftUI

struct AgentStepEditor:View {
  let server:ConnectedServer
  @Environment(\.dismiss) private var dismiss
  @State var step:SQLAgent.Step
  let steps:[SQLAgent.Step]
  let isNew:Bool
  let open:(SQLAgent.Step)->Void
  @State private var page="Genel"
  @State private var error=""
  @State private var databases:[String]=[]
  @State private var loadingDatabases=true
  @State private var loadedDatabases=false
  @State private var databaseError=""
  @State private var databaseGeneration=0
  private var readOnly:Bool {step.subsystem != "TSQL"}
  init(server:ConnectedServer,step:SQLAgent.Step,steps:[SQLAgent.Step],isNew:Bool,initialPage:String="Genel",open:@escaping (SQLAgent.Step)->Void) {
    self.server=server;_step=State(initialValue:step);self.steps=steps;self.isNew=isNew;self.open=open
    _page=State(initialValue:initialPage)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:isNew ? "New Job Step":"Job Step Properties",icon:"list.number",subtitle:"\(step.id) · \(step.name) · \(step.subsystem)")
      Picker("Sayfa",selection:$page) {Text("Genel").tag("Genel");Text("Gelişmiş").tag("Gelişmiş")}.pickerStyle(.segmented)
      if page == "Genel" {
        StudioFormField("Adım adı") {TextField("Adım adı",text:$step.name)}.disabled(readOnly).accessibilityIdentifier("agentStepName")
        StudioFormField("Tür") {Text(step.subsystem)}
        databasePicker
        Text("Komut").font(.headline)
        if readOnly {AgentSQLPreview(sql:step.command).studioEditor()}
        else {AgentCommandEditor(text:$step.command).studioEditor().accessibilityIdentifier("agentStepCommand")}
      } else {
        ScrollView {
          VStack(alignment:.leading,spacing:20) {
            GroupBox {
              VStack(alignment:.leading,spacing:14) {
                flowPicker("Başarıda",action:$step.successAction,target:$step.successStep)
                stepField("Yeniden deneme") {
                  HStack(spacing:8) {
                    TextField("0–9999",value:$step.retryAttempts,format:.number.grouping(.never)).frame(width:90).accessibilityIdentifier("agentStepRetryAttempts")
                    Stepper("Yeniden deneme sayısı",value:$step.retryAttempts,in:0...9999).labelsHidden()
                    Text("kez").foregroundStyle(.secondary)
                    Spacer()
                  }
                }
                stepField("Denemeler arası") {
                  HStack(spacing:8) {
                    TextField("0–9999",value:$step.retryInterval,format:.number.grouping(.never)).frame(width:90).accessibilityIdentifier("agentStepRetryInterval")
                    Stepper("Denemeler arası dakika",value:$step.retryInterval,in:0...9999).labelsHidden()
                    Text("dakika").foregroundStyle(.secondary)
                    Spacer()
                  }
                }
                flowPicker("Başarısızlıkta",action:$step.failAction,target:$step.failStep)
              }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            } label: {Label("Adım akışı",systemImage:"arrow.triangle.branch").font(.headline)}
            GroupBox {
              VStack(alignment:.leading,spacing:14) {
                stepField("Çıktı dosyası") {TextField("Sunucudaki dosya yolu",text:$step.outputFile).accessibilityIdentifier("agentStepOutputFile")}
                VStack(alignment:.leading,spacing:10) {
                  flagToggle("Dosyaya ekle",mask:2)
                  flagToggle("Çıktıyı adım geçmişine ekle",mask:4)
                  Toggle("Çıktıyı msdb tablosuna yaz",isOn:Binding(get:{step.flags & 24 != 0},set:{value in step.flags = value ? (step.flags & ~24) | 8:step.flags & ~24}))
                  if step.flags & 24 != 0 {Toggle("Tablodaki mevcut çıktıya ekle",isOn:Binding(get:{step.flags & 16 != 0},set:{value in step.flags=(step.flags & ~24) | (value ? 16:8)}))}
                }.padding(.leading,192)
                stepField("Veritabanı kullanıcısı") {TextField("Boş: varsayılan bağlam",text:$step.databaseUser).accessibilityIdentifier("agentStepDatabaseUser")}
                Text("Dosya yolu SQL Server üzerindedir. Çıktı dosyası ve kullanıcı bağlamı için sunucu yetkileri geçerlidir; bu ekran yerel dosya açmaz.").font(.caption).foregroundStyle(.secondary)
              }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            } label: {Label("Çıktı ve çalışma bağlamı",systemImage:"doc.text").font(.headline)}
          }.padding(4).disabled(readOnly)
        }
      }
      if readOnly {Text("Bu adım türü salt okunur. T-SQL adımları düzenlenebilir.").foregroundStyle(.secondary)}
      if !error.isEmpty {StudioFeedback(message:error)}
      HStack {
        StudioActionButton("Vazgeç", icon:"xmark") {dismiss()}.keyboardShortcut(.cancelAction)
        Spacer()
        StudioActionButton("Değişiklik SQL’ini Aç", icon:"doc.badge.gearshape") {
          do {
            _=try SQLAgent.stepScript(jobID:UUID().uuidString,step:step,existingIDs:Set(steps.map(\.id)),isNew:isNew)
            open(step)
          } catch {self.error=error.localizedDescription}
        }.buttonStyle(StudioPrimaryButton()).disabled(readOnly).accessibilityIdentifier("agentStepScript")
      }
    }.padding(StudioMetrics.gap).frame(minWidth:700,idealWidth:900,maxWidth:.infinity,minHeight:500,idealHeight:650,maxHeight:.infinity).studioPanel().interactiveDismissDisabled().task(id:databaseGeneration) {await loadDatabases()}
  }
  private var databasePicker:some View {
    VStack(alignment:.leading,spacing:5) {
      HStack {
        StudioFormField("Veritabanı") {StudioSearchablePicker(title:"Veritabanı",values:databases,selection:$step.database)}.disabled(readOnly || loadingDatabases).accessibilityIdentifier("agentStepDatabase")
        if loadingDatabases && !readOnly {ProgressView().controlSize(.small).accessibilityLabel("Veritabanları yükleniyor")}
        Button {databaseGeneration+=1} label:{Image(systemName:"arrow.clockwise")}
          .disabled(readOnly || loadingDatabases).studioHelp("Veritabanlarını yenile").accessibilityLabel("Veritabanlarını yenile").accessibilityIdentifier("agentStepDatabaseRefresh")
      }
      if !databaseError.isEmpty {Text(databaseError).font(.caption).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("agentStepDatabaseError")}
      else if loadedDatabases && !databases.contains(step.database) {
        Text("Mevcut veritabanı listede görünmüyor; seçim korunuyor. Sunucudaki görünürlük ve erişim yetkileri geçerlidir.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private func loadDatabases() async {
    guard !readOnly else {loadingDatabases=false;return}
    loadingDatabases=true;databaseError=""
    defer {loadingDatabases=false}
    do {
      var limits=Limits();limits.rows=5000;limits.totalBytes=8*1024*1024;limits.timeout=15
      let result=try await server.catalog(Catalog.databases,database:"master",limits:limits)
      try Task.checkCancellation()
      databases=Array(Set(Catalog.rows(result).map(\.name))).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
      loadedDatabases=true
      if result.partial {databaseError="Veritabanı listesi kısmi; mevcut seçim korunuyor. Yeniden deneyin."}
      else if databases.isEmpty {databaseError="Erişilebilir veritabanı bulunamadı; mevcut seçim korunuyor."}
    } catch is CancellationError {} catch {databaseError="Veritabanları yüklenemedi: "+error.localizedDescription}
  }
  private func stepField<Content:View>(_ title:String,@ViewBuilder content:@escaping ()->Content)->some View {
    StudioFormField(title,labelWidth:180,content:content)
  }
  private func flowPicker(_ title:String,action:Binding<Int>,target:Binding<Int>)->some View {
    VStack(alignment:.leading,spacing:10) {
      stepField(title) {
        Picker(title,selection:action) {Text("Başarıyla bitir").tag(1);Text("Başarısız bitir").tag(2);Text("Sonraki adıma git").tag(3);Text("Belirli adıma git").tag(4)}.labelsHidden().accessibilityLabel(title)
      }
      if action.wrappedValue == 4 {
        stepField("Hedef adım") {
          Picker("Hedef adım",selection:target) {Text("Adım seçin").tag(0);ForEach(steps) {Text("\($0.id) · \($0.name)").tag($0.id)}}.labelsHidden().accessibilityLabel(title+" hedef adımı")
        }
      }
    }
  }
  private func flagToggle(_ title:String,mask:Int)->some View {
    Toggle(title,isOn:Binding(get:{step.flags & mask != 0},set:{value in step.flags=value ? step.flags | mask:step.flags & ~mask}))
  }
}
