import AppKit
import SQLServerKit
import SwiftUI

struct AgentScheduleEditor:View {
  @Environment(\.dismiss) private var dismiss
  @State var schedule:SQLAgent.Schedule
  let isNew:Bool
  var cancel:(()->Void)? = nil
  var submitTitle="Değişiklik SQL’ini Aç"
  let open:(SQLAgent.Schedule)->Void
  @State private var error=""
  private var frequency:Int {Int(schedule.frequency) ?? 4}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:isNew ? "New Job Schedule":"Schedule Properties",icon:"calendar",subtitle:schedule.name)
      if !isNew && schedule.jobCount>1 {Label("Paylaşılan zamanlama · \(schedule.jobCount) işin tamamı etkilenir.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)}
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          StudioFormField("Zamanlama adı") {TextField("Zamanlama adı",text:$schedule.name)}
          Toggle("Etkin",isOn:$schedule.enabled).padding(.leading,162)
          StudioFormField("Zamanlama türü") {Picker("Zamanlama türü",selection:$schedule.frequency) {Text("Bir kez").tag("1");Text("Günlük").tag("4");Text("Haftalık").tag("8");Text("Aylık · Gün").tag("16");Text("Aylık · Göreli gün").tag("32");Text("Agent başladığında").tag("64");Text("İşlemci boşta olduğunda").tag("128")}.labelsHidden()}
          if frequency == 4 {Stepper("Her \(schedule.interval) gün",value:$schedule.interval,in:1...999).padding(.leading,162)}
          if frequency == 8 {
            Stepper("Her \(schedule.recurrence) hafta",value:$schedule.recurrence,in:1...999).padding(.leading,162)
            HStack {ForEach(Array(["Paz","Pzt","Sal","Çar","Per","Cum","Cmt"].enumerated()),id:\.offset) {item in
              Toggle(item.element,isOn:Binding(get:{schedule.interval & (1 << item.offset) != 0},set:{value in let bit=1 << item.offset;schedule.interval=value ? schedule.interval | bit:schedule.interval & ~bit})).toggleStyle(.button)
            }}
          }
          if frequency == 16 {Stepper("Ayın \(schedule.interval). günü",value:$schedule.interval,in:1...31).padding(.leading,162)}
          if frequency == 16 || frequency == 32 {Stepper("Her \(schedule.recurrence) ay",value:$schedule.recurrence,in:1...999).padding(.leading,162)}
          if frequency == 32 {
            StudioFormField("Sıra") {Picker("Sıra",selection:$schedule.relativeInterval) {Text("İlk").tag(1);Text("İkinci").tag(2);Text("Üçüncü").tag(4);Text("Dördüncü").tag(8);Text("Son").tag(16)}.labelsHidden()}
            StudioFormField("Gün") {Picker("Gün",selection:$schedule.interval) {Text("Pazar").tag(1);Text("Pazartesi").tag(2);Text("Salı").tag(3);Text("Çarşamba").tag(4);Text("Perşembe").tag(5);Text("Cuma").tag(6);Text("Cumartesi").tag(7);Text("Gün").tag(8);Text("Hafta içi").tag(9);Text("Hafta sonu").tag(10)}.labelsHidden()}
          }
          if frequency != 64 && frequency != 128 {
            Divider()
            StudioFormField("Gün içi tekrar") {Picker("Gün içi tekrar",selection:$schedule.subdayType) {Text("Belirtilen saatte").tag(1);Text("Saniye").tag(2);Text("Dakika").tag(4);Text("Saat").tag(8)}.labelsHidden()}.disabled(frequency == 1)
            if schedule.subdayType != 1 {StudioFormField("Tekrar aralığı") {TextField("Tekrar aralığı",value:$schedule.subdayInterval,format:.number)}}
            StudioFormField("Başlangıç saati") {DatePicker("Başlangıç saati",selection:timeBinding(end:false),displayedComponents:.hourAndMinute).labelsHidden()}
            Stepper("Başlangıç saniyesi: \(Int(schedule.time).map {$0 % 100} ?? 0)",value:Binding(get:{Int(schedule.time).map {$0 % 100} ?? 0},set:{value in let n=Int(schedule.time) ?? 0;schedule.time=String(format:"%06d",n/100*100+value)}),in:0...59).padding(.leading,162)
            if schedule.subdayType != 1 {StudioFormField("Bitiş saati") {DatePicker("Bitiş saati",selection:timeBinding(end:true),displayedComponents:.hourAndMinute).labelsHidden()}}
          }
          StudioFormField("Başlangıç tarihi") {DatePicker("Başlangıç tarihi",selection:dateBinding(end:false),displayedComponents:.date).labelsHidden()}
          Toggle("Bitiş tarihi yok",isOn:Binding(get:{schedule.endDate == 99991231},set:{value in schedule.endDate=value ? 99991231:schedule.startDate}))
          if schedule.endDate != 99991231 {StudioFormField("Bitiş tarihi") {DatePicker("Bitiş tarihi",selection:dateBinding(end:true),displayedComponents:.date).labelsHidden()}}
          Text(schedule.summary).font(.callout).foregroundStyle(.secondary)
          Text("Saat ve tarihler SQL Server'ın yerel saatine göredir.").font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }
      if !error.isEmpty {StudioFeedback(message:error)}
      HStack {StudioActionButton("Vazgeç", icon:"xmark") {if let cancel {cancel()} else {dismiss()}}.keyboardShortcut(.cancelAction);Spacer();StudioActionButton(submitTitle, icon:"square.and.arrow.down") {
        do {_=try SQLAgent.scheduleScript(schedule,jobID:isNew ? UUID().uuidString:nil);open(schedule)} catch {self.error=error.localizedDescription}
      }.buttonStyle(StudioPrimaryButton()).accessibilityIdentifier("agentScheduleScript")}
    }.padding(StudioMetrics.gap).frame(minWidth:620,idealWidth:760,maxWidth:.infinity,minHeight:480,idealHeight:670,maxHeight:.infinity).studioPanel().interactiveDismissDisabled()
      .onChange(of:schedule.frequency) {_,newValue in
        if newValue == "1" {schedule.subdayType=1}
        if newValue == "32" && !(1...10).contains(schedule.interval) {schedule.interval=1}
        if newValue == "16" && !(1...31).contains(schedule.interval) {schedule.interval=1}
      }
  }
  private func dateBinding(end:Bool)->Binding<Date> {
    Binding(get:{
      let n=end ? schedule.endDate:schedule.startDate
      return Calendar.current.date(from:DateComponents(year:n/10000,month:(n/100)%100,day:n%100)) ?? Date()
    },set:{date in
      let c=Calendar.current.dateComponents([.year,.month,.day],from:date)
      let n=(c.year ?? 1990)*10000+(c.month ?? 1)*100+(c.day ?? 1)
      if end {schedule.endDate=n} else {schedule.startDate=n}
    })
  }
  private func timeBinding(end:Bool)->Binding<Date> {
    Binding(get:{
      let n=end ? schedule.endTime:(Int(schedule.time) ?? 0)
      return Calendar.current.date(from:DateComponents(year:2000,month:1,day:1,hour:n/10000,minute:(n/100)%100,second:n%100)) ?? Date()
    },set:{date in
      let c=Calendar.current.dateComponents([.hour,.minute],from:date)
      let seconds=(end ? schedule.endTime:(Int(schedule.time) ?? 0))%100
      let n=(c.hour ?? 0)*10000+(c.minute ?? 0)*100+seconds
      if end {schedule.endTime=n} else {schedule.time=String(format:"%06d",n)}
    })
  }

}
