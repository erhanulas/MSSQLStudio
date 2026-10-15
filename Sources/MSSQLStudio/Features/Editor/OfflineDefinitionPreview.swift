import AppKit
import SQLServerKit
import SwiftUI

/// Transient view state. Never becomes the editable SQL or an ALTER conflict baseline.
@MainActor struct OfflineDefinitionPreview {
  let server: ConnectedServer
  let database: String
  let value: IndexedObjectDefinition
}

struct InlineOfflineDefinitionView: View {
  let preview: OfflineDefinitionPreview
  let back: () -> Void
  let navigate: ([String]) -> Void
  var revealInExplorer: (([String])->Void)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        StudioActionButton("SQL’e Dön", icon: "arrow.uturn.backward", action: back)
          .accessibilityIdentifier("offlineDefinitionBack")
        Label("Çevrimdışı tanım · Salt okunur",systemImage:"network.slash").font(.system(size:12,weight:.medium)).foregroundStyle(Color(nsColor:StudioTheme.warning))
        Spacer()
      }
      Text(preview.database + " · " + preview.value.item.qualified + " · Son okuma: " + preview.value.fetchedAt.formatted(date: .numeric, time: .shortened)).lineLimit(1).truncationMode(.middle).studioHelp(preview.database+" · "+preview.value.item.qualified)
        .font(.caption).foregroundStyle(.secondary)
      Text("Sunucudaki tanım farklı olabilir. SQL’iniz ve sonuçlarınız korunur.")
        .font(.caption).foregroundStyle(.secondary)
      SQLReadOnlyPreview(sql: preview.value.sql, navigateDefinition: navigate,revealInExplorer:revealInExplorer)
    }.padding(12).studioPanel()
  }
}

enum DefinitionReference {
  static func isNavigationClick(_ event:NSEvent)->Bool {
    event.clickCount==1 && event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command
  }
  @MainActor static func clickedOffset(in editor:NSTextView,at point:NSPoint)->Int? {
    guard editor.string.utf16.count<=100_000,let content=editor.textContentStorage,let layout=editor.textLayoutManager else {return nil}
    let offset=editor.characterIndexForInsertion(at:point)
    let tokens=TSQL.lex(editor.string)
    guard let token=tokens.first(where:{$0.kind == .word && offset >= $0.range.location && offset <= NSMaxRange($0.range)}),
      let start=content.location(content.documentRange.location,offsetBy:token.range.location),
      let end=content.location(start,offsetBy:token.range.length),let range=NSTextRange(location:start,end:end) else {return nil}
    layout.ensureLayout(for:range)
    var hit=false
    layout.enumerateTextSegments(in:range,type:.standard,options:[]) {_,rect,_,_ in
      if rect.offsetBy(dx:editor.textContainerOrigin.x,dy:editor.textContainerOrigin.y).insetBy(dx:-3,dy:-3).contains(point) {hit=true}
      return !hit
    }
    return hit ? offset:nil
  }
  static func parts(in sql: String, at caret: Int,maxParts:Int=2) -> [String]? {
    guard sql.utf16.count <= 100_000 else {return nil}
    let tokens=TSQL.lex(sql).filter {![.space,.comment].contains($0.kind)}
    guard let i=tokens.firstIndex(where: {caret >= $0.range.location && caret < NSMaxRange($0.range) || caret == NSMaxRange($0.range) && $0.kind == .word}),tokens[i].kind == .word else {return nil}
    func raw(_ value:String)->String {
      if value.hasPrefix("[") {return String(value.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]")}
      if value.hasPrefix("\"") {return String(value.dropFirst().dropLast()).replacingOccurrences(of:"\"\"",with:"\"")}
      return value
    }
    var start=i,end=i
    while start >= 2,tokens[start-1].text == ".",tokens[start-2].kind == .word {start -= 2}
    while end+2 < tokens.count,tokens[end+1].text == ".",tokens[end+2].kind == .word {end += 2}
    let parts=stride(from:start,through:end,by:2).map {raw(tokens[$0].text)}
    return parts.count <= maxParts ? parts:nil // Default definition navigation remains limited to the current database.
  }
}

extension WorkbenchController {
  func openOfflineDefinition(named parts:[String], server:ConnectedServer, database:String, in document:QueryDocument) {
    guard !server.online else {return}
    let request=UUID();document.offlinePreviewRequest=request
    Task { [weak self,weak document] in
      guard let self,let document else {return}
      do {
        var matches:[CatalogItem]=[]
        for folder in [Folder.tables,.views,.procedures,.functions,.synonyms,.triggers] {
          matches += try await server.definitionIndex.items(database:database,folder:folder).filter {
            $0.name.caseInsensitiveCompare(parts.last ?? "") == .orderedSame && (parts.count == 1 || $0.schema.caseInsensitiveCompare(parts[0]) == .orderedSame)
          }
        }
        let preferred=parts.count == 1 ? matches.filter {$0.schema.caseInsensitiveCompare("dbo") == .orderedSame}:matches
        let candidates=preferred.isEmpty ? matches:preferred
        guard candidates.count == 1,let item=candidates.first else {throw SQLFailure(candidates.isEmpty ? "Bu nesnenin çevrimdışı tanımı indekslenmemiş." : "Nesne adı belirsiz; şema adıyla tekrar deneyin.")}
        let value=try await server.definitionIndex.cached(database:database,id:item.id)
        guard state.documents.contains(where:{$0 === document}),document.offlinePreviewRequest == request else {return}
        document.offlinePreview=OfflineDefinitionPreview(server:server,database:database,value:value)
        document.changed?()
      } catch is CancellationError {}
      catch {if document.offlinePreviewRequest == request {state.showError(error.localizedDescription)}}
    }
  }
}
