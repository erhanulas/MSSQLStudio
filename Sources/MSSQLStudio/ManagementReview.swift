import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ModuleReviewController: NSObject, NSWindowDelegate {
  private let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:1400,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  private let left=NSScrollView(),right=NSScrollView(),script=NSScrollView()
  private let body=NSView(),summary=NSTextField(labelWithString:"Farklar hazırlanıyor…")
  private let tabs=NSSegmentedControl(labels:["Yan yana farklar","Çalıştırılacak SQL"],trackingMode:.selectOne,target:nil,action:nil)
  private let split=NSSplitView()
  private let apply=StudioToolbarButton(symbol:"paperplane.fill",label:"Veritabanına Gönder",tone:.accent,title:"Veritabanına Gönder",width:175,prominent:true)
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
    let host=NSView();StudioTheme.surface(host);panel.contentView=host
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
    let cancel=StudioToolbarButton(symbol:"xmark",label:canApply ? "Vazgeç":"Kapat",tone:.neutral,title:canApply ? "Vazgeç":"Kapat",width:80);cancel.target=self;cancel.action=#selector(closeReview);cancel.keyEquivalent="\u{1b}"
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
    text.identifier = .init("sqlSourcePreview");text.isVerticallyResizable=true;text.autoresizingMask=[.width];text.textContainerInset=NSSize(width:10,height:10)
    scroll.documentView=text;return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    guard let text=scroll.documentView as? NSTextView else {return}
    if text.string != sql {text.textContentStorage?.textStorage?.setAttributedString(SQLSourceHighlighting.attributed(sql))}
    text.backgroundColor=StudioTheme.canvas
  }
}

