import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ModuleReviewController: NSObject, NSWindowDelegate {
  private let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:1400,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  private let left=NSScrollView(),right=NSScrollView(),script=NSScrollView()
  private let body=NSView(),summary=NSTextField(labelWithString:"Farklar hazırlanıyor…")
  private let tabs=NSSegmentedControl(labels:["Yan yana farklar","Çalıştırılacak SQL"],trackingMode:.selectOne,target:nil,action:nil)
  private let split=NSSplitView()
  private let apply=NSButton(title:"Veritabanına Gönder",target:nil,action:nil)
  private var syncing=false
  private var task:Task<Void,Never>?
  private var approved: (() -> Void)?
  private var finished: (() -> Void)?
  private var observers:[NSObjectProtocol]=[]
  init(parent:NSWindow,title:String,original:String,edited:String,canApply:Bool,approved:@escaping () -> Void,finished:@escaping () -> Void) {
    super.init()
    self.approved=approved;self.finished=finished
    panel.title="Nesne değişikliklerini incele";panel.minSize=NSSize(width:960,height:600);panel.delegate=self
    if let visible=parent.screen?.visibleFrame {
      panel.setContentSize(NSSize(width:min(1400,visible.width*0.94),height:min(840,visible.height*0.90)))
    }
    let host=NSView();panel.contentView=host
    let heading=NSTextField(labelWithString:title);heading.font = .systemFont(ofSize:14,weight:.semibold)
    summary.font = .systemFont(ofSize:11);summary.textColor = .secondaryLabelColor
    let top=NSStackView(views:[heading,summary,tabs]);top.orientation = .vertical;top.alignment = .leading;top.spacing=8
    top.edgeInsets=NSEdgeInsets(top:16,left:18,bottom:12,right:18)
    tabs.selectedSegment=0;tabs.target=self;tabs.action=#selector(changeTab)
    split.isVertical=true;split.dividerStyle = .thin
    for (scroll,label) in [(left,"Açılan tanım"),(right,"Düzenlenen tanım")] {
      configure(scroll,text:"")
      let caption=NSTextField(labelWithString:label);caption.font = .systemFont(ofSize:12,weight:.semibold)
      let column=NSStackView(views:[caption,scroll]);column.orientation = .vertical;column.spacing=8;column.edgeInsets=NSEdgeInsets(top:10,left:12,bottom:10,right:12)
      scroll.widthAnchor.constraint(equalTo:column.widthAnchor,constant:-24).isActive=true
      split.addArrangedSubview(column)
    }
    let oversized=original.utf16.count>1_000_000 || edited.utf16.count>1_000_000
    let previewOriginal=oversized ? String(original.prefix(200_000)):original
    let previewEdited=oversized ? String(edited.prefix(200_000)):edited
    configure(script,text:previewEdited)
    for view in [split,script] {embed(view,in:body)}
    script.isHidden=true
    let cancel=NSButton(title:canApply ? "Vazgeç":"Kapat",target:self,action:#selector(closeReview));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}"
    apply.target=self;apply.action=#selector(submit);apply.bezelStyle = .rounded;apply.isHidden = !canApply;apply.isEnabled=false
    let note=NSTextField(labelWithString:canApply ? "SQL yalnızca Veritabanına Gönder’e bastığınızda gönderilir.":"Bu ekran karşılaştırma içindir; SQL gönderilmez.");note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor
    let footer=NSStackView(views:[note,NSView(),cancel,apply]);footer.edgeInsets=NSEdgeInsets(top:12,left:18,bottom:14,right:18)
    let stack=NSStackView(views:[top,body,footer]);stack.orientation = .vertical;stack.spacing=0
    embed(stack,in:host)
    for view in [top,body,footer] {view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    body.setContentHuggingPriority(.init(1),for:.vertical)
    for scroll in [left,right] {
      scroll.contentView.postsBoundsChangedNotifications=true
      observers.append(NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) { [weak self,weak scroll] _ in
        MainActor.assumeIsolated {guard let self,let scroll,!self.syncing else {return};self.syncing=true
          let other=scroll === self.left ? self.right:self.left
          other.contentView.scroll(to:NSPoint(x:other.contentView.bounds.minX,y:scroll.contentView.bounds.minY));other.reflectScrolledClipView(other.contentView);self.syncing=false}
      })
    }
    parent.beginSheet(panel)
    task=Task { [weak self] in
      let comparison=await Task.detached(priority:.userInitiated) {SQLTextDiff.compare(previewOriginal,previewEdited)}.value
      guard let self,!Task.isCancelled else {return}
      render(comparison,to:left,old:true,source:previewOriginal);render(comparison,to:right,old:false,source:previewEdited)
      summary.stringValue="−\(comparison.removed) kaldırılan  ·  +\(comparison.added) eklenen satır"+(comparison.simplified ? "  ·  Büyük değişiklik için blok karşılaştırması":"")
      let truncated=oversized || comparison.lines.count>10_000
      if truncated {summary.stringValue="Büyük tanım: kısmi önizleme (en çok 10.000 satır). Buradan uygulanamaz; tam SQL sorgu sekmesindedir."}
      apply.isEnabled=canApply && !truncated && (comparison.added+comparison.removed)>0
      split.setPosition(split.bounds.width/2,ofDividerAt:0)
    }
  }
  private func embed(_ child:NSView,in parent:NSView) {
    parent.addSubview(child);child.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:parent.leadingAnchor),child.trailingAnchor.constraint(equalTo:parent.trailingAnchor),child.topAnchor.constraint(equalTo:parent.topAnchor),child.bottomAnchor.constraint(equalTo:parent.bottomAnchor)])
  }
  private func configure(_ scroll:NSScrollView,text:String) {
    let view=NSTextView(usingTextLayoutManager:true);view.identifier = .init("sqlSourcePreview");view.isEditable=false;view.isSelectable=true;view.font=StudioTheme.codeFont
    view.backgroundColor=StudioTheme.editorCanvas;view.textColor=StudioTheme.editorText;view.textContentStorage?.textStorage?.setAttributedString(SQLSourceHighlighting.attributed(text));view.textContainerInset=NSSize(width:12,height:8)
    view.isVerticallyResizable=true;view.isHorizontallyResizable=true;view.autoresizingMask=[]
    view.textContainer?.widthTracksTextView=false;view.textContainer?.containerSize=NSSize(width:100_000,height:CGFloat.greatestFiniteMagnitude)
    scroll.documentView=view;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
    size(view,in:scroll,text:text)
  }
  private func size(_ view:NSTextView,in scroll:NSScrollView,text:String) {
    let lines=text.components(separatedBy:"\n")
    let width=(lines.map {($0 as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width}.max() ?? 0)+32
    view.textContainer?.containerSize=NSSize(width:max(490,width),height:CGFloat.greatestFiniteMagnitude)
    view.setFrameSize(NSSize(width:max(490,width),height:max(450,CGFloat(lines.count)*20+32)))
    let style=EditorController.codeParagraph()
    view.defaultParagraphStyle=style
    view.textContentStorage?.textStorage?.addAttribute(.paragraphStyle,value:style,range:NSRange(location:0,length:(view.string as NSString).length))
  }
  private func render(_ comparison:SQLTextDiff.Comparison,to scroll:NSScrollView,old:Bool,source:String) {
    guard let view=scroll.documentView as? NSTextView else {return}
    let attributed=NSMutableAttributedString(string:"")
    let colored=SQLSourceHighlighting.attributed(source)
    var offsets:[Int]=[],offset=0
    for line in source.components(separatedBy:"\n") {offsets.append(offset);offset += line.utf16.count+1}
    var firstChange:NSRange?
    for row in comparison.lines.prefix(10_000) {
      let number=old ? row.oldNumber:row.newNumber,value=old ? row.old:row.new
      let prefix=number.map {String(format:"%5d  ",$0)} ?? "       "
      let line=NSMutableAttributedString(string:prefix,attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.lineNumber])
      if let value,let number,offsets.indices.contains(number-1) {
        line.append(colored.attributedSubstring(from:NSRange(location:offsets[number-1],length:value.utf16.count)))
      }
      line.append(NSAttributedString(string:"\n",attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.editorText]))
      let start=attributed.length;attributed.append(line)
      if row.changed {
        attributed.addAttribute(.backgroundColor,value:(value == nil ? StudioTheme.panel:old ? StudioTheme.color(0xFCE5E5,0x502D36):StudioTheme.color(0xE3F3EA,0x254B3A)),range:NSRange(location:start,length:line.length))
        if let value {
          let a=Array(value.utf16),b=Array(((old ? row.new:row.old) ?? "").utf16)
          var prefixCount=0,suffixCount=0
          while prefixCount<min(a.count,b.count),a[prefixCount] == b[prefixCount] {prefixCount+=1}
          while suffixCount<min(a.count,b.count)-prefixCount,a[a.count-1-suffixCount] == b[b.count-1-suffixCount] {suffixCount+=1}
          // Keep UTF-16 ranges on composed-character boundaries (including emoji).
          let raw=NSRange(location:prefixCount,length:a.count-prefixCount-suffixCount)
          let changed=raw.length>0 ? (value as NSString).rangeOfComposedCharacterSequences(for:raw):raw
          let range=NSRange(location:start+prefix.utf16.count+changed.location,length:changed.length)
          if range.length>0 {attributed.addAttribute(.backgroundColor,value:old ? StudioTheme.color(0xF2BABA,0x784150):StudioTheme.color(0xACE0C4,0x3B7154),range:range)}
          if firstChange == nil {firstChange=range}
        }
      }
    }
    view.textContentStorage?.textStorage?.setAttributedString(attributed);size(view,in:scroll,text:attributed.string)
    if let firstChange {view.scrollRangeToVisible(firstChange)}
    // Start at the line beginning: jumping to an inline change can otherwise hide
    // the object name and the first half of a long SQL line.
    scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.contentView.bounds.minY))
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  @objc private func changeTab() {split.isHidden=tabs.selectedSegment != 0;script.isHidden=tabs.selectedSegment == 0}
  @objc private func submit() {guard apply.isEnabled else {return};let action=approved;dismiss();action?()}
  @objc private func closeReview() {dismiss()}
  private func dismiss() {
    task?.cancel();for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]
    panel.sheetParent?.endSheet(panel);panel.orderOut(nil);finished?();finished=nil;approved=nil
  }
  func windowShouldClose(_ sender:NSWindow) -> Bool {dismiss();return false}
}

