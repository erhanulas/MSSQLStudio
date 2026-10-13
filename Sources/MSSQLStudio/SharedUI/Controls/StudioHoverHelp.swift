import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor final class StudioHoverHelp {
  static let shared = StudioHoverHelp()
  private var pending: Task<Void, Never>?
  private var panel: NSPanel?
  private weak var source: NSView?
  private(set) var visibleTitle: String?
  private(set) var visibleDetail: String?
  func schedule(for view: NSView, sqlSource: SQLResultSource? = nil) {
    hide(); source = view
    pending = Task { [weak self, weak view] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      guard let self, let view, let window = view.window, window.isVisible,
        !view.isHiddenOrHasHiddenAncestor, let name = view.accessibilityLabel(), !name.isEmpty else { return }
      let label = NSTextField(labelWithString: name)
      label.font = .systemFont(ofSize: 11, weight: .medium)
      label.textColor = StudioTheme.text
      label.alignment = .center
      label.sizeToFit()
      var size = NSSize(width: label.frame.width + 16, height: 26)
      var content: NSView = label
      let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
      let screen = window.screen?.visibleFrame ?? anchor
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
      let below = anchor.minY-size.height-5
      let y = below >= screen.minY ? below : min(screen.maxY-size.height, anchor.maxY+5)
      let rect = NSRect(x: min(max(screen.minX, anchor.midX-size.width/2), screen.maxX-size.width),
        y: max(screen.minY, y), width: size.width, height: size.height)
      let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false; panel.level = .popUpMenu
      panel.ignoresMouseEvents = true; panel.hasShadow = true
      panel.backgroundColor = StudioTheme.panel
      panel.contentView = content
      window.addChildWindow(panel, ordered: .above)
      panel.orderFront(nil); self.panel = panel
      visibleTitle = name; visibleDetail = sqlSource?.preview
    }
  }
  func hide(for view: NSView? = nil) {
    if let view, source !== view { return }
    pending?.cancel(); pending = nil
    if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    panel = nil; source = nil; visibleTitle = nil; visibleDetail = nil
  }
}

