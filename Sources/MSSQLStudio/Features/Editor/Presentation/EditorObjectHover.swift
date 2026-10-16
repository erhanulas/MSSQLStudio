import AppKit
import SQLServerKit

@MainActor final class EditorObjectHover {
  private weak var editor:SQLTextView?
  private weak var document:QueryDocument?
  private var task:Task<Void,Never>?
  private var source=""
  private var activeRange:NSRange?

  init(document:QueryDocument,editor:SQLTextView) {self.document=document;self.editor=editor}
  deinit {task?.cancel()}
  func hide() {task?.cancel();task=nil;activeRange=nil;if let editor {StudioHoverHelp.shared.hide(for:editor)}}
  func move(_ point:NSPoint?) {
    if source != editor?.string {hide()}
    if StudioHoverHelp.shared.isPointerInsideTable {StudioHoverHelp.shared.keepTablePreview();return}
    if StudioHoverHelp.shared.hasTablePreview {
      if let point,let editor,let activeRange,NSLocationInRange(editor.characterIndexForInsertion(at:point),activeRange) {StudioHoverHelp.shared.keepTablePreview();return}
      StudioHoverHelp.shared.leaveTablePreview();return
    }
    guard let point,let editor,let document,editor.window?.isVisible == true,
      editor.string==document.sql,editor.string.utf16.count<=100_000,!editor.hasMarkedText(),!editor.trackingMouseSelection else {hide();return}
    let offset=editor.characterIndexForInsertion(at:point)
    if source==editor.string,let activeRange,NSLocationInRange(offset,activeRange) {return}
    hide();source=editor.string
    let source=source,server=document.server,db=document.database,generation=server.generation
    let hoverRevision=StudioHoverHelp.shared.begin(for:editor)
    task=Task { [weak self,weak editor,weak document] in
      do {
        try await Task.sleep(for:.milliseconds(250))
        guard let self,let editor,let document,!Task.isCancelled else {return}
        let tokens=TSQL.lex(source)
        guard let token=tokens.first(where:{$0.kind == .word && NSLocationInRange(offset,$0.range)}),
          let parts=DefinitionReference.parts(in:source,at:offset,maxParts:3) else {return}
        activeRange=token.range
        let analysis=try SQLIntelligence.analyze(source:source,caret:offset,catalog:document.intelligenceCatalog,verified:false,currentDatabase:db)
        var targets:[[String]]=[],column:String?
        var includeTableColumns=false
        if parts.count==1,["inserted","deleted"].contains(parts[0].lowercased()),let resolved=analysis.referenceBindings[parts[0].lowercased()] {targets=[resolved];includeTableColumns=true}
        else if parts.count==2,let resolved=analysis.referenceBindings[parts[0].lowercased()] {targets=[resolved];column=parts[1]}
        else if let symbol=document.intelligenceCatalog?.resolve(parts) {
          let triggerTarget=analysis.referenceBindings["inserted"]
          let triggerHeader=tokens.first(where:{$0.text.uppercased() == "TRIGGER"})
          let headerAS=tokens.first(where:{$0.text.uppercased() == "AS" && $0.range.location > (triggerHeader?.range.location ?? Int.max)})
          let isTriggerTarget=triggerTarget == parts && triggerHeader != nil && token.range.location < (headerAS?.range.location ?? 0)
          guard symbol.kind.contains("FUNCTION") || isTriggerTarget else {return}
          includeTableColumns=isTriggerTarget
          targets=[parts]
        }
        else if parts.count==2 {targets=[parts]}
        else if parts.count==3 {targets=[Array(parts.prefix(2))];column=parts[2]}
        else {
          var seen=Set<String>()
          targets=analysis.referenceBindings.values.filter {seen.insert($0.joined(separator:".")).inserted && $0.count<=2}
          column=parts[0]
        }
        guard !targets.isEmpty,targets.count<=8,server.online else {return}
        let info=try await server.hoverMetadata.lookup(targets:targets,column:column,database:db,includeTableColumns:includeTableColumns)
        guard !Task.isCancelled,StudioHoverHelp.shared.revision==hoverRevision,
          source==editor.string,document.database==db,document.server === server,server.generation==generation,editor.window?.isVisible == true,
          let info else {return}
        let rects=editor.rects(forCharacterRange:token.range)?.map(\.rectValue) ?? []
        guard let anchor=rects.first(where:{$0.intersects(editor.visibleRect)}) else {return}
        StudioHoverHelp.shared.schedule(for:editor,title:info.title,detail:info.detail,rect:anchor,columns:info.columns)
      } catch { /* Hover is optional; unavailable metadata never blocks typing or opens alerts. */ }
    }
  }
}
