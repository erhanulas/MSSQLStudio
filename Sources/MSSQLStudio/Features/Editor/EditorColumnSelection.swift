import AppKit

/// NSTextView drops multiple empty ranges. Keep their positions locally while
/// native TextKit still owns text, nonempty selections, editing and undo.
@MainActor final class EditorColumnSelection {
  unowned let editor:SQLTextView
  private var snapshot=""
  private var stored:[NSRange]=[]
  private var origin:NSPoint?
  var affinity:NSSelectionAffinity = .downstream
  private var applying=false
  init(editor:SQLTextView) {self.editor=editor}
  var ranges:[NSRange] {
    if snapshot != editor.string {clear()}
    return stored
  }
  var dragging:Bool {origin != nil}
  func clear() {stored=[];origin=nil;editor.needsDisplay=true}
  func set(_ ranges:[NSRange],affinity:NSSelectionAffinity = .downstream) {
    let length=(editor.string as NSString).length
    stored=Array(Set(ranges.filter {$0.location != NSNotFound && NSMaxRange($0)<=length})).sorted {$0.location<$1.location}
    snapshot=editor.string;self.affinity=affinity
    let visible=stored.filter {$0.length>0}
    if let first=stored.first {
      editor.setSelectedRanges((visible.isEmpty ? [first]:visible).map {NSValue(range:$0)},affinity:affinity,stillSelecting:false)
    }
    editor.needsDisplay=true
  }
  func begin(at point:NSPoint) {clear();origin=point;update(to:point)}
  func update(to point:NSPoint) {
    guard let origin else {return}
    let source=editor.string as NSString
    let start=editor.characterIndexForInsertion(at:origin),end=editor.characterIndexForInsertion(at:point)
    var line=source.lineRange(for:NSRange(location:min(start,end),length:0))
    let last=source.lineRange(for:NSRange(location:max(start,end),length:0)).location
    var selections:[NSRange]=[]
    while line.location<=last,selections.count<4096 {
      let rect=caretRect(at:line.location)
      var contentEnd=NSMaxRange(line)
      while contentEnd>line.location,[10,13].contains(source.character(at:contentEnd-1)) {contentEnd-=1}
      func offset(_ x:CGFloat)->Int {
        min(contentEnd,max(line.location,editor.characterIndexForInsertion(at:NSPoint(x:x,y:rect.midY))))
      }
      let a=offset(origin.x),b=offset(point.x)
      selections.append(NSRange(location:min(a,b),length:abs(a-b)))
      guard NSMaxRange(line)>line.location,NSMaxRange(line)<=source.length else {break}
      if NSMaxRange(line)>last {break}
      line=source.lineRange(for:NSRange(location:NSMaxRange(line),length:0))
    }
    set(selections,affinity:point.x<origin.x ? .upstream:.downstream)
  }
  func end() {origin=nil}
  private func caretRect(at offset:Int)->NSRect {
    let screen=editor.firstRect(forCharacterRange:NSRange(location:offset,length:0),actualRange:nil)
    guard let window=editor.window else {return .zero}
    return editor.convert(window.convertFromScreen(screen),from:nil)
  }
  func draw(in dirty:NSRect) {
    guard editor.window?.firstResponder === editor else {return}
    editor.insertionPointColor.setFill()
    let visible=editor.visibleCharacterRanges.map(\.rangeValue)
    for range in ranges where range.length==0 && visible.contains(where:{$0.location<=range.location && NSMaxRange($0)>=range.location}) {
      var rect=caretRect(at:range.location);rect.size.width=1
      if rect.intersects(dirty) {rect.fill()}
    }
  }
  @discardableResult func removeIndent()->Bool {
    guard editor.isEditable,!editor.hasMarkedText(),ranges.count>1 else {return false}
    let previous=ranges,source=editor.string as NSString
    let edits=previous.map {range -> NSRange in
      let line=source.lineRange(for:range),text=source.substring(with:line)
      let count=text.hasPrefix("\t") ? 1:text.prefix(4).prefix(while:{$0 == " "}).count
      return NSRange(location:line.location,length:count)
    }
    set(edits)
    guard replace(with:"") else {set(previous);return true}
    var delta=0
    let restored=zip(previous,edits).map {range,edit -> NSRange in
      func offset(_ value:Int)->Int {value-delta-max(0,min(edit.length,value-edit.location))}
      let result=NSRange(location:offset(range.location),length:offset(NSMaxRange(range))-offset(range.location))
      delta+=edit.length
      return result
    }
    set(restored)
    return true
  }
  @discardableResult func replace(with text:String,backward:Bool?=nil)->Bool {
    guard !applying,editor.isEditable,!editor.hasMarkedText(),ranges.count>1 else {return false}
    let source=editor.string as NSString
    let edits=ranges.map {range -> NSRange in
      guard let backward,range.length==0 else {return range}
      let line=source.lineRange(for:range)
      // Deleting at the physical edge must not merge the selected rows.
      if backward,range.location>line.location {return source.rangeOfComposedCharacterSequence(at:range.location-1)}
      if !backward,range.location<source.length,![10,13].contains(source.character(at:range.location)) {return source.rangeOfComposedCharacterSequence(at:range.location)}
      return range
    }
    applying=true;defer {applying=false}
    editor.finishUndoInput();editor.undoManager?.beginUndoGrouping()
    editor.performBatchEdit {
      for range in edits.reversed() {editor.insertText(text,replacementRange:range)}
      var delta=0
      let carets=edits.map {range -> NSRange in
        let location=range.location+delta+(text as NSString).length
        delta+=(text as NSString).length-range.length
        return NSRange(location:location,length:0)
      }
      set(carets)
    }
    editor.undoManager?.endUndoGrouping();editor.finishUndoInput()
    return true
  }
}
