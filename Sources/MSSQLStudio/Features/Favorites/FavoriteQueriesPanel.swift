import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class FavoriteQueriesModel:ObservableObject {
  static let changed = Notification.Name("studioFavoriteQueriesChanged")
  @Published private(set) var items:[FavoriteQuery]=[] {
    didSet {if items != oldValue {NotificationCenter.default.post(name:Self.changed,object:self)}}
  }
  @Published var error=""
  private let store:FavoriteQueryStore
  init(url:URL) {store=FavoriteQueryStore(url:url)}
  func load() async {
    do {items=try await store.load();error=""} catch {self.error=error.localizedDescription}
  }
  func save(_ value:FavoriteQuery) async throws {items=try await store.save(value);error=""}
  func matching(sql:String,serverID:UUID,database:String,preferredID:UUID?=nil) -> FavoriteQuery? {
    let sql=sql.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !sql.isEmpty else {return nil}
    let candidates=items.filter {$0.visible(serverID:serverID,database:database) && $0.sql.trimmingCharacters(in:.whitespacesAndNewlines) == sql}
    if let favorite=candidates.first(where:{$0.id == preferredID}) {return favorite}
    return candidates.first {$0.scope == .database} ?? candidates.first {$0.scope == .connection} ?? candidates.first
  }
  func delete(_ id:UUID) async throws {items=try await store.remove(id);error=""}
  func remove(_ id:UUID) async {
    do {try await delete(id)} catch {self.error=error.localizedDescription}
  }
}

extension StudioState {
  @discardableResult func openFavorite(_ favorite:FavoriteQuery,contextServerID:UUID?,contextDatabase:String) throws -> QueryDocument {
    try favorite.validate()
    let target=favorite.scope == .global ? contextServerID:favorite.serverID
    guard let server=servers.first(where:{$0.id == target}) else {throw SQLFailure("Favorinin hedef bağlantısını önce Explorer’a ekleyin veya seçin.")}
    let database=favorite.scope == .database ? favorite.database! : favorite.scope == .connection && favorite.serverID != contextServerID ? server.profile.database:contextDatabase
    guard !database.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw SQLFailure("Hedef veritabanını seçin.")}
    let doc=newQuery(server:server,database:database,text:favorite.sql,title:favorite.name,run:false)
    doc.favoriteID=favorite.id;doc.changed?()
    return doc
  }
}

