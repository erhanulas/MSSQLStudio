import Foundation

@MainActor enum ShortcutCatalog {
  enum Category:String,CaseIterable,Identifiable {
    case workspace, editor, execution, results, explorer, objects, application
    var id:String {rawValue}
    var title:String {
      switch self {
      case .workspace: "Sekmeler ve dosyalar"
      case .editor: "SQL editörü"
      case .execution: "Sorgu çalıştırma"
      case .results: "Sonuç tablosu"
      case .explorer: "Explorer ve bağlantılar"
      case .objects: "Veritabanı nesneleri"
      case .application: "Uygulama ve araçlar"
      }
    }
    var icon:String {
      switch self {
      case .workspace: "square.stack"
      case .editor: "curlybraces"
      case .execution: "play"
      case .results: "tablecells"
      case .explorer: "sidebar.left"
      case .objects: "externaldrive"
      case .application: "slider.horizontal.3"
      }
    }
  }
  enum Assignment:String,CaseIterable {
    case all, assigned, unassigned
    var title:String {
      switch self {case .all: "Tüm atamalar";case .assigned: "Atanmış";case .unassigned: "Atanmamış"}
    }
  }
  // Exhaustive: adding a command requires choosing its discoverable category.
  static func category(_ action:GridShortcuts.Action)->Category {
    switch action {
    case .pinTab,.closeLeft,.closeRight,.history,.reopenTab,.newQuery,.openFile,.saveFile,.saveAs,.closeWindow,.detach,.redock,.closeOthers,.closeAll: .workspace
    case .completion,.format,.matchingPair,.parameterInfo,.undo,.redo,.comment,.uncomment,.definition,.revealExplorer,.fold,.unfoldAll: .editor
    case .runStatement,.execute,.cancelQuery,.reconnectQuery,.estimatedPlan,.actualPlan,.beginTransaction,.commitTransaction,.rollbackTransaction: .execution
    case .gridAdd,.gridClone,.gridDelete,.gridRevert,.gridFilter,.gridFit,.gridPin,.gridHide,.gridUnpin,.headers,.columns,.results: .results
    case .connections,.explorer,.exportExplorer,.importExplorer,.copyName,.refreshObject,.editConnection,.contextCreateExplorerGroup,.contextRenameExplorerGroup,.contextRemoveExplorerGroup,.contextDeleteExplorerConnection,.contextRefreshContextParent,.contextDisconnectServer,.contextCloseExplorerConnection: .explorer
    case .contextShowOfflineDefinitionAtContext,.contextCompareDatabasesAtNode,.contextDesignTableObject,.contextEditObjectData,.contextDesignViewObject,.contextModifyManagedModule,.contextSelectRows,.contextManageObjectIndexes,.contextManageObjectRelationships,.contextManageObjectChecks,.contextObjectDependencies,.contextRenameManagedObject,.contextDeleteManagedObject,.contextManagedObjectProperties,.contextEditManagedSynonym,.contextManageChildStructure,.contextRebuildManagedIndex,.contextReorganizeManagedIndex,.contextDisableManagedIndex,.contextCheckManagedConstraint,.contextDisableManagedConstraint,.contextObjectProperties,.contextNewManagedTable,.contextNewManagedView,.contextNewManagedProcedure,.contextNewManagedScalarFunction,.contextNewManagedTableFunction,.contextNewManagedTrigger,.contextNewManagedSynonym,.contextDatabaseProperties: .objects
    case .favorites,.settings,.checkUpdates,.about,.activity,.profiler,.ai,.extensions,.manageFavorites,.addFavorite,.contextShowFavoritesAtNode,.contextOpenActivityTable,.contextJobDesigner: .application
    }
  }
  static func actions(category:Category,query:String="",assignment:Assignment = .all)->[GridShortcuts.Action] {
    func normalize(_ value:String)->String {value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"tr_TR")).replacingOccurrences(of:"ı",with:"i")}
    let words=normalize(query).split(whereSeparator:{$0.isWhitespace})
    return GridShortcuts.Action.allCases.filter {action in
      let binding=GridShortcuts.binding(action)
      guard assignment == .all || (assignment == .unassigned ? binding.key.isEmpty:!binding.key.isEmpty) else {return false}
      if words.isEmpty {return Self.category(action)==category}
      let text=normalize(GridShortcuts.title(action)+" "+Self.category(action).title+" "+binding.label)
      return words.allSatisfy {text.contains($0)}
    }.sorted {GridShortcuts.title($0).localizedStandardCompare(GridShortcuts.title($1)) == .orderedAscending}
  }
  static func target(_ id:String?)->GridShortcuts.Action? {
    guard let id,id.hasPrefix("shortcut.") else {return nil}
    return GridShortcuts.Action(rawValue:String(id.dropFirst(9)))
  }
}
