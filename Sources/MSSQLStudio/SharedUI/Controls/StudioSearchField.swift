import AppKit
import SwiftUI

/// Native editing, clearing and target/action with the same surface in all search hosts.
@MainActor private final class StudioSearchFieldCell:NSSearchFieldCell {
  private var editingFrameProvided=false
  override func draw(withFrame frame:NSRect,in view:NSView) {
    StudioTheme.controlSurface.setFill()
    let path=NSBezierPath(roundedRect:frame.insetBy(dx:0.5,dy:0.5),xRadius:StudioMetrics.controlRadius,yRadius:StudioMetrics.controlRadius)
    path.fill();StudioTheme.controlBorder.setStroke();path.lineWidth=1;path.stroke()
    super.drawInterior(withFrame:frame,in:view)
  }
  // NSCell editing otherwise uses the full control bounds, unlike search text drawing.
  override func edit(withFrame rect:NSRect,in controlView:NSView,editor:NSText,delegate:Any?,event:NSEvent?) {
    let textRect=editingFrameProvided ? rect:searchTextRect(forBounds:rect)
    let previous=editingFrameProvided;editingFrameProvided=true
    defer {editingFrameProvided=previous}
    super.edit(withFrame:textRect,in:controlView,editor:editor,delegate:delegate,event:event)
    (editor as? NSTextView)?.drawsBackground=false
    controlView.needsDisplay=true
  }
  override func select(withFrame rect:NSRect,in controlView:NSView,editor:NSText,delegate:Any?,start:Int,length:Int) {
    let textRect=editingFrameProvided ? rect:searchTextRect(forBounds:rect)
    let previous=editingFrameProvided;editingFrameProvided=true
    defer {editingFrameProvided=previous}
    super.select(withFrame:textRect,in:controlView,editor:editor,delegate:delegate,start:start,length:length)
    (editor as? NSTextView)?.drawsBackground=false
    controlView.needsDisplay=true
  }
  override func searchButtonRect(forBounds rect:NSRect)->NSRect {NSRect(x:rect.minX+8,y:rect.midY-8,width:16,height:16)}
  override func cancelButtonRect(forBounds rect:NSRect)->NSRect {NSRect(x:rect.maxX-24,y:rect.midY-8,width:16,height:16)}
  override func searchTextRect(forBounds rect:NSRect)->NSRect {
    let height=ceil(font?.boundingRectForFont.height ?? 16)
    return NSRect(x:rect.minX+30,y:rect.midY-height/2,width:max(0,rect.width-58),height:height)
  }
}

@MainActor final class StudioSearchField:NSSearchField {
  override init(frame:NSRect) {
    super.init(frame:frame)
    cell=StudioSearchFieldCell(textCell:"")
    isEditable=true;isSelectable=true
    (cell as? NSTextFieldCell)?.usesSingleLineMode=true
    font=StudioTheme.uiFont;controlSize = .small
    refreshStyle()
    NotificationCenter.default.addObserver(self,selector:#selector(refreshStyle),name:StudioTheme.changed,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  override var intrinsicContentSize:NSSize {NSSize(width:180,height:28)}
  @objc private func refreshStyle() {
    textColor=StudioTheme.text;backgroundColor=StudioTheme.controlSurface
    needsDisplay=true
  }
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshStyle()}
  override func draw(_ dirtyRect:NSRect) {
    super.draw(dirtyRect)
    guard currentEditor() != nil,let searchCell=cell as? NSSearchFieldCell else {return}
    let configuration=NSImage.SymbolConfiguration(paletteColors:[StudioTheme.muted])
    NSImage(systemSymbolName:"magnifyingglass",accessibilityDescription:nil)?.withSymbolConfiguration(configuration)?.draw(in:searchCell.searchButtonRect(forBounds:bounds))
    if !stringValue.isEmpty {
      NSImage(systemSymbolName:"xmark.circle.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[StudioTheme.controlSurface,StudioTheme.muted]))?.draw(in:searchCell.cancelButtonRect(forBounds:bounds))
    }
  }

  override func drawFocusRingMask() {NSBezierPath(roundedRect:bounds,xRadius:StudioMetrics.controlRadius,yRadius:StudioMetrics.controlRadius).fill()}
  override var focusRingMaskBounds:NSRect {bounds}
}

struct StudioSearchInput:NSViewRepresentable {
  let placeholder:String
  @Binding var text:String
  @Binding var focused:Bool
  let accessibilityLabel:String
  let accessibilityID:String
  var submit:()->Void={}
  final class Coordinator:NSObject,NSSearchFieldDelegate {
    var parent:StudioSearchInput
    init(_ parent:StudioSearchInput) {self.parent=parent}
    func controlTextDidChange(_ notification:Notification) {
      guard let field=notification.object as? NSSearchField else {return}
      parent.text=field.stringValue
    }
    func controlTextDidBeginEditing(_ notification:Notification) {parent.focused=true}
    func controlTextDidEndEditing(_ notification:Notification) {parent.focused=false}
    @objc func search(_ sender:NSSearchField) {
      parent.text=sender.stringValue
      if NSApp.currentEvent?.type == .keyDown,[36,76].contains(NSApp.currentEvent?.keyCode ?? 0) {parent.submit()}
    }
  }
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->StudioSearchField {
    let field=StudioSearchField(frame:.zero)
    field.delegate=context.coordinator;field.target=context.coordinator;field.action=#selector(Coordinator.search(_:))
    field.sendsWholeSearchString=true
    return field
  }
  func updateNSView(_ field:StudioSearchField,context:Context) {
    context.coordinator.parent=self
    field.placeholderString=placeholder;field.setAccessibilityLabel(accessibilityLabel);field.setAccessibilityIdentifier(accessibilityID)
    if field.stringValue != text {field.stringValue=text}
    if focused,field.currentEditor()==nil {field.window?.makeFirstResponder(field)}
    else if !focused,field.currentEditor() != nil {field.window?.makeFirstResponder(nil)}
  }
}