@MainActor final class FavoriteQueryPickerController:NSViewController,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
  let model:FavoriteQueriesModel
  let serverID:UUID?
  let database:String
  private let contextLabel:String
  private let open:(FavoriteQuery)throws->Void
  private let insert:((FavoriteQuery)throws->Void)?
  private let manage:()->Void
  private let search=NSSearchField()
  private let table=FavoritePickerTable()
  private let scroll=NSScrollView()
  private let count=NSTextField(labelWithString:"")
  private let message=NSTextField(wrappingLabelWithString:"")
  private let empty=NSTextField(wrappingLabelWithString:"")
  private let titleLabel=NSTextField(labelWithString:"")
  private let scopeLabel=NSTextField(labelWithString:"")
  private let preview=NSHostingController(rootView:SQLReadOnlyPreview(sql:""))
  private let openButton=StudioToolbarButton(symbol:"arrow.up.right.square",label:"Favoriyi sorguda aç",tone:.accent,title:"Sorguda Aç",width:122)
  private(set) var visible:[FavoriteQuery]=[]
  var selectedFavorite:FavoriteQuery? {visible.indices.contains(table.selectedRow) ? visible[table.selectedRow]:nil}
  init(model:FavoriteQueriesModel,serverID:UUID?,database:String,contextLabel:String,open:@escaping (FavoriteQuery)throws->Void,insert:((FavoriteQuery)throws->Void)? = nil,manage:@escaping ()->Void) {
    self.model=model;self.serverID=serverID;self.database=database;self.contextLabel=contextLabel;self.open=open;self.insert=insert;self.manage=manage
    super.init(nibName:nil,bundle:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(reloadItems),name:FavoriteQueriesModel.changed,object:model)
    NotificationCenter.default.addObserver(self,selector:#selector(refreshTheme),name:StudioTheme.changed,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  override func loadView() {
    view=NSView();view.setAccessibilityIdentifier("favoriteQueryPicker")
    let icon=NSImageView(image:NSImage(systemSymbolName:"star.square.on.square",accessibilityDescription:nil)!)
    icon.contentTintColor=StudioTheme.warning;icon.symbolConfiguration=NSImage.SymbolConfiguration(pointSize:24,weight:.medium)
    let heading=NSTextField(labelWithString:"Favori Sorgular");heading.font = .systemFont(ofSize:18,weight:.semibold)
    let context=NSTextField(labelWithString:contextLabel);context.font = .systemFont(ofSize:11);context.textColor=StudioTheme.muted
    context.lineBreakMode = .byTruncatingMiddle;context.toolTip=contextLabel
    let headingText=NSStackView(views:[heading,context]);headingText.orientation = .vertical;headingText.alignment = .leading;headingText.spacing=3
    let headingRow=NSStackView(views:[icon,headingText,NSView(),count]);headingRow.spacing=12
    count.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium)
    count.setContentCompressionResistancePriority(.required,for:.horizontal)
    search.placeholderString="Favori sorgu adı ara";search.delegate=self;search.sendsSearchStringImmediately=true
    search.target=self;search.action = #selector(searchChanged);search.setAccessibilityIdentifier("favoritePickerSearch");search.setAccessibilityLabel("Favori sorgu adı ara")
    search.controlSize = .large
    let column=NSTableColumn(identifier:.init("favorite"));column.title="Favori Sorgular";column.resizingMask = .autoresizingMask
    table.addTableColumn(column);table.headerView=nil;table.rowHeight=48;table.intercellSpacing=NSSize(width:0,height:2)
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle;table.style = .plain
    table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction = #selector(insertSelected)
    table.openSelected = {[weak self] in self?.openSelected()}
    table.setAccessibilityIdentifier("favoritePickerList");table.setAccessibilityLabel("Bu sorguda kullanılabilen favoriler")
    scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.drawsBackground=false
    scroll.wantsLayer=true;scroll.layer?.cornerRadius=9;scroll.layer?.borderWidth=1
    empty.alignment = .center;empty.font = .systemFont(ofSize:12);empty.setAccessibilityIdentifier("favoritePickerEmpty")
    let list=NSView();list.addSubview(scroll);list.addSubview(empty)
    for child in [scroll,empty] {child.translatesAutoresizingMaskIntoConstraints=false}
    NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:list.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:list.trailingAnchor),scroll.topAnchor.constraint(equalTo:list.topAnchor),scroll.bottomAnchor.constraint(equalTo:list.bottomAnchor),empty.centerXAnchor.constraint(equalTo:list.centerXAnchor),empty.centerYAnchor.constraint(equalTo:list.centerYAnchor),empty.widthAnchor.constraint(lessThanOrEqualTo:list.widthAnchor,constant:-32)])
    titleLabel.font = .systemFont(ofSize:13,weight:.semibold);titleLabel.lineBreakMode = .byTruncatingTail
    scopeLabel.font = .systemFont(ofSize:11);scopeLabel.lineBreakMode = .byTruncatingMiddle
    addChild(preview);preview.sizingOptions=[]
    preview.view.wantsLayer=true;preview.view.layer?.cornerRadius=8;preview.view.layer?.masksToBounds=true
    let detail=NSStackView(views:[titleLabel,scopeLabel,preview.view]);detail.orientation = .vertical;detail.alignment = .leading;detail.spacing=8
    preview.view.setContentHuggingPriority(.init(1),for:.vertical)
    preview.view.widthAnchor.constraint(equalTo:detail.widthAnchor).isActive=true
    let body=NSStackView(views:[list,detail]);body.orientation = .horizontal;body.spacing=16;body.distribution = .fill
    list.widthAnchor.constraint(equalTo:body.widthAnchor,multiplier:0.43,constant:-8).isActive=true
    list.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true;detail.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true
    message.font = .systemFont(ofSize:11);message.isHidden=true
    let manageButton=StudioToolbarButton(symbol:"slider.horizontal.3",label:"Favori sorguları yönet",tone:.neutral,title:"Yönet",width:80)
    manageButton.target=self;manageButton.action = #selector(manageFavorites)
    openButton.target=self;openButton.action = #selector(openSelected);openButton.keyEquivalent="\r";openButton.keyEquivalentModifierMask=[]
    openButton.setAccessibilityIdentifier("favoritePickerOpen")
    let close=NSButton(title:"Vazgeç",target:self,action:#selector(closePicker));close.bezelStyle = .rounded;close.keyEquivalent="\u{1b}";close.keyEquivalentModifierMask=[]
    let help=NSTextField(labelWithString:"↑ ↓ seç · ↩ aç · esc kapat");help.font = .systemFont(ofSize:10);help.textColor=StudioTheme.muted
    let footer=NSStackView(views:[manageButton,help,NSView(),close,openButton]);footer.spacing=10
    let stack=NSStackView(views:[headingRow,search,body,message,footer]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
    view.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16)])
    for child in [headingRow,search,body,message,footer] {child.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    headingRow.heightAnchor.constraint(equalToConstant:48).isActive=true;search.heightAnchor.constraint(equalToConstant:30).isActive=true
    body.setContentHuggingPriority(.init(1),for:.vertical)
    refreshTheme();reloadItems()
  }
  override func viewDidAppear() {super.viewDidAppear();focusSearch()}
  func focusSearch() {view.window?.makeFirstResponder(search)}
  @objc func reloadItems() {
    guard isViewLoaded else {return}
    let previous=selectedFavorite?.id
    visible=FavoriteQuerySelection.matches(model.items,serverID:serverID,database:database,search:search.stringValue)
    table.reloadData()
    if let index=visible.firstIndex(where:{$0.id == previous}) ?? (visible.isEmpty ? nil:0) {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)} else {table.deselectAll(nil)}
    count.stringValue="\(visible.count) sorgu"
    empty.isHidden = !visible.isEmpty
    empty.stringValue=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Bu bağlantı ve veritabanında kullanılabilen favori yok.\nYönet bölümünden bir sorgu ekleyin.":"Aramanıza uygun favori bulunamadı."
    message.stringValue=model.error;message.isHidden=model.error.isEmpty
    updatePreview()
  }
  func numberOfRows(in tableView:NSTableView)->Int {visible.count}
  func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
    let value=visible[row],cell=NSTableCellView(),name=NSTextField(labelWithString:value.name),scope=NSTextField(labelWithString:scopeText(value))
    let image=NSImageView(image:NSImage(systemSymbolName:value.scope == .global ? "globe":value.scope == .connection ? "server.rack":"externaldrive",accessibilityDescription:nil)!)
    image.contentTintColor=StudioTheme.warning
    name.font = .systemFont(ofSize:12,weight:.medium);name.lineBreakMode = .byTruncatingTail
    scope.font = .systemFont(ofSize:10);scope.textColor=StudioTheme.muted;scope.lineBreakMode = .byTruncatingMiddle
    let text=NSStackView(views:[name,scope]);text.orientation = .vertical;text.alignment = .leading;text.spacing=3
    let stack=NSStackView(views:[image,text]);stack.spacing=10
    cell.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:10),stack.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),stack.centerYAnchor.constraint(equalTo:cell.centerYAnchor),image.widthAnchor.constraint(equalToConstant:18)])
    cell.textField=name;cell.imageView=image;cell.toolTip=value.name+" · "+scopeText(value)
    cell.setAccessibilityLabel(cell.toolTip);return cell
  }
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {StudioRowView()}
  func tableViewSelectionDidChange(_ notification:Notification) {updatePreview()}
  private func scopeText(_ value:FavoriteQuery)->String {value.scope == .global ? "Genel · Tüm bağlantılar":value.scope == .connection ? "Explorer · Bu bağlantı":"Veritabanı · "+database}
  private func updatePreview() {
    let value=selectedFavorite
    titleLabel.stringValue=value?.name ?? "SQL önizlemesi";scopeLabel.stringValue=value.map(scopeText) ?? "Sorgu otomatik çalıştırılmaz."
    let source=value?.sql ?? "",prefix=source.prefix(64_000)
    if prefix.endIndex != source.endIndex {
      scopeLabel.stringValue += " · Önizleme: ilk 64.000 karakter"
      scopeLabel.toolTip="Önizleme ilk 64.000 karakteri gösterir. Sorguda Aç tam SQL metnini açar."
    } else {scopeLabel.toolTip=scopeLabel.stringValue}
    preview.rootView=SQLReadOnlyPreview(sql:String(prefix))
    openButton.isEnabled=value != nil && serverID != nil
  }
  func select(step:Int) {
    guard let next=FavoriteQuerySelection.next(visible,selected:selectedFavorite?.id,step:step),let index=visible.firstIndex(where:{$0.id == next}) else {return}
    table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false);table.scrollRowToVisible(index)
  }
  @objc private func searchChanged() {reloadItems()}
  @objc func insertSelected() {
    guard let favorite=selectedFavorite else {return}
    do {if let insert {try insert(favorite);view.window?.close()} else {openSelected()}} catch {message.stringValue=error.localizedDescription;message.isHidden=false}
  }
  @objc func openSelected() {
    guard let favorite=selectedFavorite,serverID != nil else {return}
    do {try open(favorite);view.window?.close()} catch {message.stringValue=error.localizedDescription;message.isHidden=false}
  }
  @objc private func manageFavorites() {manage()}
  @objc private func closePicker() {view.window?.close()}
  func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector)->Bool {
    if command == #selector(NSResponder.moveDown(_:)) {select(step:1);return true}
    if command == #selector(NSResponder.moveUp(_:)) {select(step:-1);return true}
    if command == #selector(NSResponder.insertNewline(_:)) {openSelected();return true}
    if command == #selector(NSResponder.cancelOperation(_:)) {closePicker();return true}
    return false
  }
  @objc private func refreshTheme() {
    guard isViewLoaded else {return}
    StudioTheme.surface(view,chrome:true);table.backgroundColor=StudioTheme.canvas
    scroll.layer?.borderColor=StudioTheme.border.cgColor;scopeLabel.textColor=StudioTheme.muted;count.textColor=StudioTheme.muted
    empty.textColor=StudioTheme.muted;message.textColor=StudioTheme.danger;openButton.refreshStyle();table.reloadData()
  }
}
@MainActor private final class FavoritePickerTable:NSTableView {
  var openSelected:(()->Void)?
  override func keyDown(with event:NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 {openSelected?();return}
    super.keyDown(with:event)
  }
}