private struct AgentSQLPreview:NSViewRepresentable {
  let sql:String
  func makeNSView(context:Context) -> NSScrollView {
    let scroll=NSScrollView();scroll.hasVerticalScroller=true
    let text=NSTextView(usingTextLayoutManager:true);text.isEditable=false;text.isSelectable=true;text.font=StudioTheme.codeFont
    text.isVerticallyResizable=true;text.autoresizingMask=[.width];text.textContainerInset=NSSize(width:10,height:10)
    scroll.documentView=text;return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    guard let text=scroll.documentView as? NSTextView else {return}
    if text.string != sql {text.string=sql}
    text.backgroundColor=StudioTheme.canvas;text.textColor=StudioTheme.text
  }
}

extension WorkbenchController {
  func showAgentHistory(_ node:TreeNode) {
    present(AgentHistoryPanel(server:node.server,job:node.objectFolder == .jobs ? node.item?.name:nil),title:"SQL Server Agent · History",width:1080,height:700)
  }
  func showAgentProperties(_ node:TreeNode) {
    guard let item=node.item else {return}
    present(AgentPropertiesPanel(server:node.server,name:item.name,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Job Properties · "+item.name)
    }),title:"Job Properties · "+item.name,width:1000,height:720)
  }
  func showAgentAction(_ node:TreeNode,action:SQLAgent.Action) {
    guard let item=node.item else {return}
    present(AgentActionPanel(server:node.server,name:item.name,action:action,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Agent · "+action.rawValue+" · "+item.name)
    }),title:"SQL Server Agent · "+action.rawValue,width:740,height:520)
  }
  func showAgentActivity(_ node:TreeNode) {
    present(AgentActivityPanel(server:node.server,history:{[weak self] in self?.showAgentHistory(node)}),title:"SQL Server Agent · Job Activity",width:1040,height:680)
  }
  func showAgentSchedule(_ node:TreeNode) {
    guard let item=node.item else {return}
    present(AgentSchedulePanel(item:item,open:{[weak self] sql in self?.stageAgentSQL(sql,server:node.server,title:"Schedule · "+item.name)}),title:"Schedule Properties · "+item.name,width:740,height:480)
  }
  private func stageAgentSQL(_ sql:String,server:ConnectedServer,title:String) {
    let doc=state.newQuery(server:server,database:"msdb",text:sql,title:title)
    view.window?.makeKeyAndOrderFront(nil)
    doc.managedObjectApplied={ [weak doc] in
      guard let doc,doc.lastExecutedSQL == sql else {return}
      NotificationCenter.default.post(name:.init("studioAgentChanged"),object:server)
    }
  }
}

