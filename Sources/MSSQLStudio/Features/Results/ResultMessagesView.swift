import AppKit

/// Styles the message snapshot without changing its text or clipboard contents.
@MainActor final class ResultMessagesView:StudioTextView,NSTextViewDelegate {
  var navigate:((NSRange)->Void)?
  private var locations:[(message:NSRange,source:NSRange)]=[]
  func textView(_ textView:NSTextView,clickedOnLink link:Any,at charIndex:Int)->Bool {
    if let target=locations.last(where:{NSLocationInRange(charIndex,$0.message)}) {navigate?(target.source)}
    return true
  }
  private var renderedAppearance:String?
  func show(_ source:String,locations:[(message:NSRange,source:NSRange)]=[]) {
    let appearance=effectiveAppearance.name.rawValue
    guard string != source || renderedAppearance != appearance || self.locations.map(\.message) != locations.map(\.message) || self.locations.map(\.source) != locations.map(\.source) else {return}
    self.locations=locations;delegate=self
    renderedAppearance=appearance
    let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=5;paragraph.paragraphSpacing=4
    let result=NSMutableAttributedString(string:source,attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.text,.paragraphStyle:paragraph])
    let text=source as NSString
    var offset=0,count=0
    while offset<text.length,count<5000 {
      let range=text.lineRange(for:NSRange(location:offset,length:0)),line=text.substring(with:range).lowercased()
      let color:NSColor?
      if line.contains("hata") || line.contains("error") || line.hasPrefix("[42") || line.hasPrefix("[08") {color=StudioTheme.danger}
      else if line.contains("kısmi") || line.contains("sınır") || line.contains("uyarı") {color=StudioTheme.warning}
      else if line.contains("satır etkilendi") {color=StudioTheme.success}
      else {color=nil}
      if let color {result.addAttribute(.foregroundColor,value:color,range:range)}
      offset=NSMaxRange(range);count+=1
    }
    for (index,location) in locations.enumerated() where NSMaxRange(location.message)<=result.length {
      result.addAttributes([.link:URL(string:"studio-error://\(index)")!,.underlineStyle:NSUnderlineStyle.single.rawValue],range:location.message)
    }
    linkTextAttributes=[.foregroundColor:StudioTheme.danger,.underlineStyle:NSUnderlineStyle.single.rawValue]
    let selection=selectedRange(),origin=enclosingScrollView?.contentView.bounds.origin
    textStorage?.setAttributedString(result)
    if NSMaxRange(selection)<=result.length {setSelectedRange(selection)}
    if let origin {enclosingScrollView?.contentView.scroll(to:origin)}
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance();renderedAppearance=nil;show(string,locations:locations)
  }
}