struct FavoriteQueriesPanel:View {
  let state:StudioState
  @ObservedObject var model:FavoriteQueriesModel
  @State var contextServerID:UUID?
  @State var contextDatabase:String
  var didOpen:()->Void = {}
  var insert:((FavoriteQuery)throws->Void)?
  var editFavorite:((FavoriteQuery?,UUID?,String)->Void)?
  @State private var all=false
  @State private var search=""
  @State private var selected:UUID?
  @State private var deleting=false
  @State private var openError=""
  private var current:FavoriteQuery? {visible.first {$0.id == selected}}
  private var visible:[FavoriteQuery] {model.items.filter {(all || $0.visible(serverID:contextServerID,database:contextDatabase)) && (search.isEmpty || $0.name.localizedStandardContains(search))}}
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Favori Sorgular",icon:"star",subtitle:"Adlandır, kapsamını seç ve tekrar kullan")
      HStack {
        Picker("Explorer bağlantısı",selection:$contextServerID) {
          Text("Bağlantı seçin").tag(nil as UUID?)
          ForEach(state.servers) {Text($0.profile.name).tag(Optional($0.id))}
        }.frame(maxWidth:360)
        FavoriteDatabasePicker(servers:state.servers,serverID:contextServerID,selection:$contextDatabase)
      }.onChange(of:contextServerID) {_,id in contextDatabase=state.servers.first {$0.id == id}?.profile.database ?? ""}
      HStack {
        TextField("Favori adı ara",text:$search)
        Toggle("Bütün kapsamlar",isOn:$all).fixedSize()
        FavoriteNativeAction(title:"Yeni",icon:"plus",identifier:"favoriteNew",width:72) {editFavorite?(nil,contextServerID,contextDatabase)}
          .frame(width:72,height:30).disabled(editFavorite == nil)
      }
      HSplitView {
        List(visible,selection:$selected) {item in
          VStack(alignment:.leading,spacing:4) {
            Label(item.name,systemImage:item.scope == .global ? "globe":item.scope == .connection ? "server.rack":"externaldrive")
            Text(scopeLabel(item)).font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical,5).tag(item.id)
        }.contextMenu(forSelectionType:UUID.self) { _ in } primaryAction: { ids in
          if let id=ids.first,let item=visible.first(where:{$0.id == id}) {insertFavorite(item)}
        }.frame(minWidth:230,idealWidth:280,maxWidth:360).accessibilityIdentifier("favoriteList")
        VStack(alignment:.leading,spacing:12) {
          if let current {
            Text(current.name).font(.system(size:17,weight:.semibold))
            Text(scopeLabel(current)).foregroundStyle(.secondary)
            SQLReadOnlyPreview(sql:current.sql).frame(minHeight:200)
            Text("Açılacak hedef: "+targetLabel(current)).font(.caption).foregroundStyle(.secondary)
          } else {StudioEmptyState(title:"Bir favori seçin",icon:"star",detail:"Genel favoriler her bağlantıda, bağlantı ve veritabanı favorileri kendi kapsamlarında görünür.")}
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
      }
      if !model.error.isEmpty {Text(model.error).foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled)}
      if !openError.isEmpty {Text(openError).foregroundStyle(Color(nsColor:StudioTheme.danger))}
      HStack {
        FavoriteNativeAction(title:"Düzenle",icon:"pencil",identifier:"favoriteEdit",width:90) {if let current {editFavorite?(current,contextServerID,contextDatabase)}}
          .frame(width:90,height:30).disabled(current == nil || editFavorite == nil)
        StudioActionButton("Sil",icon:"trash",tint:Color(nsColor:StudioTheme.danger)) {deleting=true}.disabled(current == nil)
        Spacer()
        StudioActionButton("İmlece Ekle",icon:"text.insert") {if let current {insertFavorite(current)}}.disabled(current == nil || insert == nil)
        StudioActionButton("Sorguda Aç",icon:"arrow.up.right.square") {
          guard let current else {return}
          do {try state.openFavorite(current,contextServerID:contextServerID,contextDatabase:targetDatabase(current));openError="";didOpen()}
          catch {openError=error.localizedDescription}
        }.buttonStyle(StudioPrimaryButton()).disabled(current == nil).accessibilityIdentifier("favoriteOpen")
      }
      Text("Çift tıklama mevcut editörde imlece ekler. Sorguda Aç yeni bir sekme açar; SQL otomatik çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
    }.padding(20).studioPanel().task {await model.load()}
      .confirmationDialog("Seçili favori silinsin mi?",isPresented:$deleting,titleVisibility:.visible) {
        Button("Favoriyi Sil",role:.destructive) {if let current {Task {await model.remove(current.id);selected=nil}}}
        Button("Vazgeç",role:.cancel) {}
      }
  }
  private func insertFavorite(_ favorite:FavoriteQuery) {
    do {try insert?(favorite);openError=""} catch {openError=error.localizedDescription}
  }
  private func scopeLabel(_ favorite:FavoriteQuery) -> String {
    guard favorite.scope != .global else {return "Genel · Tüm bağlantılar"}
    let server=state.servers.first {$0.id == favorite.serverID}?.profile.name ?? "Explorer’da bulunmayan bağlantı"
    return favorite.scope == .connection ? "Bağlantı · "+server:"Veritabanı · "+server+" / "+(favorite.database ?? "")
  }
  private func targetDatabase(_ favorite:FavoriteQuery) -> String {
    if favorite.scope == .database {return favorite.database ?? ""}
    if favorite.scope == .global || favorite.serverID == contextServerID {return contextDatabase}
    return state.servers.first {$0.id == favorite.serverID}?.profile.database ?? ""
  }
  private func targetLabel(_ favorite:FavoriteQuery) -> String {
    let id=favorite.scope == .global ? contextServerID:favorite.serverID
    return (state.servers.first {$0.id == id}?.profile.name ?? "Bağlantı seçilmedi")+" / "+targetDatabase(favorite)
  }
}

