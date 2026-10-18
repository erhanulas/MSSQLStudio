import AppKit

@MainActor enum StudioCommandCatalog {
  struct Definition {let title:String;let selector:String;let defaultBinding:GridShortcuts.Binding}
  static let definitions:[GridShortcuts.Action:Definition]=[
    .tabSwitcher:.init(title:"Açık sekmeler · Önizlemeli geçiş",selector:"showTabSwitcher",defaultBinding:.init(key:"\t",modifiers:NSEvent.ModifierFlags.option.rawValue)),
    .connections:.init(title:"Bağlantıları yönet",selector:"showConnect",defaultBinding:.init(key:"",modifiers:0)),
    .settings:.init(title:"Ayarlar",selector:"settings",defaultBinding:.init(key:",",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .checkUpdates:.init(title:"Güncellemeleri kontrol et",selector:"installUpdate",defaultBinding:.init(key:"",modifiers:0)),
    .about:.init(title:"Hakkında",selector:"about",defaultBinding:.init(key:"",modifiers:0)),
    .openFile:.init(title:"SQL dosyası aç",selector:"openSQL",defaultBinding:.init(key:"o",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .saveFile:.init(title:"Kaydet",selector:"saveSQL",defaultBinding:.init(key:"s",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .saveAs:.init(title:"Farklı kaydet",selector:"saveAsSQL",defaultBinding:.init(key:"s",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)),
    .closeWindow:.init(title:"Öndeki pencereyi / sekmeyi kapat",selector:"closeFocusedWindow",defaultBinding:.init(key:"w",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .execute:.init(title:"SQL çalıştır",selector:"execute",defaultBinding:.init(key:"r",modifiers:NSEvent.ModifierFlags.control.rawValue)),
    .cancelQuery:.init(title:"Sorguyu iptal et",selector:"cancel",defaultBinding:.init(key:".",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .reconnectQuery:.init(title:"Sorgu oturumunu yeniden bağla",selector:"reconnectQuery",defaultBinding:.init(key:"",modifiers:0)),
    .estimatedPlan:.init(title:"Tahmini plan",selector:"estimatedPlan",defaultBinding:.init(key:"l",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .actualPlan:.init(title:"Gerçek planı dahil et",selector:"toggleActualPlan",defaultBinding:.init(key:"m",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .beginTransaction:.init(title:"Transaction başlat",selector:"beginTransaction",defaultBinding:.init(key:"",modifiers:0)),
    .commitTransaction:.init(title:"Commit",selector:"commitTransaction",defaultBinding:.init(key:"",modifiers:0)),
    .rollbackTransaction:.init(title:"Rollback",selector:"rollbackTransaction",defaultBinding:.init(key:"",modifiers:0)),
    .explorer:.init(title:"Explorer göster / gizle",selector:"toggleExplorer",defaultBinding:.init(key:"b",modifiers:NSEvent.ModifierFlags([.command,.option]).rawValue)),
    .results:.init(title:"Sonuçları göster / gizle",selector:"toggleResults",defaultBinding:.init(key:"r",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .profiler:.init(title:"SQL Profiler",selector:"profiler",defaultBinding:.init(key:"",modifiers:0)),
    .activity:.init(title:"Activity Monitor",selector:"activity",defaultBinding:.init(key:"",modifiers:0)),
    .ai:.init(title:"AI Assistant",selector:"aiAssistant",defaultBinding:.init(key:"",modifiers:0)),
    .extensions:.init(title:"Extensions",selector:"extensionsPanel",defaultBinding:.init(key:"",modifiers:0)),
    .detach:.init(title:"Sorguyu ayrı pencereye taşı",selector:"detachQuery",defaultBinding:.init(key:"",modifiers:0)),
    .redock:.init(title:"Sorguları çalışma alanına yerleştir",selector:"redockQueries",defaultBinding:.init(key:"",modifiers:0)),
    .exportExplorer:.init(title:"Explorer dışa aktar",selector:"exportExplorer",defaultBinding:.init(key:"",modifiers:0)),
    .importExplorer:.init(title:"Explorer içe aktar",selector:"importExplorer",defaultBinding:.init(key:"",modifiers:0)),
    .manageFavorites:.init(title:"Favorileri yönet",selector:"manageFavorites",defaultBinding:.init(key:"",modifiers:0)),
    .addFavorite:.init(title:"Favorilere ekle",selector:"addFavorite",defaultBinding:.init(key:"",modifiers:0)),
    .definition:.init(title:"Editör · Nesne tanımına git",selector:"goToDefinition:",defaultBinding:.init(key:"b",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .revealExplorer:.init(title:"Editör · Explorer’da git",selector:"revealExplorerObject:",defaultBinding:.init(key:"",modifiers:0)),
    .fold:.init(title:"Editör · Bloğu daralt / aç",selector:"toggleCodeOutline:",defaultBinding:.init(key:"[",modifiers:NSEvent.ModifierFlags([.command,.option]).rawValue)),
    .unfoldAll:.init(title:"Editör · Tüm blokları aç",selector:"expandCodeOutline:",defaultBinding:.init(key:"]",modifiers:NSEvent.ModifierFlags([.command,.option]).rawValue)),
    .closeOthers:.init(title:"Diğer sorgu sekmelerini kapat",selector:"closeOtherTabs",defaultBinding:.init(key:"",modifiers:0)),
    .closeAll:.init(title:"Tüm sorgu sekmelerini kapat",selector:"closeAllTabs",defaultBinding:.init(key:"",modifiers:0)),
    .copyName:.init(title:"Explorer · Adı kopyala",selector:"copyNodeName",defaultBinding:.init(key:"",modifiers:0)),
    .refreshObject:.init(title:"Explorer · Yenile",selector:"refreshContextNode",defaultBinding:.init(key:"",modifiers:0)),
    .editConnection:.init(title:"Explorer · Bağlantı ayarları",selector:"editConnection",defaultBinding:.init(key:"",modifiers:0)),
    .contextCreateExplorerGroup:.init(title:"Yeni Klasör…",selector:"createExplorerGroup:",defaultBinding:.init(key:"",modifiers:0)),
    .contextRenameExplorerGroup:.init(title:"Klasörü Yeniden Adlandır…",selector:"renameExplorerGroup",defaultBinding:.init(key:"",modifiers:0)),
    .contextRemoveExplorerGroup:.init(title:"Klasörü Kaldır…",selector:"removeExplorerGroup",defaultBinding:.init(key:"",modifiers:0)),
    .contextDeleteExplorerConnection:.init(title:"Kayıtlı Bağlantıyı Sil…",selector:"deleteExplorerConnection",defaultBinding:.init(key:"",modifiers:0)),
    .contextShowFavoritesAtNode:.init(title:"Favori Sorguları Yönet…",selector:"showFavoritesAtNode",defaultBinding:.init(key:"",modifiers:0)),
    .contextRefreshContextParent:.init(title:"Yüklemeyi Tekrar Dene",selector:"refreshContextParent",defaultBinding:.init(key:"",modifiers:0)),
    .contextShowOfflineDefinitionAtContext:.init(title:"İndekslenmiş Tanımı Gör…",selector:"showOfflineDefinitionAtContext",defaultBinding:.init(key:"",modifiers:0)),
    .contextDisconnectServer:.init(title:"Explorer’dan Kaldır…",selector:"disconnectServer",defaultBinding:.init(key:"",modifiers:0)),
    .contextCloseExplorerConnection:.init(title:"Aktif Bağlantıyı Kapat",selector:"closeExplorerConnection:",defaultBinding:.init(key:"",modifiers:0)),
    .contextCompareDatabasesAtNode:.init(title:"DDL Karşılaştır…",selector:"compareDatabasesAtNode",defaultBinding:.init(key:"",modifiers:0)),
    .contextDesignTableObject:.init(title:"Design…",selector:"designTableObject",defaultBinding:.init(key:"",modifiers:0)),
    .contextEditObjectData:.init(title:"Edit Top 200 Rows…",selector:"editObjectData",defaultBinding:.init(key:"",modifiers:0)),
    .contextDesignViewObject:.init(title:"Design…",selector:"designViewObject",defaultBinding:.init(key:"",modifiers:0)),
    .contextModifyManagedModule:.init(title:"Modify · ALTER…",selector:"modifyManagedModule",defaultBinding:.init(key:"",modifiers:0)),
    .contextSelectRows:.init(title:"Select Top 1000 Rows",selector:"selectRows",defaultBinding:.init(key:"",modifiers:0)),
    .contextManageObjectIndexes:.init(title:"Indexes / Keys…",selector:"manageObjectIndexes",defaultBinding:.init(key:"",modifiers:0)),
    .contextManageObjectRelationships:.init(title:"Relationships…",selector:"manageObjectRelationships",defaultBinding:.init(key:"",modifiers:0)),
    .contextManageObjectChecks:.init(title:"Check Constraints…",selector:"manageObjectChecks",defaultBinding:.init(key:"",modifiers:0)),
    .contextObjectDependencies:.init(title:"View Dependencies",selector:"objectDependencies",defaultBinding:.init(key:"",modifiers:0)),
    .contextRenameManagedObject:.init(title:"Rename…",selector:"renameManagedObject",defaultBinding:.init(key:"",modifiers:0)),
    .contextDeleteManagedObject:.init(title:"Delete…",selector:"deleteManagedObject",defaultBinding:.init(key:"",modifiers:0)),
    .contextManagedObjectProperties:.init(title:"Properties…",selector:"managedObjectProperties",defaultBinding:.init(key:"",modifiers:0)),
    .contextEditManagedSynonym:.init(title:"Modify / Re-create…",selector:"editManagedSynonym",defaultBinding:.init(key:"",modifiers:0)),
    .contextManageChildStructure:.init(title:"Modify / Properties…",selector:"manageChildStructure",defaultBinding:.init(key:"",modifiers:0)),
    .contextRebuildManagedIndex:.init(title:"Rebuild…",selector:"rebuildManagedIndex",defaultBinding:.init(key:"",modifiers:0)),
    .contextReorganizeManagedIndex:.init(title:"Reorganize…",selector:"reorganizeManagedIndex",defaultBinding:.init(key:"",modifiers:0)),
    .contextDisableManagedIndex:.init(title:"Disable…",selector:"disableManagedIndex",defaultBinding:.init(key:"",modifiers:0)),
    .contextCheckManagedConstraint:.init(title:"Enable / Check…",selector:"checkManagedConstraint",defaultBinding:.init(key:"",modifiers:0)),
    .contextDisableManagedConstraint:.init(title:"Disable / NOCHECK…",selector:"disableManagedConstraint",defaultBinding:.init(key:"",modifiers:0)),
    .contextObjectProperties:.init(title:"Properties…",selector:"objectProperties",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedTable:.init(title:"New Table…",selector:"newManagedTable",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedView:.init(title:"New View…",selector:"newManagedView",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedProcedure:.init(title:"New Stored Procedure…",selector:"newManagedProcedure",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedScalarFunction:.init(title:"New Scalar Function…",selector:"newManagedScalarFunction",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedTableFunction:.init(title:"New Inline Table-valued Function…",selector:"newManagedTableFunction",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedTrigger:.init(title:"New Trigger…",selector:"newManagedTrigger",defaultBinding:.init(key:"",modifiers:0)),
    .contextNewManagedSynonym:.init(title:"New Synonym…",selector:"newManagedSynonym",defaultBinding:.init(key:"",modifiers:0)),
    .contextOpenActivityTable:.init(title:"Sorguda Tablo Olarak İzle",selector:"openActivityTable",defaultBinding:.init(key:"",modifiers:0)),
    .contextDatabaseProperties:.init(title:"Veritabanı bilgileri…",selector:"databaseProperties",defaultBinding:.init(key:"",modifiers:0)),
    .contextJobDesigner:.init(title:"New SQL Agent Job…",selector:"jobDesigner",defaultBinding:.init(key:"",modifiers:0)),
    .runStatement:.init(title:"Editör · İfade / blok çalıştır",selector:"runSQLStatement:",defaultBinding:.init(key:"\r",modifiers:NSEvent.ModifierFlags([.command]).rawValue)),
    .completion:.init(title:"Editör · Tamamlamayı göster",selector:"showSQLCompletion:",defaultBinding:.init(key:" ",modifiers:NSEvent.ModifierFlags([.control]).rawValue)),
    .pinTab:.init(title:"Sorgu sekmesini sabitle / kaldır",selector:"pinActiveTab",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .closeLeft:.init(title:"Soldaki sorgu sekmelerini kapat",selector:"closeLeftTabs",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .closeRight:.init(title:"Sağdaki sorgu sekmelerini kapat",selector:"closeRightTabs",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridCopyQuery:.init(title:"Grid · Bu değerlerle sorgu kopyala",selector:"copyQueryWithValues",defaultBinding:.init(key:"",modifiers:0)),
    .gridAdd:.init(title:"Grid · Yeni satır",selector:"addResultRow",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridClone:.init(title:"Grid · Satırı çoğalt",selector:"cloneResultRow",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridDelete:.init(title:"Grid · Satırı sil / geri al",selector:"deleteResultRow",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridRevert:.init(title:"Grid · Seçili düzenlemeleri geri al",selector:"revertResultRows",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridFilter:.init(title:"Grid · Seçili kolon filtresi",selector:"filterColumnMenu:",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridFit:.init(title:"Grid · Seçili kolonu içeriğe sığdır",selector:"fitColumn:",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridPin:.init(title:"Grid · Seçili kolonu sabitle / kaldır",selector:"togglePinnedColumn:",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridHide:.init(title:"Grid · Seçili kolonu gizle",selector:"toggleColumn:",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
    .gridUnpin:.init(title:"Grid · Tüm sabitlemeleri kaldır",selector:"unpinAllColumns",defaultBinding:.init(key:"",modifiers:NSEvent.ModifierFlags([]).rawValue)),
  ]
  static func action(for selector:Selector?)->GridShortcuts.Action? {
    guard let selector else {return nil}
    let name=NSStringFromSelector(selector)
    if name != "tabMenuAction:",let action=definitions.first(where:{$0.value.selector==name})?.key {return action}
    return ["newQuery":.newQuery,"newQueryAtNode":.newQuery,"showHistory":.history,"reopenLastClosedTab":.reopenTab,"showFavorites":.favorites,"formatSQL":.format,"formatSQLText:":.format,"toggleSQLComment:":.comment,"uncommentSQL:":.uncomment,"goToMatchingPair:":.matchingPair,"showParameterInfo:":.parameterInfo,"copyWithHeaders":.headers,"undoSQL:":.undo,"redoSQL:":.redo][name]
  }
  static func action(for item:NSMenuItem)->GridShortcuts.Action? {
    if item.action == Selector(("tabMenuAction:")) {return [0:GridShortcuts.Action.pinTab,1:.closeWindow,2:.closeRight,3:.closeLeft,4:.closeOthers,5:.closeAll][item.tag]}
    return action(for:item.action)
  }
  nonisolated static func decorate(_ item:NSMenuItem) {
    let selector=item.action,tag=item.tag
    let binding=MainActor.assumeIsolated {() -> GridShortcuts.Binding? in
      let action:GridShortcuts.Action? = selector == Selector(("tabMenuAction:")) ? [0:GridShortcuts.Action.pinTab,1:.closeWindow,2:.closeRight,3:.closeLeft,4:.closeOthers,5:.closeAll][tag]:action(for:selector)
      return action.map {GridShortcuts.binding($0)}
    }
    if let binding {
      item.allowsAutomaticKeyEquivalentLocalization=false
      item.allowsAutomaticKeyEquivalentMirroring=false
      item.keyEquivalent=binding.key;item.keyEquivalentModifierMask=binding.flags
    }
  }
  static func help(_ title:String,selector:Selector?)->String {
    guard let action=action(for:selector) else {return title}
    return help(title,action:action)
  }
  static func help(_ title:String,action:GridShortcuts.Action)->String {
    let binding=GridShortcuts.binding(action)
    return binding.key.isEmpty ? title:title+"  ·  "+binding.label
  }
  static func dispatch(_ event:NSEvent,to target:NSResponder,allowForwardedTarget:Bool=true,menu:()->NSMenu?)->Bool {
    guard !event.modifierFlags.intersection([.command,.control]).isEmpty else {return false}
    guard let action=definitions.keys.first(where:{GridShortcuts.matches($0,event)}),let selector=definitions[action]?.selector else {return false}
    guard allowForwardedTarget || target.responds(to:Selector((selector))) else {return false}
    func find(_ menu:NSMenu)->[NSMenuItem] {
      menu.items.flatMap {item in
        (Self.action(for:item)==action ? [item]:[]) + (item.submenu.map(find) ?? [])
      }
    }
    guard let menu=menu() else {return false}
    let matches=find(menu)
    guard matches.count==1,let item=matches.first,item.isEnabled else {return false}
    let receiver=item.target ?? target
    if let validated=receiver as? any NSUserInterfaceValidations,!validated.validateUserInterfaceItem(item) {return false}
    return NSApp.sendAction(item.action ?? Selector((selector)),to:receiver,from:item)
  }
}
