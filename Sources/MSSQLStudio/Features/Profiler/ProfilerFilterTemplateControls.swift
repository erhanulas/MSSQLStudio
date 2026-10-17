import AppKit
import SwiftUI
import SQLServerKit

struct ProfilerFilterTemplateControls:View {
  @ObservedObject var model:ProfilerModel
  @ObservedObject private var templates:ProfilerFilterTemplatesModel
  @State private var selected:UUID?
  @State private var error=""
  init(model:ProfilerModel) {self.model=model;templates=model.templates}
  private var current:ProfilerFilterTemplate? {templates.templates.first {$0.id==selected}}
  var body:some View {
    VStack(alignment:.leading,spacing:4) {
      HStack(spacing:4) {
        StudioSelectionPicker(title:"Genel filtre şablonları",selection:$selected,options:[nil]+templates.templates.map {Optional($0.id)},label:{id in
          templates.templates.first {$0.id==id}?.name ?? "Filtre şablonu seç"
        }).frame(maxWidth:.infinity)
        Button {
          guard let current else {return}
          do {try model.applyTemplate(current);error=""} catch {self.error=error.localizedDescription}
        } label:{Image(systemName:"arrow.down.circle")}
          .buttonStyle(StudioSecondaryButton()).disabled(current==nil || model.hasSession || model.busy || templates.busy)
          .accessibilityLabel("Şablonu uygula").studioHelp("Seçili şablonun tüm filtrelerini uygula. İzleme başlamaz; aktif yakalamayı önce durdurun.")
        Button(action:saveAs) {Image(systemName:"square.and.arrow.down")}
          .buttonStyle(StudioSecondaryButton()).disabled(templates.busy || !templates.ready)
          .accessibilityLabel("Filtreleri şablon olarak kaydet").studioHelp("Mevcut yakalama ve grid filtrelerini tüm bağlantılarda kullanılabilen bir şablon olarak kaydet")
        Menu {
          Button {update()} label:{Label("Seçili Şablonu Güncelle",systemImage:"arrow.triangle.2.circlepath")}.disabled(current==nil)
          Button {remove()} label:{Label("Seçili Şablonu Sil…",systemImage:"trash")}.disabled(current==nil)
        } label:{Image(systemName:"ellipsis")}
          .menuStyle(.borderlessButton).fixedSize().disabled(templates.busy)
          .accessibilityLabel("Şablon işlemleri").studioHelp("Seçili genel şablonu güncelle veya sil")
      }
      Text("Genel · Tüm bağlantılarda kullanılabilir").font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
      if templates.busy {ProgressView().controlSize(.small)}
      if !templates.error.isEmpty {
        StudioFeedback(message:templates.error,tone:.error)
        if !templates.ready {Button("Şablonları Yeniden Yükle") {Task {await templates.load()}}.buttonStyle(StudioSecondaryButton()).disabled(templates.busy)}
      }
      if !error.isEmpty {StudioFeedback(message:error,tone:.warning)}
    }.task {await templates.load()}
      .onChange(of:templates.templates.map(\.id)) {_,ids in if let selected,!ids.contains(selected) {self.selected=nil}}
  }
  private func snapshot(id:UUID=UUID(),name:String) throws -> ProfilerFilterTemplate {
    try ProfilerFilterTemplate(id:id,name:name,configuration:model.configuration,displayFilter:model.displayFilter)
  }
  private func saveAs() {
    let alert=StudioAlert(role:"saveProfilerTemplate");alert.messageText="Filtre şablonunu kaydet"
    alert.informativeText="Yakalama ve grid filtreleri bu Mac’teki tüm bağlantılarda kullanılabilir. Şablonu uygulamak izlemeyi başlatmaz."
    let field=NSTextField(frame:NSRect(x:0,y:0,width:300,height:26))
    field.placeholderString="Şablon adı";field.setAccessibilityLabel("Şablon adı")
    alert.accessoryView=field;alert.addButton(withTitle:"Kaydet");alert.addButton(withTitle:"Vazgeç")
    alert.window.initialFirstResponder=field
    guard alert.runModal() == .alertFirstButtonReturn else {return}
    do {
      let value=try snapshot(name:field.stringValue)
      Task {if await templates.save(value) {selected=value.id;error=""}}
    } catch {self.error=error.localizedDescription}
  }
  private func update() {
    guard let current else {return}
    do {
      let value=try snapshot(id:current.id,name:current.name)
      Task {if await templates.save(value) {error=""}}
    } catch {self.error=error.localizedDescription}
  }
  private func remove() {
    guard let current else {return}
    let alert=StudioAlert(role:"deleteProfilerTemplate");alert.messageText="Genel şablon silinsin mi?"
    alert.informativeText="“\(current.name)” tüm bağlantıların şablon listesinden kaldırılacak. Mevcut filtreler ve izleme değişmez."
    alert.addButton(withTitle:"Sil");alert.addButton(withTitle:"Vazgeç")
    guard alert.runModal() == .alertFirstButtonReturn else {return}
    Task {await templates.remove(current.id)}
  }
}