/// Keep favorite actions on explicit AppKit targets shared by the management and editor windows.
struct FavoriteNativeAction:NSViewRepresentable {
  let title:String
  let icon:String
  let identifier:String
  let width:CGFloat
  var primary=false
  let action:()->Void
  @Environment(\.isEnabled) private var enabled
  @MainActor final class Coordinator:NSObject {
    var action:()->Void
    init(action:@escaping ()->Void) {self.action=action}
    @objc func performAction() {action()}
  }
  func makeCoordinator()->Coordinator {Coordinator(action:action)}
  func makeNSView(context:Context)->StudioToolbarButton {
    let button=StudioToolbarButton(symbol:icon,label:title,tone:primary ? .accent:.neutral,title:title,width:width,prominent:primary)
    button.target=context.coordinator;button.action = #selector(Coordinator.performAction)
    button.setAccessibilityIdentifier(identifier);button.isEnabled=enabled
    return button
  }
  func updateNSView(_ button:StudioToolbarButton,context:Context) {
    context.coordinator.action=action;button.isEnabled=enabled;button.refreshStyle()
  }
}

@MainActor final class FavoriteEditorWindowTarget {
  weak var window:NSWindow?
  func close() {window?.close()}
}

@MainActor final class FavoriteQuerySubmission:ObservableObject {
  @Published private(set) var saving=false
  @Published private(set) var error=""
  private let persist:(FavoriteQuery)async throws->Void
  init(persist:@escaping (FavoriteQuery)async throws->Void) {self.persist=persist}
  func report(_ error:String) {self.error=error}
  func save(_ value:FavoriteQuery,close:@escaping ()->Void) {
    guard !saving else {return}
    saving=true;error=""
    Task {
      do {
        try await persist(value)
        saving=false
        close()
      } catch {
        self.error=error.localizedDescription
        saving=false
      }
    }
  }
}

