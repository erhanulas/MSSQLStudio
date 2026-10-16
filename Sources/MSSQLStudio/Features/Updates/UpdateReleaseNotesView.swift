import SwiftUI
import SQLServerKit

struct UpdateReleaseNotesView:View {
  let notes:[ReleaseNote]
  let error:String
  var body:some View {
    ScrollView {
      LazyVStack(alignment:.leading,spacing:12) {
        if !error.isEmpty {StudioFeedback(message:"Sürüm notları alınamadı. "+error,tone:.warning)}
        ForEach(Array(notes.enumerated()),id:\.offset) {_,note in
          ReleaseNoteContent(note:note).studioCard(padding:12)
        }
        if notes.isEmpty && error.isEmpty {
          Text("Bu sürüm aralığı için değişiklik notu bulunamadı.").foregroundStyle(.secondary)
        }
      }.padding(4)
    }.accessibilityIdentifier("updateReleaseNotes")
      .foregroundStyle(.primary).studioPanel()
  }
}
