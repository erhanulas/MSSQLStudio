import AppKit
import SQLServerKit
import SwiftUI

@MainActor enum GridShortcuts {
  enum Action:String,CaseIterable {
    case runStatement
    case completion
    case pinTab
    case closeLeft
    case closeRight
    case gridAdd
    case gridClone
    case gridDelete
    case gridRevert
    case gridFilter
    case gridFit
    case gridPin
    case gridHide
    case gridUnpin

    case history, reopenTab, format, headers, newQuery, favorites
    case columns, matchingPair, parameterInfo, undo, redo, comment
    case uncomment, connections, settings, checkUpdates, about, openFile
    case saveFile, saveAs, closeWindow, execute, cancelQuery, reconnectQuery
    case estimatedPlan, actualPlan, beginTransaction, commitTransaction, rollbackTransaction, explorer
    case results, activity, ai, extensions, detach, redock
    case exportExplorer, importExplorer, manageFavorites, addFavorite, definition, revealExplorer
    case fold, unfoldAll, closeOthers, closeAll, copyName, refreshObject
    case editConnection, contextCreateExplorerGroup, contextRenameExplorerGroup, contextRemoveExplorerGroup, contextDeleteExplorerConnection, contextShowFavoritesAtNode
    case contextRefreshContextParent, contextShowOfflineDefinitionAtContext, contextDisconnectServer, contextCloseExplorerConnection, contextCompareDatabasesAtNode, contextDesignTableObject
    case contextEditObjectData, contextDesignViewObject, contextModifyManagedModule, contextSelectRows, contextManageObjectIndexes, contextManageObjectRelationships
    case contextManageObjectChecks, contextObjectDependencies, contextRenameManagedObject, contextDeleteManagedObject, contextManagedObjectProperties, contextEditManagedSynonym
    case contextManageChildStructure, contextRebuildManagedIndex, contextReorganizeManagedIndex, contextDisableManagedIndex, contextCheckManagedConstraint, contextDisableManagedConstraint
    case contextObjectProperties, contextNewManagedTable, contextNewManagedView, contextNewManagedProcedure, contextNewManagedScalarFunction, contextNewManagedTableFunction
    case contextNewManagedTrigger, contextNewManagedSynonym, contextOpenActivityTable, contextDatabaseProperties, contextJobDesigner
  }
  static func title(_ action:Action)->String {
    switch action {
    case .history: return "History · Sorgu ve sekme geçmişi"
    case .reopenTab: return "Kapatılan sekmeyi aç"
    case .format: return "Editör · SQL Formatla"
    case .headers: return "Grid · Başlıklarla kopyala"
    case .newQuery: return "Yeni sorgu"
    case .favorites: return "Favori sorgu seçici"
    case .columns: return "Grid · Kolon başlığında ara"
    case .matchingPair: return "Editör · Eşleşen ayırıcıya git"
    case .parameterInfo: return "Editör · Parametre bilgisi"
    case .undo: return "Editör · Geri al"
    case .redo: return "Editör · İleri al"
    case .comment: return "Editör · Yorum yap / kaldır"
    case .uncomment: return "Editör · Yorumu kaldır"
    default: return StudioCommandCatalog.definitions[action]?.title ?? action.rawValue
    }
  }
  struct Binding: Codable, Equatable, Sendable {
    var key: String
    var modifiers: UInt
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var label: String {
      (key.isEmpty ? "Atanmamış" : "") + (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
        + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (key == "\r" ? "↩":key == " " ? "␣":key.uppercased())
    }
  }
  static let changed = Notification.Name("MSSQLStudio.gridShortcutsChanged")
  static func binding(_ action: Action) -> Binding {
    if let data = UserDefaults.standard.data(forKey: "shortcut.\(action.rawValue)"), let binding = try? JSONDecoder().decode(Binding.self, from: data) { return binding }
    if action == .history {return Binding(key:"h",modifiers:NSEvent.ModifierFlags([.command,.option]).rawValue)}
    if action == .reopenTab {return Binding(key:"t",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)}
    if action == .format {return Binding(key:"f",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)}
    if action == .undo {return Binding(key:"z",modifiers:NSEvent.ModifierFlags.control.rawValue)}
    if action == .redo {return Binding(key:"y",modifiers:NSEvent.ModifierFlags.control.rawValue)}
    if action == .comment {return Binding(key:"/",modifiers:NSEvent.ModifierFlags.command.rawValue)}
    if action == .uncomment {return Binding(key:"/",modifiers:NSEvent.ModifierFlags([.command,.option]).rawValue)}
    if action == .matchingPair {return Binding(key:"m",modifiers:NSEvent.ModifierFlags([.control,.shift]).rawValue)}
    if action == .parameterInfo {return Binding(key:"p",modifiers:NSEvent.ModifierFlags.control.rawValue)}
    if action == .favorites {return Binding(key:"p",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue)}
    if action == .columns { return Binding(key:"j",modifiers:NSEvent.ModifierFlags([.command,.shift]).rawValue) }
    if action == .newQuery { return Binding(key: "n", modifiers: NSEvent.ModifierFlags.command.rawValue) }
    if action == .headers {return Binding(key:"c",modifiers:headersModifiers.rawValue)}
    return StudioCommandCatalog.definitions[action]?.defaultBinding ?? Binding(key:"",modifiers:0)
  }
  static var headersModifiers: NSEvent.ModifierFlags {
    if let data = UserDefaults.standard.data(forKey: "shortcut.headers"), let binding = try? JSONDecoder().decode(Binding.self, from: data) { return binding.flags }
    return UserDefaults.standard.string(forKey: "gridCopyHeadersShortcut") == "option" ? [.command,.option] : [.command,.shift]
  }
  static var headersLabel: String { binding(.headers).label }
  static func matches(_ action: Action, _ event: NSEvent) -> Bool {
    let binding = binding(action)
    let key=event.charactersIgnoringModifiers?.lowercased()
    var flags=event.modifierFlags.intersection([.command,.shift,.option,.control]),expected=binding.flags
    // Turkish / is Shift+7. Shift used to produce the symbol is part of the glyph.
    if key == "/",binding.key == "/" {flags.remove(.shift);expected.remove(.shift)}
    return !binding.key.isEmpty && key == binding.key && flags == expected
  }
  static func matchesHeaders(_ event: NSEvent) -> Bool {
    matches(.headers,event)
  }
  static func save(_ event: NSEvent, action: Action) -> String? {
    var flags = event.modifierFlags.intersection([.command,.shift,.option,.control])
    guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1,
      ["/",",",".","[","]","\r"," "].contains(key) || key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }), flags.contains(.command) || flags.contains(.control)
    else { return "⌘ veya ⌃ ile harf, rakam, / , . [ ], Space veya Enter kullanın. Escape iptal eder." }
    if key == "/" {flags.remove(.shift)}
    // Existing application and standard editing commands remain reserved.
    let reserved: [(String,NSEvent.ModifierFlags)] = [("\r",.command),(" ",.control),("b",.command),(".",.command),(",",.command),("[",[.command,.option]),("]",[.command,.option]),("q",.command),("w",.command),("s",.command),("s",[.command,.shift]),("o",.command),("c",.command),("v",.command),("x",.command),("a",.command),("z",.command),("z",[.command,.shift]),("f",.command),("f",.control),("r",.command),("m",.command),("l",.command),("b",[.command,.option])]
    let historyOwner:Action? = key == "z" && (flags == .command || flags == .control) ? .undo
      : (key == "z" && (flags == [.command,.shift] || flags == [.control,.shift])) || (key == "y" && flags == .control) ? .redo : nil
    guard historyOwner == nil || historyOwner == action,
      historyOwner == action || StudioCommandCatalog.definitions[action]?.defaultBinding == Binding(key:key,modifiers:flags.rawValue) || !reserved.contains(where: { $0.0 == key && $0.1 == flags })
    else { return "Bu tuş uygulamanın başka bir işlemi için ayrılmış." }
    let value = Binding(key: key, modifiers: flags.rawValue)
    guard !Action.allCases.filter({ $0 != action }).contains(where: { binding($0) == value }) else { return "Bu kısayol diğer işlemde kullanılıyor." }
    if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "shortcut.\(action.rawValue)") }
    NotificationCenter.default.post(name: changed, object: nil)
    return nil
  }
  static func clear(_ action:Action) {
    if let data=try? JSONEncoder().encode(Binding(key:"",modifiers:0)) {UserDefaults.standard.set(data,forKey:"shortcut."+action.rawValue)}
    NotificationCenter.default.post(name:changed,object:nil)
  }
  static func reset(_ action: Action) {
    UserDefaults.standard.removeObject(forKey: "shortcut.\(action.rawValue)")
    if action == .headers { UserDefaults.standard.removeObject(forKey: "gridCopyHeadersShortcut") }
    NotificationCenter.default.post(name: changed, object: nil)
  }
}