private struct AgentHistoryPanel:View {
  let server:ConnectedServer
  let job:String?
  @State private var rows:[SQLAgent.History]=[]
  @State private var status = -1
  @State private var days=30
  @State private var steps=false
  @State private var loading=false
  @State private var error=""
  @State private var selected:Int?
  @State private var generation=0
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Job History",icon:"clock.arrow.circlepath",subtitle:server.profile.name+" · "+(job ?? "Tüm işler"))
      HStack {
        Picker("Durum",selection:$status) {Text("Tümü").tag(-1);Text("Succeeded").tag(1);Text("Failed").tag(0);Text("Retry").tag(2);Text("Canceled").tag(3);Text("In Progress").tag(4)}.frame(width:210)
        Picker("Son",selection:$days) {Text("1 gün").tag(1);Text("7 gün").tag(7);Text("30 gün").tag(30);Text("365 gün").tag(365)}.frame(width:150)
        Toggle("Adımları göster",isOn:$steps)
        Spacer()
        Button {generation+=1} label:{Label("Yenile",systemImage:"arrow.clockwise")}.disabled(loading)
      }
      if loading {ProgressView().controlSize(.small)}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      Table(rows,selection:$selected) {
        TableColumn("Durum") {Text($0.statusLabel).foregroundStyle($0.status == 0 ? .red:$0.status == 1 ? .green:.secondary)}.width(100)
        TableColumn("İş",value:\.job)
        TableColumn("Adım") {Text($0.step == 0 ? "Job outcome":"\($0.step) · \($0.stepName)")}
        TableColumn("Başlangıç",value:\.started).width(160)
        TableColumn("Süre",value:\.duration).width(80)
      }
      if let row=rows.first(where:{$0.id == selected}) {
        ScrollView {Text(row.message).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(12)}.frame(minHeight:48,maxHeight:140).background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:6))
      }
      Text("\(rows.count) kayıt · En yeni 500 kayıt · Sunucunun yerel tarih/saat bilgisi. Kaydı seçerek ayrıntısını okuyun.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task(id:"\(generation)|\(status)|\(days)|\(steps)") {
      loading=true;error="";defer {loading=false}
      do {let result=try await server.catalog(SQLAgent.history(name:job,status:status<0 ? nil:status,days:days,includeSteps:steps),database:"msdb");try Task.checkCancellation();rows=try SQLAgent.decodeHistory(result);selected=nil}
      catch is CancellationError {} catch {rows=[];self.error=error.localizedDescription}
    }
  }
}

