import SwiftUI
import SQLServerKit

/// Shared readable release content for About and the update offer.
struct ReleaseNoteContent:View {
  let note:ReleaseNote
  @Environment(\.colorScheme) private var colorScheme
  var body:some View {
    let _=colorScheme
    VStack(alignment:.leading,spacing:12) {
      VStack(alignment:.leading,spacing:6) {
        HStack(spacing:8) {
          Text(note.version).font(.system(size:11,weight:.semibold,design:.monospaced))
            .foregroundStyle(Color(nsColor:StudioTheme.accent)).padding(.horizontal,8).padding(.vertical,4)
            .background(Color(nsColor:StudioTheme.selection),in:Capsule())
          Text(note.date).font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
        }
        Text(note.title).font(.system(size:StudioMetrics.headingFont,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
      }
      ForEach(Array(note.changes.enumerated()),id:\.offset) {_,change in
        HStack(alignment:.top,spacing:10) {
          Image(systemName:"checkmark.circle.fill").foregroundStyle(Color(nsColor:StudioTheme.accent)).padding(.top,2)
          Text(change).font(.system(size:StudioMetrics.bodyFont)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
        }
      }
    }.frame(maxWidth:.infinity,alignment:.leading)
  }
}