extension WorkbenchController {
  func showAgentHistory(_ node:TreeNode) {
    presentAgent(AgentHistoryPanel(server:node.server,job:node.objectFolder == .jobs ? node.item?.name:nil),title:"SQL Server Agent · History",width:1380,height:820,minWidth:960,minHeight:640,identity:"agent.history|\(node.server.id)|\(node.objectFolder == .jobs ? "job:"+(node.item?.name ?? "") : "all")")
  }
  func showAgentProperties(_ node:TreeNode) {
    guard let item=node.item else {return}
    presentAgent(AgentPropertiesPanel(server:node.server,name:item.name,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Job Properties · "+item.name)
    },history:{[weak self] in self?.showAgentHistory(node)}),title:"Job Properties · "+item.name,width:1220,height:800,minWidth:1000,minHeight:680,identity:"agent.properties|\(node.server.id)|\(item.name)")
  }
  func showAgentAction(_ node:TreeNode,action:SQLAgent.Action) {
    guard let item=node.item else {return}
    presentAgent(AgentActionPanel(server:node.server,name:item.name,action:action,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Agent · "+action.rawValue+" · "+item.name)
    }),title:"SQL Server Agent · "+action.rawValue,width:740,height:520)
  }
  func showAgentActivity(_ node:TreeNode) {
    let server=node.server
    func jobNode(_ job:SQLAgent.Job)->TreeNode {TreeNode(job.name,kind:.object(.jobs),server:server,item:CatalogItem(name:job.name))}
    presentAgent(AgentActivityPanel(server:server,history:{[weak self] name in
      if let name {self?.showAgentHistory(TreeNode(name,kind:.object(.jobs),server:server,item:CatalogItem(name:name)))} else {self?.showAgentHistory(node)}
    },properties:{[weak self] job in self?.showAgentProperties(jobNode(job))},action:{[weak self] job,action in self?.showAgentAction(jobNode(job),action:action)}),title:"SQL Server Agent · Job Activity",width:1400,height:800,minWidth:1060,minHeight:640)
  }
  func showAgentSchedule(_ node:TreeNode) {
    guard let item=node.item else {return}
    weak var panelWindow:NSWindow?
    panelWindow=presentAgent(AgentSchedulePanel(server:node.server,item:item,close:{panelWindow?.close()},open:{[weak self] sql in self?.stageAgentSQL(sql,server:node.server,title:"Schedule · "+item.name)}),title:"Schedule Properties · "+item.name,width:820,height:760)
  }
  @discardableResult private func presentAgent<V:View>(_ root:V,title:String,width:CGFloat,height:CGFloat,minWidth:CGFloat=620,minHeight:CGFloat=480,identity:String?=nil)->NSWindow {
    let frame=(view.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:width/0.94,height:height/0.94)
    let width=min(width,frame.width*0.94),height=min(height,frame.height*0.94)
    return present(root,title:title,width:width,height:height,minWidth:min(minWidth,width),minHeight:min(minHeight,height),identity:identity)
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

struct AgentHistoryPanel:View {
  let server:ConnectedServer
  let job:String?
  init(server:ConnectedServer,job:String?,includeSteps:Bool=false) {
    self.server=server;self.job=job;_steps=State(initialValue:includeSteps)
  }
  @State private var rows:[SQLAgent.History]=[]
  @State private var cachedTree:[SQLAgent.History]=[]
  @State private var status = -1
  @State private var days=7
  @State private var steps=false
  @State private var search=""
  @State private var loading=false
  @State private var error=""
  @State private var selected:Int?
  @State private var generation=0
  @State private var requestID=UUID()
  private var tree:[SQLAgent.History] {
    let tree=cachedTree
    guard !search.isEmpty else {return tree}
    return tree.filter {row in
      ([row]+(row.children ?? [])).contains {($0.job+" "+$0.stepName+" "+$0.message).localizedCaseInsensitiveContains(search)}
    }
  }
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      StudioPanelHeading(title:"Log File Viewer · Job History",icon:"clock.arrow.circlepath",subtitle:server.profile.name+" · "+(job ?? "Tüm işler"))
      HStack {
        Picker("Durum",selection:$status) {Text("Tümü").tag(-1);Text("Succeeded").tag(1);Text("Failed").tag(0);Text("Retry").tag(2);Text("Canceled").tag(3);Text("In Progress").tag(4)}.frame(width:210).accessibilityIdentifier("agentHistoryStatus")
        Picker("Son",selection:$days) {Text("1 gün").tag(1);Text("7 gün").tag(7);Text("30 gün").tag(30);Text("365 gün").tag(365);Text("10 yıl").tag(3650)}.frame(width:150)
        Toggle("Adım ayrıntıları",isOn:$steps).help("İlk açılışta çalışma sonuçları alınır. Adım ve yeniden deneme ayrıntıları için açın.")
        Spacer()
        Button {generation+=1} label:{Label("Yenile",systemImage:"arrow.clockwise")}.disabled(loading).accessibilityIdentifier("agentHistoryRefresh")
      }
      TextField("Yüklenen çalışmalarda iş, adım veya mesaj ara",text:$search).textFieldStyle(.roundedBorder).accessibilityIdentifier("agentHistorySearch")
      Text("Filtre: \(days) gün · \(status < 0 ? "Tüm sonuçlar":"Seçili iş sonucu") · \(tree.count) çalışma. Durum filtresi iş sonucuna uygulanır; alt adımlar kendi sonuçlarıyla gösterilir.").font(.caption).foregroundStyle(.secondary)
      if loading {HStack {ProgressView().controlSize(.small);Text("Geçmiş yükleniyor… Önceki sonuçlar yükleme bitene kadar korunur.").font(.caption)}}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      VSplitView {
        Table(tree,children:\.children,selection:$selected) {
          TableColumn("Çalışma / Adım") {row in
            Label(row.step == 0 ? row.job:"\(row.step) · \(row.stepName)",systemImage:row.step == 0 ? "clock":"list.number")
          }.width(min:180,ideal:290)
          TableColumn("Durum") {AgentStatus(status:$0.status)}.width(110)
          TableColumn("Başlangıç",value:\.started).width(165)
          TableColumn("Süre",value:\.duration).width(85)
          TableColumn("Tekrar") {Text("\($0.retries)")}.width(55)
          TableColumn("Mesaj",value:\.message).width(min:180,ideal:320)
        }.frame(minHeight:180,idealHeight:350).accessibilityIdentifier("agentHistoryTable")
        Group {
          if let row=rows.first(where:{$0.id == selected}) {
            ScrollView {
              VStack(alignment:.leading,spacing:8) {
                HStack {Text("Seçili kayıt ayrıntıları").font(.headline);Spacer();StudioActionButton("Kopyala", icon:"doc.on.doc", tint:.accentColor) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(historyDetails(row),forType:.string)}}
                Text("\(row.job) · \(row.step == 0 ? "İş sonucu":row.stepName) · \(row.statusLabel)")
                Text("Sunucu: \(row.server)    Başlangıç: \(row.started)    Süre: \(row.duration)")
                Text("SQL mesajı: \(String(row.messageID))    Önem derecesi: \(row.severity)    Yeniden deneme: \(row.retries)").foregroundStyle(.secondary)
                Divider()
                Text(row.message).font(.system(size:12,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("agentHistoryMessage")
              }.textSelection(.enabled).padding(12)
            }
          } else {
            ScrollView {Text(rows.isEmpty && !loading ? "Bu filtreye uygun geçmiş kaydı yok.":(steps ? "İşin yanındaki oku açarak adımları görün; mesajın tamamını okumak için bir kayıt seçin.":"Bir çalışma seçerek mesajı okuyun; adımlar için Adım ayrıntıları seçeneğini açın.")).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:196,alignment:.center)}
          }
        }.frame(minHeight:220,idealHeight:220,maxHeight:400).background(Color(nsColor:StudioTheme.canvas))
      }
      Text(rows.count >= 5001 ? "5.000 kayıt sınırına ulaşıldı; en eski çalışmanın adımları eksik olabilir. Tarih filtresini daraltın.":"En yeni 500 tamamlanmış çalışma · Sunucunun yerel saati. Devam eden işleri Job Activity Monitor’den izleyin; geçmiş, adımlar tamamlandıkça oluşur.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task(id:"\(generation)|\(status)|\(days)|\(steps)") {
      let token=UUID();requestID=token;loading=true;error=""
      defer {if requestID == token {loading=false}}
      do {
        let result=try await server.catalog(SQLAgent.history(name:job,status:status<0 ? nil:status,days:days,includeSteps:steps),database:"msdb")
        try Task.checkCancellation();guard requestID == token else {return}
        let decoded=try await Task.detached(priority:.userInitiated) {
          let rows=try SQLAgent.decodeHistory(result)
          return (rows,SQLAgent.historyTree(rows))
        }.value
        try Task.checkCancellation();guard requestID == token else {return}
        rows=decoded.0;cachedTree=decoded.1
        if !rows.contains(where:{$0.id == selected}) {selected=nil}
      } catch is CancellationError {} catch {if requestID == token {self.error=error.localizedDescription}}
    }
  }
  private func historyDetails(_ row:SQLAgent.History)->String {
    "\(row.job) · \(row.stepName)\n\(row.statusLabel) · \(row.started) · \(row.duration)\nSQL \(row.messageID), Severity \(row.severity), Retries \(row.retries)\n\(row.message)"
  }
}
private struct AgentStatus:View {
  let status:Int
  var body:some View {
    HStack(spacing:5) {
      Image(systemName:status == 1 ? "checkmark.circle.fill":status == 0 ? "xmark.circle.fill":status == 4 ? "arrow.triangle.2.circlepath":status == 2 ? "arrow.clockwise":"minus.circle")
        .foregroundStyle(status == 1 ? Color.green:status == 0 ? .red:status == 4 ? .blue:.secondary)
      Text(label)
    }.accessibilityElement(children:.ignore).accessibilityLabel(label)
  }
  private var label:String {switch status {case 0:"Failed";case 1:"Succeeded";case 2:"Retry";case 3:"Canceled";case 4:"Running";default:"—"}}
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
  @State private var startAt=""
  @State private var steps:[SQLAgent.Step]=[]
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:action.rawValue.capitalized+" Job",icon:action == .delete ? "trash":"clock.badge.checkmark",subtitle:server.profile.name+" · "+name)
      if let job {Text("\(job.enabled ? "Enabled":"Disabled") · \(job.state) · Owner: \(job.owner)").foregroundStyle(.secondary)}
      Text(action == .start ? "İşin adımları çalıştırılır; komut kabul edilmesi işin başarıyla tamamlandığı anlamına gelmez. Sonucu History’den izleyin.":action == .stop ? "Çalışan iş durdurulur. Önceden tamamlanan adımların etkileri geri alınmaz.":action == .delete ? "İş ve iş geçmişi silinir. Paylaşılan zamanlamalar korunur.":"İşin etkinlik ayarı değiştirilir; devam eden çalışma durdurulmaz.").font(.callout)
      if action == .start {
        Picker("Başlatılacak adım",selection:$startAt) {Text("İşin tanımlı başlangıç adımı").tag("");ForEach(steps) {Text("\($0.id) · \($0.name)").tag($0.name)}}.disabled(busy || done)
      }
      AgentSQLPreview(sql:sql).studioEditor()
      if !error.isEmpty {Text(error).foregroundStyle(done ? .green:.red).textSelection(.enabled)}
      HStack {
        if busy {ProgressView().controlSize(.small)}
        Spacer()
        StudioActionButton("SQL’i Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) {open(sql)}.disabled(sql.isEmpty || busy)
        // Explicit command action, separate from property/design SQL generation.
        StudioActionButton(action == .delete ? "İşi Sil":"Uygula",icon:action == .delete ? "trash":"checkmark") {apply()}.buttonStyle(StudioPrimaryButton()).disabled(sql.isEmpty || busy || done)
      }
    }.padding(20).studioPanel().task {
      busy=true;defer {busy=false}
      do {
        let output=try await server.catalog(action == .start ? SQLAgent.details(name:name):SQLAgent.jobs(name:name),database:"msdb")
        if action == .start {let details=try SQLAgent.decodeDetails(output);job=details.0;steps=details.1} else {job=try SQLAgent.decodeJobs(output).first}
        guard let job else {throw SQLFailure("İş bulunamadı.")};sql=try SQLAgent.command(action,id:job.id)
      } catch {self.error=error.localizedDescription}
    }.onChange(of:startAt) {_,value in
      guard let job else {return}
      do {sql=try SQLAgent.command(action,id:job.id,stepName:value.isEmpty ? nil:value)} catch {sql="";self.error=error.localizedDescription}
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

struct AgentPropertiesPanel:View {
  let server:ConnectedServer
  let name:String
  let open:(String)->Void
  var history:()->Void = {}
  @State private var job:SQLAgent.Job?
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
  @State private var confirmRefresh=false
  @State private var confirmDeleteStep=false
  @State private var confirmDetach=false
  @State private var pickSchedule=false
  private let pages=["Genel","Adımlar","Zamanlamalar","Uyarılar","Bildirimler","Hedefler"]
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
        StudioPanelHeading(title:"Job Properties",icon:"gearshape.2",subtitle:server.profile.name+" · "+name)
        Spacer()
        StudioActionButton("Geçmiş", icon:"clock.arrow.circlepath", tint:.accentColor,action:history).accessibilityIdentifier("agentPropertiesHistory")
        StudioActionButton("Yenile", icon:"arrow.clockwise", tint:.accentColor) {confirmRefresh=true}.disabled(loading)
      }
      if loading {ProgressView().controlSize(.small)}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      HSplitView {
        VStack(alignment:.leading) {
          Text("Sayfa seçin").font(.caption).foregroundStyle(.secondary).padding(.horizontal,10)
          ForEach(pages,id:\.self) {item in
            StudioNavigationItem(title: item, icon: pageIcon(item), selected: page == item) { page = item }
              .accessibilityIdentifier("agentPage" + item)
          }
          Spacer()
          Text("\(server.profile.name)\nmsdb").font(.caption).foregroundStyle(.secondary).padding(10)
        }.padding(6).background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 12)).frame(minWidth:155,idealWidth:170,maxWidth:220)
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
        Text("Değişiklikler önce SQL olarak açılır. Çalıştırdıktan sonra Yenile ile sunucudaki durumu okuyun.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        if page == "Genel" || page == "Bildirimler" {
          StudioActionButton("Değişiklik SQL’ini Aç", icon:"doc.badge.gearshape") {preparePage()}.buttonStyle(StudioPrimaryButton()).disabled(job == nil || loading).accessibilityIdentifier("agentPropertiesScript")
        }
      }
    }.padding(20).studioPanel().task(id:generation) {await load()}
      .confirmationDialog("Kaydedilmemiş alanlar sunucudaki değerlerle değiştirilsin mi?",isPresented:$confirmRefresh) {Button("Sunucudan Yenile",role:.destructive) {generation+=1}}
      .confirmationDialog("Adım silinirse adım numaraları ve akış hedefleri değişebilir; adımın çıktı günlüğü de silinir.",isPresented:$confirmDeleteStep) {Button("Silme SQL’ini Aç",role:.destructive) {if let job,let selected {stage {try SQLAgent.deleteStep(jobID:job.id,stepID:selected)}}}}
      .confirmationDialog("Zamanlamanın yalnız bu işle bağlantısı kaldırılacak. Paylaşılan zamanlama silinmez.",isPresented:$confirmDetach) {Button("Bağlantı Kaldırma SQL’ini Aç") {if let job,let selectedSchedule {stage {try SQLAgent.detachSchedule(jobID:job.id,scheduleID:selectedSchedule)}}}}
      .sheet(isPresented:$pickSchedule) {
        AgentPickSchedule(server:server,attached:Set(schedules.map(\.id))) {schedule in
          guard let job else {return};stage {try SQLAgent.attachSchedule(jobID:job.id,scheduleID:schedule.id)};pickSchedule=false
        }
      }
      .sheet(item:$editingStep) {step in
        AgentStepEditor(server:server,step:step,steps:steps,isNew:newStep) {edited in
          guard let job else {return}
          stage {try SQLAgent.stepScript(jobID:job.id,step:edited,existingIDs:Set(steps.map(\.id)),isNew:newStep)}
          editingStep=nil
        }
      }
      .sheet(item:$editingSchedule) {schedule in
        AgentScheduleEditor(schedule:schedule,isNew:newSchedule) {edited in
          guard let job else {return}
          stage {try SQLAgent.scheduleScript(edited,jobID:newSchedule ? job.id:nil)}
          editingSchedule=nil
        }
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
          GridRow {Text("Oluşturulma");Text(job?.created ?? "")}
          GridRow {Text("Son değişiklik");Text(job?.modified ?? "")}
          GridRow {Text("Son çalışma");Text(job?.lastRun ?? "")}
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
      StudioActionButton("Başlangıç Adımı SQL’ini Aç", icon:"list.number", tint:.accentColor) {guard let job else {return};stage {try SQLAgent.generalScript(job,name:job.name,description:job.description,enabled:job.enabled,owner:job.owner,category:job.category,startStep:startStep,stepIDs:Set(steps.map(\.id)))}}.disabled(steps.isEmpty || startStep == job?.startStep)
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
    loading=true;error="";defer {loading=false}
    do {
      let query=try job.map {try SQLAgent.details(id:$0.id)} ?? SQLAgent.details(name:name)
      let output=try await server.catalog(query,database:"msdb")
      let result=try await Task.detached(priority:.userInitiated) {try SQLAgent.decodeDetails(output)}.value
      try Task.checkCancellation()
      job=result.0;steps=result.1;schedules=result.2;title=result.0.name;description=result.0.description;enabled=result.0.enabled
      owner=result.0.owner;category=result.0.category;startStep=result.0.startStep;emailLevel=result.0.emailLevel;emailOperator=result.0.emailOperator;eventLogLevel=result.0.eventLogLevel;deleteLevel=result.0.deleteLevel
      selected=steps.first?.id;selectedSchedule=schedules.first?.id
    } catch is CancellationError {} catch {job=nil;self.error=error.localizedDescription}
  }
  private func stage(_ generate:()throws->String) {
    do {let sql=try SQLAgent.checkedScript([generate()],job:job);error="";open(sql)} catch {self.error=error.localizedDescription}
  }
  private func preparePage() {
    guard let job else {return}
    if page == "Genel" {stage {try SQLAgent.generalScript(job,name:title,description:description,enabled:enabled,owner:owner,category:category,startStep:startStep,stepIDs:Set(steps.map(\.id)))}}
    else {stage {try SQLAgent.notifications(jobID:job.id,emailLevel:emailLevel,operatorName:emailOperator,eventLogLevel:eventLogLevel,deleteLevel:deleteLevel)}}
  }
}

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
      if !error.isEmpty {Text(error).foregroundStyle(.red)}
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
    }.padding(20).frame(width:900,height:650).studioPanel().interactiveDismissDisabled().task(id:databaseGeneration) {await loadDatabases()}
  }
  private var databasePicker:some View {
    VStack(alignment:.leading,spacing:5) {
      HStack {
        StudioFormField("Veritabanı") {Picker("Veritabanı",selection:$step.database) {
          if !databases.contains(step.database) {
            Text(step.database.isEmpty ? "Veritabanı seçin":step.database + (loadedDatabases ? " · mevcut, listede yok":" · mevcut")).tag(step.database)
          }
          ForEach(databases,id:\.self) {Text($0).tag($0)}
        }.labelsHidden()}.disabled(readOnly || loadingDatabases).accessibilityIdentifier("agentStepDatabase")
        if loadingDatabases && !readOnly {ProgressView().controlSize(.small).accessibilityLabel("Veritabanları yükleniyor")}
        Button {databaseGeneration+=1} label:{Image(systemName:"arrow.clockwise")}
          .disabled(readOnly || loadingDatabases).help("Veritabanlarını yenile").accessibilityLabel("Veritabanlarını yenile").accessibilityIdentifier("agentStepDatabaseRefresh")
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
struct AgentCommandEditor:NSViewRepresentable {
  @Binding var text:String
  @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
    var parent:AgentCommandEditor
    weak var editor:NSTextView?
    private var source:String?
    private var dark:Bool?
    private var painting=false
    init(_ parent:AgentCommandEditor) {
      self.parent=parent
      super.init()
      NotificationCenter.default.addObserver(self,selector:#selector(themeChanged),name:StudioTheme.changed,object:nil)
      for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
        NotificationCenter.default.addObserver(self,selector:#selector(undoChanged(_:)),name:name,object:nil)
      }
    }
    // Synchronize restored text before a SwiftUI refresh can reapply the old binding.
    @objc private func undoChanged(_ notification:Notification) {
      guard let editor,let manager=notification.object as? UndoManager,manager === editor.undoManager else {return}
      parent.text=editor.string
      source=nil
      highlight(editor)
    }
    @objc private func themeChanged() {if let editor {highlight(editor)}}
    func highlight(_ view:NSTextView) {
      guard !painting,!view.hasMarkedText(),source != view.string || dark != StudioTheme.dark,
        let storage=view.textContentStorage?.textStorage else {return}
      painting=true;defer {painting=false}
      source=view.string;dark=StudioTheme.dark
      let styled=SQLSourceHighlighting.attributed(view.string)
      var changes:[(NSRange,[NSAttributedString.Key:Any])]=[]
      styled.enumerateAttributes(in:NSRange(location:0,length:styled.length)) {attributes,range,_ in
        storage.enumerateAttributes(in:range) {existing,run,_ in
          if existing[.foregroundColor] as? NSColor != attributes[.foregroundColor] as? NSColor || existing[.font] as? NSFont != attributes[.font] as? NSFont {changes.append((run,attributes))}
        }
      }
      let undo=view.undoManager,registering=undo?.isUndoRegistrationEnabled == true
      if registering {undo?.disableUndoRegistration()}
      storage.beginEditing()
      for (range,attributes) in changes {storage.addAttributes(attributes,range:range)}
      storage.endEditing()
      if registering {undo?.enableUndoRegistration()}
      view.backgroundColor=StudioTheme.editorCanvas
      view.insertionPointColor=StudioTheme.editorText
      view.typingAttributes[.foregroundColor]=StudioTheme.editorText
      view.typingAttributes[.font]=StudioTheme.codeFont
    }
    func textDidChange(_ notification:Notification) {
      guard !painting,let view=notification.object as? NSTextView else {return}
      parent.text=view.string
      highlight(view)
    }
  }
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
    let view=NSTextView(usingTextLayoutManager:true);view.isRichText=false;view.isAutomaticQuoteSubstitutionEnabled=false;view.isAutomaticDashSubstitutionEnabled=false;view.isAutomaticTextReplacementEnabled=false;view.isAutomaticSpellingCorrectionEnabled=false;view.allowsUndo=true
    view.font=StudioTheme.codeFont;view.textContainerInset=NSSize(width:10,height:10);view.isVerticallyResizable=true;view.autoresizingMask=[.width];view.delegate=context.coordinator;view.identifier = .init("agentCommandEditor");view.setAccessibilityIdentifier("agentCommandEditor")
    context.coordinator.editor=view
    scroll.documentView=view;return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    context.coordinator.parent=self
    guard let view=scroll.documentView as? NSTextView else {return}
    if view.string != text {view.string=text}
    context.coordinator.highlight(view)
  }
}
private struct AgentScheduleEditor:View {
  @Environment(\.dismiss) private var dismiss
  @State var schedule:SQLAgent.Schedule
  let isNew:Bool
  var cancel:(()->Void)? = nil
  let open:(SQLAgent.Schedule)->Void
  @State private var error=""
  private var frequency:Int {Int(schedule.frequency) ?? 4}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:isNew ? "New Job Schedule":"Schedule Properties",icon:"calendar",subtitle:schedule.name)
      if !isNew && schedule.jobCount>1 {Label("Paylaşılan zamanlama · \(schedule.jobCount) işin tamamı etkilenir.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)}
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          StudioFormField("Zamanlama adı") {TextField("Zamanlama adı",text:$schedule.name)}
          Toggle("Etkin",isOn:$schedule.enabled).padding(.leading,162)
          StudioFormField("Zamanlama türü") {Picker("Zamanlama türü",selection:$schedule.frequency) {Text("Bir kez").tag("1");Text("Günlük").tag("4");Text("Haftalık").tag("8");Text("Aylık · Gün").tag("16");Text("Aylık · Göreli gün").tag("32");Text("Agent başladığında").tag("64");Text("İşlemci boşta olduğunda").tag("128")}.labelsHidden()}
          if frequency == 4 {Stepper("Her \(schedule.interval) gün",value:$schedule.interval,in:1...999).padding(.leading,162)}
          if frequency == 8 {
            Stepper("Her \(schedule.recurrence) hafta",value:$schedule.recurrence,in:1...999).padding(.leading,162)
            HStack {ForEach(Array(["Paz","Pzt","Sal","Çar","Per","Cum","Cmt"].enumerated()),id:\.offset) {item in
              Toggle(item.element,isOn:Binding(get:{schedule.interval & (1 << item.offset) != 0},set:{value in let bit=1 << item.offset;schedule.interval=value ? schedule.interval | bit:schedule.interval & ~bit})).toggleStyle(.button)
            }}
          }
          if frequency == 16 {Stepper("Ayın \(schedule.interval). günü",value:$schedule.interval,in:1...31).padding(.leading,162)}
          if frequency == 16 || frequency == 32 {Stepper("Her \(schedule.recurrence) ay",value:$schedule.recurrence,in:1...999).padding(.leading,162)}
          if frequency == 32 {
            StudioFormField("Sıra") {Picker("Sıra",selection:$schedule.relativeInterval) {Text("İlk").tag(1);Text("İkinci").tag(2);Text("Üçüncü").tag(4);Text("Dördüncü").tag(8);Text("Son").tag(16)}.labelsHidden()}
            StudioFormField("Gün") {Picker("Gün",selection:$schedule.interval) {Text("Pazar").tag(1);Text("Pazartesi").tag(2);Text("Salı").tag(3);Text("Çarşamba").tag(4);Text("Perşembe").tag(5);Text("Cuma").tag(6);Text("Cumartesi").tag(7);Text("Gün").tag(8);Text("Hafta içi").tag(9);Text("Hafta sonu").tag(10)}.labelsHidden()}
          }
          if frequency != 64 && frequency != 128 {
            Divider()
            StudioFormField("Gün içi tekrar") {Picker("Gün içi tekrar",selection:$schedule.subdayType) {Text("Belirtilen saatte").tag(1);Text("Saniye").tag(2);Text("Dakika").tag(4);Text("Saat").tag(8)}.labelsHidden()}.disabled(frequency == 1)
            if schedule.subdayType != 1 {StudioFormField("Tekrar aralığı") {TextField("Tekrar aralığı",value:$schedule.subdayInterval,format:.number)}}
            StudioFormField("Başlangıç saati") {DatePicker("Başlangıç saati",selection:timeBinding(end:false),displayedComponents:.hourAndMinute).labelsHidden()}
            Stepper("Başlangıç saniyesi: \(Int(schedule.time).map {$0 % 100} ?? 0)",value:Binding(get:{Int(schedule.time).map {$0 % 100} ?? 0},set:{value in let n=Int(schedule.time) ?? 0;schedule.time=String(format:"%06d",n/100*100+value)}),in:0...59).padding(.leading,162)
            if schedule.subdayType != 1 {StudioFormField("Bitiş saati") {DatePicker("Bitiş saati",selection:timeBinding(end:true),displayedComponents:.hourAndMinute).labelsHidden()}}
          }
          StudioFormField("Başlangıç tarihi") {DatePicker("Başlangıç tarihi",selection:dateBinding(end:false),displayedComponents:.date).labelsHidden()}
          Toggle("Bitiş tarihi yok",isOn:Binding(get:{schedule.endDate == 99991231},set:{value in schedule.endDate=value ? 99991231:schedule.startDate}))
          if schedule.endDate != 99991231 {StudioFormField("Bitiş tarihi") {DatePicker("Bitiş tarihi",selection:dateBinding(end:true),displayedComponents:.date).labelsHidden()}}
          Text(schedule.summary).font(.callout).foregroundStyle(.secondary)
          Text("Saat ve tarihler SQL Server'ın yerel saatine göredir.").font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }
      if !error.isEmpty {Text(error).foregroundStyle(.red)}
      HStack {StudioActionButton("Vazgeç", icon:"xmark") {if let cancel {cancel()} else {dismiss()}}.keyboardShortcut(.cancelAction);Spacer();StudioActionButton("Değişiklik SQL’ini Aç", icon:"doc.badge.gearshape") {
        do {_=try SQLAgent.scheduleScript(schedule,jobID:isNew ? UUID().uuidString:nil);open(schedule)} catch {self.error=error.localizedDescription}
      }.buttonStyle(StudioPrimaryButton()).accessibilityIdentifier("agentScheduleScript")}
    }.padding(20).frame(width:760,height:670).studioPanel().interactiveDismissDisabled()
      .onChange(of:schedule.frequency) {_,newValue in
        if newValue == "1" {schedule.subdayType=1}
        if newValue == "32" && !(1...10).contains(schedule.interval) {schedule.interval=1}
        if newValue == "16" && !(1...31).contains(schedule.interval) {schedule.interval=1}
      }
  }
  private func dateBinding(end:Bool)->Binding<Date> {
    Binding(get:{
      let n=end ? schedule.endDate:schedule.startDate
      return Calendar.current.date(from:DateComponents(year:n/10000,month:(n/100)%100,day:n%100)) ?? Date()
    },set:{date in
      let c=Calendar.current.dateComponents([.year,.month,.day],from:date)
      let n=(c.year ?? 1990)*10000+(c.month ?? 1)*100+(c.day ?? 1)
      if end {schedule.endDate=n} else {schedule.startDate=n}
    })
  }
  private func timeBinding(end:Bool)->Binding<Date> {
    Binding(get:{
      let n=end ? schedule.endTime:(Int(schedule.time) ?? 0)
      return Calendar.current.date(from:DateComponents(year:2000,month:1,day:1,hour:n/10000,minute:(n/100)%100,second:n%100)) ?? Date()
    },set:{date in
      let c=Calendar.current.dateComponents([.hour,.minute],from:date)
      let seconds=(end ? schedule.endTime:(Int(schedule.time) ?? 0))%100
      let n=(c.hour ?? 0)*10000+(c.minute ?? 0)*100+seconds
      if end {schedule.endTime=n} else {schedule.time=String(format:"%06d",n)}
    })
  }

}
private struct AgentRelatedPage:View {
  let server:ConnectedServer
  let name:String
  let targets:Bool
  @State private var rows:[[String?]]=[]
  @State private var error=""
  @State private var loading=true
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      Text(targets ? "Hedef sunucular":"İşi tetikleyen uyarılar").font(.title2)
      if loading {ProgressView()}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      List(Array(rows.enumerated()),id:\.offset) {item in Text(item.element.compactMap {$0}.joined(separator:" · ")).textSelection(.enabled)}
      Text(targets ? "Bu sayfa hedef sunucuları salt okunur gösterir; çoklu sunucu dağıtımı yönetilmez.":"Bu sayfa mevcut uyarıları salt okunur gösterir. E-posta koşulları Bildirimler sayfasından düzenlenir.").font(.caption).foregroundStyle(.secondary)
      if rows.isEmpty && !loading && error.isEmpty {Text("Kayıt bulunamadı.").foregroundStyle(.secondary)}
    }.task(id:"\(targets)|\(name)") {
      loading=true;error="";defer {loading=false}
      let sql=targets ? "SELECT COALESCE(s.name,CONVERT(nvarchar(20),t.server_id)),t.last_run_outcome,t.last_run_date,t.last_run_time FROM msdb.dbo.sysjobservers t JOIN msdb.dbo.sysjobs j ON j.job_id=t.job_id LEFT JOIN master.sys.servers s ON s.server_id=t.server_id WHERE j.name=\(SQL.literal(name));":"SELECT a.name,a.enabled,a.message_id,a.severity FROM msdb.dbo.sysalerts a JOIN msdb.dbo.sysjobs j ON j.job_id=a.job_id WHERE j.name=\(SQL.literal(name));"
      do {let result=try await server.catalog(sql,database:"msdb");try Task.checkCancellation();guard !result.partial else {throw SQLFailure("Sonuç kısmi; yenileyin.")};rows=result.results.first.map {Array($0.values)} ?? []} catch is CancellationError {} catch {rows=[];self.error=error.localizedDescription}
    }
  }
}