private struct AgentActionPanel:View {
  let server:ConnectedServer
  let name:String
  let action:SQLAgent.Action
  let open:(String)->Void
  @State private var sql=""
  @State private var job:SQLAgent.Job?
  @State private var busy=false
  @State private var error=""
  @State private var done=false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:action.rawValue.capitalized+" Job",icon:action == .delete ? "trash":"clock.badge.checkmark",subtitle:server.profile.name+" · "+name)
      if let job {Text("\(job.enabled ? "Enabled":"Disabled") · \(job.state) · Owner: \(job.owner)").foregroundStyle(.secondary)}
      Text(action == .start ? "İşin adımları çalıştırılır; komut kabul edilmesi işin başarıyla tamamlandığı anlamına gelmez. Sonucu History’den izleyin.":action == .stop ? "Çalışan iş durdurulur. Önceden tamamlanan adımların etkileri geri alınmaz.":action == .delete ? "İş ve iş geçmişi silinir. Paylaşılan zamanlamalar korunur.":"İşin etkinlik ayarı değiştirilir; devam eden çalışma durdurulmaz.").font(.callout)
      AgentSQLPreview(sql:sql).studioEditor()
      if !error.isEmpty {Text(error).foregroundStyle(done ? .green:.red).textSelection(.enabled)}
      HStack {
        if busy {ProgressView().controlSize(.small)}
        Spacer()
        Button("SQL’i Sorgu Sekmesine Aktar") {open(sql)}.disabled(sql.isEmpty || busy)
        // Explicit command action, separate from property/design SQL generation.
        Button(action == .delete ? "İşi Sil":"Uygula") {apply()}.buttonStyle(StudioPrimaryButton()).disabled(sql.isEmpty || busy || done)
      }
    }.padding(20).studioPanel().task {
      busy=true;defer {busy=false}
      do {let output=try await server.catalog(SQLAgent.jobs(name:name),database:"msdb");job=try SQLAgent.decodeJobs(output).first;guard let job else {throw SQLFailure("İş bulunamadı.")};sql=try SQLAgent.command(action,id:job.id)}catch {self.error=error.localizedDescription}
    }
  }
  private func apply() {
    guard !busy,!done,!sql.isEmpty else {return};busy=true;error=""
    Task { @MainActor in
      defer {busy=false}
      do {
        let result=try await server.catalog(sql,database:"msdb")
        guard !result.partial else {throw SQLFailure("Komut sonucu kısmi; durumu yenileyerek kontrol edin.")}
        done=true;error=action == .start ? "Başlatma isteği kabul edildi. Sonucu History’den izleyin.":"İşlem tamamlandı."
        NotificationCenter.default.post(name:.init("studioAgentChanged"),object:server)
      } catch {self.error=error.localizedDescription}
    }
  }
}

