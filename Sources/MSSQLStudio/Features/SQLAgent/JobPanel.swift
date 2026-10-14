import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct JobPanel: View {
  var databases: [String]
  var open: (String) -> Void
  @State private var name = ""
  @State private var database = "master"
  @State private var command = "SELECT SYSDATETIME();"
  @State private var daily = false
  @State private var time = "090000"
  @State private var preview = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "SQL Server Agent", icon: "clock.badge.checkmark", subtitle: "Yeni iş ve zamanlama SQL’i hazırla")
      StudioFormField("Job adı") {TextField("Job adı", text: $name)}
      StudioFormField("Veritabanı") {StudioSearchablePicker(title:"Veritabanı",values:databases,selection:$database)}
      VSplitView {
        VStack(alignment:.leading,spacing:8) {
          Text("T-SQL Step").font(.system(size:12,weight:.semibold))
          SQLCodeEditor(text:$command).studioEditor().frame(minHeight:100,idealHeight:150)
          HStack {
            Toggle("Her gün çalıştır", isOn: $daily)
            TextField("HHMMSS", text: $time).frame(width: 120).disabled(!daily)
          }
        }.frame(minHeight:170,idealHeight:230)
        VStack(alignment:.leading,spacing:8) {
          HStack {
            StudioActionButton("SQL Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) {
              do {
                if daily && Int(time) == nil { throw SQLFailure("Saat HHMMSS olmalı.") }
                preview = try Scripts.job(
                  name: name, database: database, command: command, dailyTime: daily ? Int(time) : nil)
                error = ""
              } catch let failure { error = failure.localizedDescription }
            }
            StudioActionButton("Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) { open(preview) }.disabled(preview.isEmpty)
          }
          Text(
            "Job oluşturma SQL'i ayrı sekmede incelenip çalıştırılır. Zamanlama için SQL Server Agent çalışıyor olmalı."
          ).font(.caption).foregroundStyle(.secondary)
          SQLCodeEditor(text:$preview).studioEditor().frame(minHeight:120)
        }.frame(minHeight:210,idealHeight:280)
      }
      StudioFeedback(message:error)
    }.padding(StudioMetrics.gap).studioPanel()
  }
}
