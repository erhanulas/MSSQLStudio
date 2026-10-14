import AppKit
import SQLServerKit
import SwiftUI

/// Editable SQL for management drafts; native undo and source colors share one owner.
struct SQLCodeEditor:NSViewRepresentable {
  @Binding var text:String
  @MainActor final class Coordinator:NSObject,NSTextViewDelegate {
    var parent:SQLCodeEditor
    weak var editor:NSTextView?
    private var source:String?
    private var dark:Bool?
    private var painting=false
    init(_ parent:SQLCodeEditor) {
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
    let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.borderType = .noBorder
    let view=StudioTextView(usingTextLayoutManager:true);view.isRichText=false;view.isAutomaticQuoteSubstitutionEnabled=false;view.isAutomaticDashSubstitutionEnabled=false;view.isAutomaticTextReplacementEnabled=false;view.isAutomaticSpellingCorrectionEnabled=false;view.allowsUndo=true
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

// Preserve the existing Agent/Favorites call sites and accessibility identity.
typealias AgentCommandEditor = SQLCodeEditor