struct AgentActivityPanel:View {
  let server:ConnectedServer
  let history:(String?)->Void
  let properties:(SQLAgent.Job)->Void
  let action:(SQLAgent.Job,SQLAgent.Action)->Void
  @State private var jobs:[SQLAgent.Job]=[]
  @State private var error=""
  @State private var service="Agent servisi sorgulanıyor…"
  @State private var generation=0
  @State private var search=""
  @State private var filter=0
  @State private var refresh=0
  @State private var selected:String?
  @State private var loading=false
  @State private var refreshed=""
  @State private var sortOrder=[KeyPathComparator(\SQLAgent.Job.name)]
  private var visible:[SQLAgent.Job] {jobs.filter {job in
    (search.isEmpty || job.name.localizedCaseInsensitiveContains(search)) &&
    (filter == 0 || (filter == 1 && job.state == "Running") || (filter == 2 && !job.enabled) || (filter == 3 && job.lastStatus == 0))
  }.sorted(using:sortOrder)}
  private var chosen:SQLAgent.Job? {visible.first {$0.id == selected}}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Job Activity Monitor",icon:"waveform.path.ecg",subtitle:server.profile.name)
      HStack {
        TextField("İş adı ara",text:$search).textFieldStyle(.roundedBorder)
        Picker("Göster",selection:$filter) {Text("Tüm işler").tag(0);Text("Çalışanlar").tag(1);Text("Devre dışı").tag(2);Text("Son çalışması hatalı").tag(3)}.frame(width:220)
        Picker("Otomatik yenile",selection:$refresh) {Text("Kapalı").tag(0);Text("15 saniye").tag(15);Text("30 saniye").tag(30);Text("60 saniye").tag(60)}.frame(width:190)
        StudioActionButton("Yenile", icon:"arrow.clockwise", tint:.accentColor) {generation+=1}.disabled(loading)
      }
      Text(service).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if loading {ProgressView().controlSize(.small)}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      Table(visible,selection:$selected,sortOrder:$sortOrder) {
        TableColumn("İş",value:\.name).width(min:150,ideal:250)
        TableColumn("Etkin") {Text($0.enabled ? "Evet":"Hayır")}.width(55)
        TableColumn("Durum") {Label($0.state,systemImage:$0.state == "Running" ? "arrow.triangle.2.circlepath":"pause.circle")}.width(100)
        TableColumn("Son sonuç") {AgentStatus(status:$0.lastStatus)}.width(110)
        TableColumn("Son çalışma",value:\.lastRun).width(165)
        TableColumn("Sonraki çalışma",value:\.nextRun).width(165)
        TableColumn("Sahip",value:\.owner)
      }.accessibilityIdentifier("agentActivityTable").contextMenu(forSelectionType:String.self,menu:{ids in
        if let job=jobs.first(where:{ids.contains($0.id)}) {
          StudioActionButton("View History…",icon:"clock.arrow.circlepath",tint:.accentColor) {history(job.name)}
          StudioActionButton("Properties…",icon:"slider.horizontal.3",tint:.accentColor) {properties(job)}
          StudioActionButton("Start Job…",icon:"play.fill",tint:.green) {action(job,.start)}.disabled(job.state == "Running")
          StudioActionButton("Stop Job…",icon:"stop.fill",tint:.orange) {action(job,.stop)}.disabled(job.state != "Running")
          StudioActionButton(job.enabled ? "Disable…":"Enable…",icon:job.enabled ? "pause.circle":"checkmark.circle",tint:job.enabled ? .orange:.green) {action(job,job.enabled ? .disable:.enable)}
        }
      },primaryAction:{ids in if let job=jobs.first(where:{ids.contains($0.id)}) {properties(job)}})
      HStack {
        StudioActionButton("Geçmiş", icon:"clock.arrow.circlepath", tint:.accentColor) {history(chosen?.name)}.accessibilityIdentifier("agentActivityHistory")
        StudioActionButton("Özellikler…", icon:"slider.horizontal.3", tint:.accentColor) {if let chosen {properties(chosen)}}.disabled(chosen == nil)
        Divider().frame(height:18)
        StudioActionButton("Başlat…", icon:"play.fill", tint:.green) {if let chosen {action(chosen,.start)}}.disabled(chosen == nil || chosen?.state == "Running")
        StudioActionButton("Durdur…", icon:"stop.fill", tint:.orange) {if let chosen {action(chosen,.stop)}}.disabled(chosen?.state != "Running")
        StudioActionButton(chosen?.enabled == false ? "Etkinleştir…":"Devre Dışı Bırak…",icon:chosen?.enabled == false ? "checkmark.circle":"pause.circle",tint:chosen?.enabled == false ? .green:.orange) {if let chosen {action(chosen,chosen.enabled ? .disable:.enable)}}.disabled(chosen == nil)
        Spacer()
        Text("\(visible.count) / \(jobs.count) iş · \(refreshed)").font(.caption).foregroundStyle(.secondary)
      }
      Text("En çok 1.000 iş. Sonraki çalışma bilgisi Agent önbelleği nedeniyle gecikmeli olabilir. Agent servisi sunucu işletim sisteminden yönetilir.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task(id:"\(generation)|\(refresh)") {
      repeat {
        await load()
        guard refresh>0,!Task.isCancelled else {return}
        do {try await Task.sleep(for:.seconds(refresh))} catch {return}
      } while !Task.isCancelled
    }.onReceive(NotificationCenter.default.publisher(for:.init("studioAgentChanged"))) {notification in
      if let changed=notification.object as? ConnectedServer,changed === server {generation+=1}
    }
  }
  private func load() async {
    loading=true;error="";defer {loading=false}
    do {
      let result=try await server.catalog(SQLAgent.jobs(),database:"msdb");try Task.checkCancellation()
      jobs=try SQLAgent.decodeJobs(result);refreshed=Date().formatted(date:.omitted,time:.standard)
      if !jobs.contains(where:{$0.id == selected}) {selected=nil}
    } catch is CancellationError {return} catch {jobs=[];selected=nil;self.error=error.localizedDescription}
    do {
      let result=try await server.catalog(SQLAgent.serviceStatus,database:"master");try Task.checkCancellation()
      service=result.results.first?.values.map {$0.compactMap {$0}.joined(separator:" · ")}.joined(separator:"\n") ?? ""
      if service.isEmpty {service="Agent servisi bu instance için raporlanmadı."}
    } catch is CancellationError {} catch {service="Servis durumu okunamadı: "+error.localizedDescription}
  }
}

