import AppKit
import SQLServerKit

@MainActor enum ProfilerMessagePresentation {
  static func tone(_ level:SQLProfiler.MessageLevel?)->StudioFeedback.Tone {
    switch level {case .warning:.warning;case .error:.error;default:.info}
  }
  static func color(_ level:SQLProfiler.MessageLevel?)->NSColor {
    switch level {
    case .info:StudioTheme.accent
    case .warning:StudioTheme.warning
    case .error:StudioTheme.danger
    default:StudioTheme.muted
    }
  }
  static func heading(_ event:SQLProfiler.Event)->String {
    var parts=[event.messageLevel?.title ?? "Sunucu mesajı"]
    if let number=event.errorNumber {parts.append("SQL Server \(number)")}
    if let severity=event.severity {parts.append("Önem derecesi \(severity)")}
    else if event.kind=="error_reported" {parts.append("Önem derecesi alınamadı")}
    if let state=event.errorState {parts.append("Durum \(state)")}
    return parts.joined(separator:" · ")
  }
  static func details(_ event:SQLProfiler.Event)->String {
    heading(event)+"\n"+event.message
  }
}
