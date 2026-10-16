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
    case results, activity, profiler, ai, extensions, detach, redock
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
        + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (key == "\r" ? "↩":key == " " ? "␣":GridShortcuts.keyLabel(key))
    }
  }
  private static let functionKeyCodes: [UInt16: Int] = [122:1,120:2,99:3,118:4,96:5,97:6,98:7,100:8,101:9,109:10,103:11,111:12,105:13,107:14,113:15,106:16,64:17,79:18,80:19,90:20]
  static func eventKey(_ event: NSEvent) -> String? {
    if let number = functionKeyCodes[event.keyCode], let scalar = UnicodeScalar(0xF703 + number) { return String(scalar) }
    return event.charactersIgnoringModifiers?.lowercased()
  }
  nonisolated private static func functionNumber(_ key: String) -> Int? {
    guard key.unicodeScalars.count == 1, let value = key.unicodeScalars.first?.value,
      (0xF704...0xF726).contains(value) else { return nil }
    return Int(value - 0xF703)
  }
  nonisolated static func keyLabel(_ key: String) -> String {
    functionNumber(key).map { "F\($0)" } ?? key.uppercased()
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
    let key=eventKey(event)
    var flags=event.modifierFlags.intersection([.command,.shift,.option,.control]),expected=binding.flags
    // Turkish / is Shift+7. Shift used to produce the symbol is part of the glyph.
    if key == "/",binding.key == "/" {flags.remove(.shift);expected.remove(.shift)}
    return !binding.key.isEmpty && key == binding.key && flags == expected
  }
  static func matchesHeaders(_ event: NSEvent) -> Bool {
    matches(.headers,event)
  }
  struct AssignmentFeedback {
    enum Tone {case success,warning,error}
    let message:String
    var tone:Tone = .warning
    var target:Action? = nil
  }
  private struct ReservedShortcut {
    let binding:Binding
    let title:String
    let action:Action?
  }
  private static var reservedShortcuts:[ReservedShortcut] {
    func command(_ key:String,_ flags:NSEvent.ModifierFlags,_ action:Action)->ReservedShortcut {
      ReservedShortcut(binding:Binding(key:key,modifiers:flags.rawValue),title:title(action),action:action)
    }
    func native(_ key:String,_ flags:NSEvent.ModifierFlags,_ title:String)->ReservedShortcut {
      ReservedShortcut(binding:Binding(key:key,modifiers:flags.rawValue),title:title,action:nil)
    }
    return [
      command("\r",.command,.runStatement),
      command(" ",.control,.completion),
      command("b",.command,.definition),
      command(".",.command,.cancelQuery),
      command(",",.command,.settings),
      command("[",[.command,.option],.fold),
      command("]",[.command,.option],.unfoldAll),
      native("q",.command,"Uygulamadan çık"),
      command("w",.command,.closeWindow),
      command("s",.command,.saveFile),
      command("s",[.command,.shift],.saveAs),
      command("o",.command,.openFile),
      native("c",.command,"Kopyala"),
      native("v",.command,"Yapıştır"),
      native("x",.command,"Kes"),
      native("a",.command,"Tümünü seç"),
      command("z",.command,.undo),
      command("z",[.command,.shift],.redo),
      native("f",.command,"Bul"),
      native("f",.control,"Bul"),
      command("r",.command,.results),
      native("m",.command,"Pencereyi küçült"),
      command("l",.command,.estimatedPlan),
      command("b",[.command,.option],.explorer)
    ]
  }
  static func save(_ event:NSEvent,action:Action)->String? {
    let feedback=assign(event,action:action)
    return feedback.tone == .success ? nil:feedback.message
  }
  static func assign(_ event: NSEvent, action: Action) -> AssignmentFeedback {
    var flags = event.modifierFlags.intersection([.command,.shift,.option,.control])
    guard let key = eventKey(event), key.count == 1,
      functionNumber(key) != nil || ["/",",",".","[","]","\r"," "].contains(key) || key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }), flags.contains(.command) || flags.contains(.control)
    else { return AssignmentFeedback(message:"⌘ veya ⌃ ile harf, rakam, / , . [ ], Space, Enter veya F1–F35 kullanın. Escape iptal eder.") }
    if key == "/" {flags.remove(.shift)}
    // Configurable defaults are reserved only while still assigned to their
    // owner. Fixed native commands and history aliases keep their protection.
    let value = Binding(key:key,modifiers:flags.rawValue)
    let reserved=reservedShortcuts.first {
      $0.binding == value && ($0.action.map {binding($0) == value} ?? true)
    }
    let historyOwner:Action? = key == "z" && (flags == .command || flags == .control) ? .undo
      : (key == "z" && (flags == [.command,.shift] || flags == [.control,.shift])) || (key == "y" && flags == .control) ? .redo : nil
    if let historyOwner,historyOwner != action {
      return AssignmentFeedback(message:value.label+" “"+title(historyOwner)+"” işlemi için ayrılmış.",target:historyOwner)
    }
    if historyOwner != action,StudioCommandCatalog.definitions[action]?.defaultBinding != value,let reserved {
      let detail=reserved.action == nil ? " Bu yerleşik tuşun ayarlarda değiştirilebilir bir ataması yok.":""
      return AssignmentFeedback(message:value.label+" “"+reserved.title+"” işlemi için yerleşik olarak ayrılmış."+detail,target:reserved.action)
    }
    if let owner=Action.allCases.first(where:{$0 != action && binding($0) == value}) {
      return AssignmentFeedback(message:value.label+" zaten “"+title(owner)+"” işlemine atanmış.",target:owner)
    }
    guard let data=try? JSONEncoder().encode(value) else {return AssignmentFeedback(message:"Kısayol kaydedilemedi.",tone:.error)}
    UserDefaults.standard.set(data,forKey:"shortcut.\(action.rawValue)")
    NotificationCenter.default.post(name: changed, object: nil)
    return AssignmentFeedback(message:"Kısayol kaydedildi: "+title(action)+" · "+value.label,tone:.success)
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
