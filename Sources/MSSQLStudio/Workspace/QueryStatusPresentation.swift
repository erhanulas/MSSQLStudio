import AppKit

/// Stateless status styling shared by main and detached query windows.
@MainActor struct QueryStatusPresentation {
  let text:String
  let symbol:String
  let color:NSColor
  init(document:QueryDocument,operation:String?=nil,connectionError:String?=nil) {
    if let operation {text=operation;symbol="arrow.triangle.2.circlepath";color=StudioTheme.accent;return}
    if let error=connectionError ?? document.connectionError {text="Bağlantı başarısız: "+error;symbol="exclamationmark.circle.fill";color=StudioTheme.danger;return}
    if document.offlinePreview != nil {text="Çevrimdışı tanım · Salt okunur";symbol="eye";color=StudioTheme.warning;return}
    if document.definitionLoading {text="Nesne tanımı yükleniyor…";symbol="arrow.down.doc";color=StudioTheme.accent;return}
    switch document.state {
    case .ready:
      if document.executionFailed {text="Hata";symbol="exclamationmark.circle.fill";color=StudioTheme.danger}
      else if document.transactionCount>0 {text="Ready";symbol="exclamationmark.triangle.fill";color=StudioTheme.warning}
      else {text="Ready";symbol="checkmark.circle.fill";color=StudioTheme.success}
    case .running:text="Executing…";symbol="play.circle.fill";color=StudioTheme.accent
    case .connecting:text="Connecting…";symbol="network";color=StudioTheme.accent
    case .cancelling:text="Cancelling…";symbol="stop.circle.fill";color=StudioTheme.warning
    case .disconnected:text=document.disconnectedStatus;symbol="network.slash";color=StudioTheme.muted
    }
  }
  static func makeIcon()->NSImageView {
    let icon=NSImageView();icon.setAccessibilityElement(false)
    icon.setAccessibilityIdentifier("queryStatusIcon")
    icon.widthAnchor.constraint(equalToConstant:14).isActive=true
    icon.heightAnchor.constraint(equalToConstant:14).isActive=true
    return icon
  }
  func apply(to field:NSTextField,icon:NSImageView,detail:String) {
    Self.apply(text:text,symbol:symbol,color:color,to:field,icon:icon,detail:detail)
  }
  static func apply(text:String,symbol:String,color:NSColor,to field:NSTextField,icon:NSImageView,detail:String="") {
    icon.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:11,weight:.semibold))
    icon.contentTintColor=color
    let value=NSMutableAttributedString(string:text,attributes:[.foregroundColor:color,.font:field.font ?? NSFont.monospacedSystemFont(ofSize:10,weight:.regular)])
    value.append(NSAttributedString(string:detail,attributes:[.foregroundColor:StudioTheme.muted,.font:field.font ?? NSFont.monospacedSystemFont(ofSize:10,weight:.regular)]))
    field.attributedStringValue=value
  }
}