private struct AgentPickSchedule:View {
  @Environment(\.dismiss) private var dismiss
  let server:ConnectedServer
  let attached:Set<Int>
  let open:(SQLAgent.Schedule)->Void
  @State private var schedules:[SQLAgent.Schedule]=[]
  @State private var selected:Int?
  @State private var error=""
  @State private var loading=true
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Pick Schedule",icon:"calendar",subtitle:"Mevcut bir zamanlamayı bu işe bağlayın")
      if loading {ProgressView()}
      if !error.isEmpty {Text(error).foregroundStyle(.red)}
      Table(schedules,selection:$selected) {TableColumn("Ad",value:\.name);TableColumn("Tekrar",value:\.summary);TableColumn("Etkin") {Text($0.enabled ? "Evet":"Hayır")}}
      Text("Zamanlama paylaşılır; ileride yapılan düzenlemeler bu işi de etkiler. Zaten bağlı zamanlamalar listede gösterilmez.").font(.caption).foregroundStyle(.secondary)
      HStack {StudioActionButton("Vazgeç", icon:"xmark") {dismiss()};Spacer();StudioActionButton("Bağlama SQL’ini Aç", icon:"link", tint:.accentColor) {if let schedule=schedules.first(where:{$0.id == selected}) {open(schedule)}}.disabled(selected == nil)}
    }.padding(20).frame(width:850,height:520).studioPanel().task {
      defer {loading=false}
      do {let result=try await server.catalog(SQLAgent.availableSchedules(),database:"msdb");try Task.checkCancellation();guard !result.partial else {throw SQLFailure("Zamanlama listesi kısmi.")};schedules=try SQLAgent.decodeSchedules(result.results.first.map {Array($0.values)} ?? []).filter {!attached.contains($0.id)}} catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
private struct AgentSchedulePanel:View {
  let server:ConnectedServer
  let item:CatalogItem
  let close:()->Void
  let open:(String)->Void
  @State private var schedule:SQLAgent.Schedule?
  @State private var error=""
  var body:some View {
    Group {
      if let schedule {AgentScheduleEditor(schedule:schedule,isNew:false,cancel:close) {edited in
        do {open(try SQLAgent.checkedScript([SQLAgent.scheduleScript(edited)]))} catch {self.error=error.localizedDescription}
      }} else {
        VStack(spacing:16) {
          if error.isEmpty {ProgressView("Zamanlama yükleniyor…")} else {Text(error).foregroundStyle(.red).textSelection(.enabled)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(20)
      }
    }.task {
      do {
        let result=try await server.catalog(SQLAgent.scheduleDetails(id:item.id),database:"msdb");try Task.checkCancellation()
        guard !result.partial else {throw SQLFailure("Zamanlama bilgisi kısmi.")}
        schedule=try SQLAgent.decodeSchedules(result.results.first.map {Array($0.values)} ?? []).first
        if schedule == nil {throw SQLFailure("Zamanlama bulunamadı.")}
      } catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