struct FavoriteQueryEditor:View {
  let servers:[ConnectedServer]
  let close:()->Void
  private let id:UUID
  @State private var name:String
  @State private var sql:String
  @State private var scope:FavoriteQuery.Scope
  @State private var serverID:UUID?
  @State private var database:String
  @StateObject private var submission:FavoriteQuerySubmission
  init(model:FavoriteQueriesModel,servers:[ConnectedServer],contextServerID:UUID?,database:String,favorite:FavoriteQuery?=nil,sql:String="",name:String="",close:@escaping ()->Void) {
    self.servers=servers;self.close=close;id=favorite?.id ?? UUID()
    _submission=StateObject(wrappedValue:FavoriteQuerySubmission {try await model.save($0)})
    _name=State(initialValue:favorite?.name ?? name);_sql=State(initialValue:favorite?.sql ?? sql)
    _scope=State(initialValue:favorite?.scope ?? (contextServerID == nil ? .global:database.isEmpty ? .connection:.database))
    _serverID=State(initialValue:favorite?.serverID ?? contextServerID);_database=State(initialValue:favorite?.database ?? database)
  }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Favori Sorgu",icon:"star",subtitle:"SQL’e bir ad ve kullanım kapsamı ver")
      StudioFormField("Ad") {TextField("Örneğin günlük satış özeti",text:$name).accessibilityIdentifier("favoriteName")}
      StudioFormField("Kapsam") {Picker("Kapsam",selection:$scope) {Text("Genel").tag(FavoriteQuery.Scope.global);Text("Explorer bağlantısı").tag(FavoriteQuery.Scope.connection);Text("Veritabanı").tag(FavoriteQuery.Scope.database)}.labelsHidden()}
      if scope != .global {
        StudioFormField("Explorer bağlantısı") {Picker("Explorer bağlantısı",selection:$serverID) {
          Text("Bağlantı seçin").tag(nil as UUID?)
          if let serverID,!servers.contains(where:{$0.id == serverID}) {Text("Explorer’da bulunmayan bağlantı").tag(Optional(serverID))}
          ForEach(servers) {Text($0.profile.name).tag(Optional($0.id))}
        }.labelsHidden()}
      }
      if scope == .database {FavoriteDatabasePicker(servers:servers,serverID:serverID,selection:$database)}
      Text("SQL").fontWeight(.semibold)
      AgentCommandEditor(text:$sql).studioEditor().frame(minHeight:220)
      if !submission.error.isEmpty {Text(submission.error).foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled).accessibilityIdentifier("favoriteSaveError")}
      HStack {
        StudioActionButton("Vazgeç",icon:"xmark") {close()}.disabled(submission.saving)
        Spacer()
        if submission.saving {
          ProgressView().controlSize(.small)
          Text("Favori kaydediliyor…").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("favoriteSaveProgress")
        }
        FavoriteNativeAction(title:"Favoriyi Kaydet",icon:"star.fill",identifier:"favoriteSave",width:154,primary:true) {
          do {
            let value=try FavoriteQuery(id:id,name:name,sql:sql,scope:scope,serverID:serverID,database:database)
            submission.save(value,close:close)
          } catch {submission.report(error.localizedDescription)}
        }.frame(width:154,height:30).disabled(submission.saving)
      }
    }.padding(20).frame(width:720,height:660).studioPanel()
      .onChange(of:serverID) {_,id in database=servers.first {$0.id == id}?.profile.database ?? ""}
  }
}

