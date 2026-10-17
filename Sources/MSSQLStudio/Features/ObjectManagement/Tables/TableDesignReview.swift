import SwiftUI

struct TableDesignReview:View {
  @ObservedObject var model:TableDesignerModel
  let plan:TableDesignPlan
  let context:String
  @Environment(\.dismiss) private var dismiss
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Tablo Değişikliklerini İncele",icon:"tablecells",subtitle:context+" · "+plan.schema+"."+plan.name)
      Text("SQL yalnız onayınızla gönderilir. Kolon silme verileri kaldırır; anahtar ve ilişki değişiklikleri bağlı işlemleri etkileyebilir.").font(.callout).foregroundStyle(.secondary)
      SQLReadOnlyPreview(sql:plan.sql).frame(maxWidth:.infinity,maxHeight:.infinity).studioCard(padding:0)
      if model.busy {StudioLoadingView(title:"Tablo güncelleniyor",context:context,phase:"Güncel tasarım doğrulanıyor, değişiklikler uygulanıyor ve metadata yenileniyor…").frame(height:124)}
      if !model.error.isEmpty {StudioFeedback(message:model.error)}
      HStack {
        StudioActionButton("Vazgeç",icon:"xmark") {dismiss()}.disabled(model.busy)
        Spacer()
        StudioActionButton("Onayla ve Veritabanına Gönder",icon:"externaldrive.badge.checkmark") {
          Task {if await model.apply(plan) {dismiss()}}
        }.buttonStyle(StudioPrimaryButton()).disabled(model.busy || model.unverified || !model.isCurrent(plan))
      }.fixedSize(horizontal:false,vertical:true)
    }.padding(16).studioPanel().frame(minWidth:720,maxWidth:.infinity,minHeight:520,maxHeight:.infinity).interactiveDismissDisabled(model.busy)
  }
}