private struct AgentPropertiesPanel:View {
  let server:ConnectedServer
  let name:String
  let open:(String)->Void
  @State private var job:SQLAgent.Job?
  @State private var title=""
  @State private var description=""
  @State private var enabled=false
  @State private var steps:[SQLAgent.Step]=[]
  @State private var schedules:[SQLAgent.Schedule]=[]
  @State private var selected:Int?
  @State private var stepName=""
  @State private var database=""
  @State private var command=""
  @State private var error=""
  @State private var loading=true
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Job Properties",icon:"gearshape.2",subtitle:server.profile.name+" · "+name)
      if loading {ProgressView()}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      TabView {
        VStack(alignment:.leading,spacing:14) {
          TextField("Ad",text:$title)
          Toggle("Enabled",isOn:$enabled)
          Text("Owner: \(job?.owner ?? "") · Durum: \(job?.state ?? "") · Son değişiklik: \(job?.modified ?? "")").foregroundStyle(.secondary)
          Text("Açıklama").font(.headline)
          TextEditor(text:$description).studioEditor()
          Button("Değişiklik SQL’ini İncele") {prepareGeneral()}.disabled(job == nil)
        }.padding(14).tabItem {Label("Genel",systemImage:"info.circle")}
        VStack(alignment:.leading,spacing:10) {
          Table(steps,selection:$selected) {TableColumn("#") {Text("\($0.id)")}.width(35);TableColumn("Ad",value:\.name);TableColumn("Tür",value:\.subsystem);TableColumn("Veritabanı",value:\.database)}.frame(minHeight:120,maxHeight:170)
          TextField("Adım adı",text:$stepName);TextField("Veritabanı",text:$database)
          TextEditor(text:$command).font(.custom(StudioTheme.codeFont.fontName,size:13)).studioEditor()
          HStack {
            Text("Mevcut T-SQL adımlarını düzenleyebilirsiniz; diğer subsystem’ler salt okunurdur.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Adım SQL’ini İncele") {prepareStep()}.disabled(steps.first(where:{$0.id == selected})?.subsystem != "TSQL")
          }
        }.padding(14).tabItem {Label("Adımlar",systemImage:"list.number")}
        VStack(alignment:.leading,spacing:12) {
          Table(schedules) {TableColumn("Ad",value:\.name);TableColumn("Etkin") {Text($0.enabled ? "Enabled":"Disabled")};TableColumn("Frequency type",value:\.frequency);TableColumn("Başlangıç (HHMMSS)",value:\.time)}
          Text("Paylaşılan zamanlamaları Object Explorer → SQL Server Agent → Schedules üzerinden yönetin. Yeni iş oluşturma ekranı günlük zamanlama ekleyebilir.").font(.caption).foregroundStyle(.secondary)
        }.padding(14).tabItem {Label("Zamanlamalar",systemImage:"calendar")}
      }.disabled(job == nil)
      Text("Özellik değişiklikleri önce sorgu sekmesine aktarılır; siz çalıştırana kadar sunucu değişmez.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task {
      defer {loading=false}
      do {let result=try SQLAgent.decodeDetails(await server.catalog(SQLAgent.details(name:name),database:"msdb"));job=result.0;steps=result.1;schedules=result.2;title=result.0.name;description=result.0.description;enabled=result.0.enabled}
      catch {self.error=error.localizedDescription}
    }.onChange(of:selected) {_,value in
      if let step=steps.first(where:{$0.id == value}) {stepName=step.name;database=step.database;command=step.command}
    }
  }
  private func prepareGeneral() {guard let job else {return};do {open(try SQLAgent.update(job,name:title,description:description,enabled:enabled))}catch {self.error=error.localizedDescription}}
  private func prepareStep() {guard let job,let step=steps.first(where:{$0.id == selected}) else {return};do {open(try SQLAgent.updateStep(jobID:job.id,step:step,name:stepName,database:database,command:command))}catch {self.error=error.localizedDescription}}
}

