import SwiftUI
import SQLServerKit

struct ActivityResourceCards:View {
  let sample:ActivityMonitoring.Sample?
  var body:some View {
    let health=sample?.health
    return HStack(spacing:8) {
      card("Oturum",icon:"person.2",value:ActivityFormat.count(health?.userSessions),detail:"Kullanıcı oturumları")
      card("SQL Server CPU",icon:"cpu",value:ActivityFormat.number(sample?.cpu)+" %",detail:"İşlemci kullanımı",percent:sample?.cpu)
      card("SQL bellek",icon:"memorychip",value:ActivityFormat.memory(health?.sqlMemoryMB),detail:"Fiziksel bellek payı",percent:ActivityMonitoring.memoryPercent(health?.sqlMemoryMB,total:health?.totalMemoryMB))
      card("Boş bellek",icon:"square.stack.3d.up",value:ActivityFormat.memory(health?.availableMemoryMB),detail:"Kullanılabilir fiziksel",percent:ActivityMonitoring.memoryPercent(health?.availableMemoryMB,total:health?.totalMemoryMB))
      card("Okuma",icon:"arrow.down.circle",value:ActivityFormat.number(sample?.readLatencyMS)+" ms",detail:"Ortalama gecikme")
      card("Yazma",icon:"arrow.up.circle",value:ActivityFormat.number(sample?.writeLatencyMS)+" ms",detail:"Ortalama gecikme")
    }.accessibilityIdentifier("activityResourceCards")
  }
  private func card(_ title:String,icon:String,value:String,detail:String,percent:Double?=nil)->some View {
    VStack(alignment:.leading,spacing:6) {
      Label(title,systemImage:icon).font(.system(size:11,weight:.medium)).foregroundStyle(Color(nsColor:StudioTheme.muted)).lineLimit(1)
      HStack(alignment:.firstTextBaseline,spacing:4) {
        Text(value).font(.system(size:18,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1)
        Spacer(minLength:0)
      }
      if let percent {
        ProgressView(value:percent,total:100).tint(Color(nsColor:StudioTheme.accent)).controlSize(.small)
        Text(ActivityFormat.number(percent)+" % · "+detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
      } else {
        Text(detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength:0)
      }
    }.frame(maxWidth:.infinity,alignment:.leading).frame(height:78).studioCard(padding:8)
      .studioHelp(title+": "+value+(percent.map {" · "+ActivityFormat.number($0)+" %"} ?? "")+" · "+detail)
      .accessibilityElement(children:.combine)
  }
}