@MainActor final class FavoriteDatabaseChoices:ObservableObject {
  @Published private(set) var names:[String]=[]
  @Published private(set) var loading=false
  @Published private(set) var message=""
  private var generation=UUID()
  func load(server:ConnectedServer?) async {
    let token=UUID();generation=token
    names=Array(Set(server?.databases.map(\.name) ?? [])).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
    message="";loading=false
    guard let server else {return}
    guard server.online || server.catalogFixture != nil else {message="Çevrimdışı · Son yüklenen veritabanları";return}
    loading=true
    defer {if generation == token {loading=false}}
    do {
      var limits=Limits();limits.rows=5000;limits.totalBytes=8*1024*1024;limits.timeout=15
      let output=try await server.catalog(Catalog.databases,database:"master",limits:limits)
      try Task.checkCancellation()
      guard generation == token else {return}
      names=Array(Set(Catalog.rows(output).map(\.name))).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
      if output.partial {message="Liste kısmi; mevcut seçim korunuyor."}
      else if names.isEmpty {message="Erişilebilir veritabanı bulunamadı; mevcut seçim korunuyor."}
    } catch is CancellationError {} catch {
      guard generation == token else {return}
      message="Veritabanları yüklenemedi: "+error.localizedDescription
    }
  }
}
struct FavoriteDatabasePicker:View {
  let servers:[ConnectedServer]
  let serverID:UUID?
  @Binding var selection:String
  @StateObject private var choices=FavoriteDatabaseChoices()
  @State private var revision=0
  private var server:ConnectedServer? {servers.first {$0.id == serverID}}
  var body:some View {
    VStack(alignment:.leading,spacing:5) {
      HStack {
        StudioFormField("Veritabanı") {
          StudioSearchablePicker(title:"Veritabanı",values:choices.names,selection:$selection).accessibilityIdentifier("favoriteDatabase")
        }.disabled(server == nil || choices.loading)
        if choices.loading {ProgressView().controlSize(.small).accessibilityLabel("Veritabanları yükleniyor")}
        Button {revision+=1} label:{Image(systemName:"arrow.clockwise")}
          .disabled(choices.loading || server == nil || !(server?.online == true || server?.catalogFixture != nil))
          .studioHelp("Veritabanlarını yenile").accessibilityLabel("Veritabanlarını yenile")
      }
      if !choices.message.isEmpty {Text(choices.message).font(.caption).foregroundStyle(.secondary).lineLimit(2).studioHelp(choices.message)}
    }.task(id:"\(serverID?.uuidString ?? "none")|\(server?.generation.uuidString ?? "")|\(revision)") {await choices.load(server:server)}
  }
}
