import AppKit
import SQLServerKit
import SwiftUI

struct AgentStatus:View {
  let status:Int
  var body:some View {
    HStack(spacing:5) {
      Image(systemName:status == 1 ? "checkmark.circle.fill":status == 0 ? "xmark.circle.fill":status == 4 ? "arrow.triangle.2.circlepath":status == 2 ? "arrow.clockwise":"minus.circle")
        .foregroundStyle(status == 1 ? Color.green:status == 0 ? .red:status == 4 ? .blue:.secondary)
      Text(label)
    }.accessibilityElement(children:.ignore).accessibilityLabel(label)
  }
  private var label:String {switch status {case 0:"Failed";case 1:"Succeeded";case 2:"Retry";case 3:"Canceled";case 4:"Running";default:"—"}}
}
