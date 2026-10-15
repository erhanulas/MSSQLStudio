import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor final class StudioHoverHelp {
  static let shared = StudioHoverHelp()
  private var monitor:Any?
  private var tableExit: Task<Void,Never>?
  var hasTablePreview: Bool {panel?.contentView is FunctionReturnPreview}
  var isPointerInsideTable: Bool {hasTablePreview && panel?.frame.contains(NSEvent.mouseLocation) == true}
  func keepTablePreview() {tableExit?.cancel();tableExit=nil}
  func leaveTablePreview() {
    guard tableExit == nil else {return}
    tableExit = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled, let self else {return}
      tableExit=nil
      if !isPointerInsideTable {hide()}
    }
  }
  private(set) var revision=UUID()
  private var pending: Task<Void, Never>?
  private var panel: NSPanel?
  private weak var source: NSView?
  private(set) var visibleTitle: String?
  private(set) var visibleDetail: String?
  /// Custom help controls must not also register AppKit's delayed tooltip.
  func configureText(_ text:String?,for view:NSView) {
    view.removeAllToolTips()
    view.setAccessibilityHelp(text)
    hide(for:view)
  }
  @discardableResult func begin(for view:NSView)->UUID {
    hide();source=view
    monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown,.keyDown,.scrollWheel]) { [weak self] event in
      MainActor.assumeIsolated {
        if event.type == .scrollWheel, self?.isPointerInsideTable == true {return}
        self?.hide()
      };return event
    }
    return revision
  }
  func schedule(for view: NSView, sqlSource: SQLResultSource? = nil,title:String?=nil,detail:String?=nil,rect:NSRect?=nil,columns:[SQLObjectHover.Column]=[]) {
    begin(for:view)
    pending = Task { [weak self, weak view] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      guard let self, let view, let window = view.window, window.isVisible,
        !view.isHiddenOrHasHiddenAncestor, let name = title ?? view.accessibilityLabel() ?? view.toolTip, !name.isEmpty else { return }
      let label = NSTextField(wrappingLabelWithString:String(name.prefix(1500)))
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textColor = StudioTheme.text
      label.alignment = .left;label.lineBreakMode = .byTruncatingTail;label.maximumNumberOfLines=4
      label.sizeToFit()
      let anchor = window.convertToScreen(view.convert(rect ?? view.bounds, to: nil))
      let screen = window.screen?.visibleFrame ?? anchor
      let width=min(480,max(80,min(label.frame.width+24,screen.width-16)))
      let height=min(68,max(16,ceil(label.attributedStringValue.boundingRect(with:NSSize(width:width-24,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)))
      var size=NSSize(width:width,height:height+20)
      let standard=NSView(frame:NSRect(origin:.zero,size:size))
      label.frame=NSRect(x:12,y:10,width:width-24,height:height)
      standard.addSubview(label)
      var content:NSView=standard
      if let sqlSource {
        let width = min(560, max(240, screen.width-24))
        let code = NSTextField(wrappingLabelWithString: sqlSource.preview)
        code.attributedStringValue = SQLSourceHighlighting.attributed(sqlSource.preview)
        code.maximumNumberOfLines = 16
        code.lineBreakMode = .byTruncatingTail
        let measured = code.attributedStringValue.boundingRect(with: NSSize(width: width-24, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = min(280, max(24, ceil(measured)+4))
        size = NSSize(width: width, height: height+50)
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true; box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1; box.layer?.borderColor = StudioTheme.border.cgColor
        box.layer?.backgroundColor = StudioTheme.editorCanvas.cgColor
        let heading = NSTextField(labelWithString: sqlSource.heading)
        heading.font = .systemFont(ofSize: 11, weight: .semibold); heading.textColor = StudioTheme.muted
        heading.frame = NSRect(x: 12, y: size.height-30, width: width-24, height: 18)
        code.frame = NSRect(x: 12, y: 12, width: width-24, height: height)
        box.addSubview(heading); box.addSubview(code); content = box
      }
      if let detail {
        let box=NSView();box.wantsLayer=true;box.layer?.cornerRadius=8;box.layer?.borderWidth=1;box.layer?.borderColor=StudioTheme.border.cgColor;box.layer?.backgroundColor=StudioTheme.panel.cgColor
        let heading=NSTextField(labelWithString:name);heading.font = .systemFont(ofSize:11,weight:.semibold);heading.textColor=StudioTheme.accent
        let text=NSTextField(wrappingLabelWithString:String(detail.prefix(1500)));text.font = .monospacedSystemFont(ofSize:11,weight:.regular);text.textColor=StudioTheme.text;text.maximumNumberOfLines=10;text.lineBreakMode = .byTruncatingTail
        let width=min(380,max(240,screen.width-24))
        let height=min(180,max(18,ceil(text.attributedStringValue.boundingRect(with:NSSize(width:width-20,height:1000),options:[.usesLineFragmentOrigin]).height)))
        size=NSSize(width:width,height:height+42);box.frame=NSRect(origin:.zero,size:size)
        heading.frame=NSRect(x:10,y:size.height-25,width:width-20,height:16);text.frame=NSRect(x:10,y:8,width:width-20,height:height)
        box.addSubview(heading);box.addSubview(text);content=box
      }
      if !columns.isEmpty {
        content=FunctionReturnPreview(title:name,columns:columns,screen:screen.size)
        size=content.frame.size
      }
      content.wantsLayer=true;content.layer?.cornerRadius=9;content.layer?.masksToBounds=true
      content.layer?.borderWidth=1;content.layer?.borderColor=StudioTheme.border.cgColor
      content.layer?.backgroundColor=(sqlSource == nil ? StudioTheme.panel:StudioTheme.editorCanvas).cgColor
      let rect=Self.placement(anchor:anchor,size:size,screen:screen)
      let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false; panel.level = .popUpMenu
      panel.ignoresMouseEvents = columns.isEmpty; panel.hasShadow = true;panel.hidesOnDeactivate=true
      panel.isOpaque=false;panel.backgroundColor = .clear
      panel.contentView = content
      window.addChildWindow(panel, ordered: .above)
      panel.orderFront(nil); self.panel = panel
      visibleTitle = name; visibleDetail = detail ?? sqlSource?.preview
    }
  }
  static func placement(anchor:NSRect,size:NSSize,screen:NSRect)->NSRect {
    let area=screen.insetBy(dx:8,dy:8)
    let size=NSSize(width:min(size.width,area.width),height:min(size.height,area.height))
    let below=anchor.minY-size.height-8
    let y=below>=area.minY ? below:min(area.maxY-size.height,anchor.maxY+8)
    return NSRect(x:min(max(area.minX,anchor.midX-size.width/2),area.maxX-size.width),y:max(area.minY,y),width:size.width,height:size.height)
  }
  func hide(for view: NSView? = nil) {
    if let view, source !== view { return }
    tableExit?.cancel();tableExit=nil
    revision=UUID()
    if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil
    pending?.cancel(); pending = nil
    if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    panel = nil; source = nil; visibleTitle = nil; visibleDetail = nil
  }
}