private struct AgentActivityPanel:View {
  let server:ConnectedServer
  let history:()->Void
  @State private var jobs:[SQLAgent.Job]=[]
  @State private var error=""
  @State private var service="Agent servisi sorgulanıyor…"
  @State private var generation=0
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Job Activity Monitor",icon:"waveform.path.ecg",subtitle:server.profile.name)
      HStack {Text(service).foregroundStyle(.secondary);Spacer();Button("History",action:history);Button("Yenile") {generation+=1}}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      Table(jobs) {TableColumn("İş",value:\.name);TableColumn("Enabled") {Text($0.enabled ? "Enabled":"Disabled")};TableColumn("Durum",value:\.state);TableColumn("Owner",value:\.owner);TableColumn("Son değişiklik",value:\.modified)}
      Text("En çok 1.000 iş · Anlık yenileme. Job işlemlerini Explorer sağ menüsünden yapın. Agent servisini başlatma/durdurma sunucu işletim sisteminden yönetilir.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task(id:generation) {
      do {let result=try await server.catalog(SQLAgent.jobs(),database:"msdb");try Task.checkCancellation();jobs=try SQLAgent.decodeJobs(result);error=""}catch is CancellationError {} catch {self.error=error.localizedDescription}
      do {let result=try await server.catalog(SQLAgent.serviceStatus,database:"master");try Task.checkCancellation();service=result.results.first?.values.map {$0.compactMap {$0}.joined(separator:" · ")}.joined(separator:"\n") ?? "";if service.isEmpty {service="Agent servisi bu instance için raporlanmadı."}}catch is CancellationError {} catch {service="Servis durumu okunamadı: "+error.localizedDescription}
    }
  }
}

private struct AgentSchedulePanel:View {
  let item:CatalogItem
  let open:(String)->Void
  @State private var enabled=false
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      StudioPanelHeading(title:"Schedule Properties",icon:"calendar",subtitle:item.name)
      Toggle("Enabled",isOn:$enabled)
      Text("Bu zamanlama birden çok işe bağlı olabilir. Değişiklik bağlı tüm işleri etkiler. SQL’i inceleyerek çalıştırın.").foregroundStyle(.secondary)
      Spacer()
      if !error.isEmpty {Text(error).foregroundStyle(.red)}
      Button("Değişiklik SQL’ini İncele") {do {open(try SQLAgent.scheduleState(id:item.id,enabled:enabled))}catch {self.error=error.localizedDescription}}
    }.padding(20).studioPanel().onAppear {enabled = !item.detail.contains("Disabled")}
  }
}
