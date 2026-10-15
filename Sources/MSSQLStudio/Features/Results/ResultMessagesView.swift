import AppKit

/// Styles the message snapshot without changing its text or clipboard contents.
@MainActor final class ResultMessagesView:StudioTextView {
  private var renderedAppearance:String?
  func show(_ source:String) {
    let appearance=effectiveAppearance.name.rawValue
    guard string != source || renderedAppearance != appearance else {return}
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
    let selection=selectedRange(),origin=enclosingScrollView?.contentView.bounds.origin
    textStorage?.setAttributedString(result)
    if NSMaxRange(selection)<=result.length {setSelectedRange(selection)}
    if let origin {enclosingScrollView?.contentView.scroll(to:origin)}
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance();renderedAppearance=nil;show(string)
  }
}
