import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ModuleReviewController: NSObject, NSWindowDelegate {
  private let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:1400,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  private let left=NSScrollView(),right=NSScrollView(),script=NSScrollView()
  private let body=NSView(),summary=NSTextField(labelWithString:"Farklar hazırlanıyor…")
  private let tabs=NSSegmentedControl(labels:["Yan yana farklar","Çalıştırılacak SQL"],trackingMode:.selectOne,target:nil,action:nil)
  private let split=NSSplitView()
  private var diffContent:NSView?
  private var inlinePreview:SQLInlineDiffView?
  private let apply=StudioToolbarButton(symbol:"paperplane.fill",label:"Veritabanına Gönder",tone:.accent,title:"Veritabanına Gönder",width:175,prominent:true)
  private var syncing=false
  private var task:Task<Void,Never>?
  private var comparison:SQLTextDiff.Comparison?
  private var approved: (() -> Void)?
  private var finished: (() -> Void)?
  private var observers:[NSObjectProtocol]=[]
  init(parent:NSWindow,title:String,original:String,edited:String,canApply:Bool,leftTitle:String="Açılan tanım",rightTitle:String="Düzenlenen tanım",executionSQL:String?=nil,ignoringSQLWhitespace:Bool=false,editedOnLeft:Bool=false,approved:@escaping () -> Void,finished:@escaping () -> Void) {
    super.init()
    self.approved=approved;self.finished=finished
    panel.title="Nesne değişikliklerini incele";panel.minSize=NSSize(width:960,height:600);panel.delegate=self
    if let visible=parent.screen?.visibleFrame {
      panel.setContentSize(NSSize(width:min(1400,visible.width*0.94),height:min(840,visible.height*0.90)))
    }
    let host=NSView();StudioTheme.surface(host);panel.contentView=host
    let heading=NSTextField(labelWithString:title);heading.font = .systemFont(ofSize:14,weight:.semibold)
    summary.font = .systemFont(ofSize:11);summary.textColor = .secondaryLabelColor
    let top=NSStackView(views:[heading,summary,tabs]);top.orientation = .vertical;top.alignment = .leading;top.spacing=8
    top.edgeInsets=NSEdgeInsets(top:16,left:18,bottom:12,right:18)
    tabs.selectedSegment=0;tabs.target=self;tabs.action=#selector(changeTab)
    let diff:NSView
    if ignoringSQLWhitespace {
      // DDL migration previews share the same token ranges, aligned physical
      // rows and exact-source copy mapping as the comparison's lower panes.
      let preview=SQLInlineDiffView(frame:.zero);inlinePreview=preview
      preview.leftText.setAccessibilityLabel(leftTitle+" SQL farkları")
      preview.rightText.setAccessibilityLabel(rightTitle+" SQL farkları")
      let captions=NSStackView(views:(editedOnLeft ? [rightTitle,leftTitle]:[leftTitle,rightTitle]).map {title in
        let caption=NSTextField(labelWithString:title);caption.font = .systemFont(ofSize:12,weight:.semibold)
        return caption
      })
      captions.distribution = .fillEqually;captions.spacing=1;captions.edgeInsets=NSEdgeInsets(top:10,left:12,bottom:8,right:12)
      let column=NSStackView(views:[captions,preview]);column.orientation = .vertical;column.spacing=0
      for view in [captions,preview] {view.widthAnchor.constraint(equalTo:column.widthAnchor).isActive=true}
      diff=column
    } else {
      split.isVertical=true;split.dividerStyle = .thin
      let panes=editedOnLeft ? [(right,rightTitle),(left,leftTitle)]:[(left,leftTitle),(right,rightTitle)]
      for (scroll,label) in panes {
        configure(scroll,text:"")
        let caption=NSTextField(labelWithString:label);caption.font = .systemFont(ofSize:12,weight:.semibold)
        let column=NSStackView(views:[caption,scroll]);column.orientation = .vertical;column.spacing=8;column.edgeInsets=NSEdgeInsets(top:10,left:12,bottom:10,right:12)
        scroll.widthAnchor.constraint(equalTo:column.widthAnchor,constant:-24).isActive=true
        split.addArrangedSubview(column)
      }
      diff=split
    }
    diffContent=diff
    let oversized=original.utf16.count>1_000_000 || edited.utf16.count>1_000_000 || (executionSQL?.utf16.count ?? 0)>1_000_000
    let previewOriginal=oversized ? String(original.prefix(200_000)):original
    let previewEdited=oversized ? String(edited.prefix(200_000)):edited
    let execution=executionSQL ?? previewEdited
    configure(script,text:String(execution.prefix(1_000_000)))
    for view in [diff,script] {embed(view,in:body)}
    script.isHidden=true
    let cancel=StudioToolbarButton(symbol:"xmark",label:canApply ? "Vazgeç":"Kapat",tone:.neutral,title:canApply ? "Vazgeç":"Kapat",width:80);cancel.target=self;cancel.action=#selector(closeReview);cancel.keyEquivalent="\u{1b}"
    apply.target=self;apply.action=#selector(submit);apply.bezelStyle = .rounded;apply.isHidden = !canApply;apply.isEnabled=false
    let note=NSTextField(labelWithString:canApply ? "SQL yalnızca Veritabanına Gönder’e bastığınızda gönderilir.":"Bu ekran karşılaştırma içindir; SQL gönderilmez.");note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor
    let footer=NSStackView(views:[note,NSView(),cancel,apply]);footer.edgeInsets=NSEdgeInsets(top:12,left:18,bottom:14,right:18)
    let stack=NSStackView(views:[top,body,footer]);stack.orientation = .vertical;stack.spacing=0
    embed(stack,in:host)
    for view in [top,body,footer] {view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    body.setContentHuggingPriority(.init(1),for:.vertical)
    for scroll in inlinePreview == nil ? [left,right]:[] {
      scroll.contentView.postsBoundsChangedNotifications=true
      observers.append(NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) { [weak self,weak scroll] _ in
        MainActor.assumeIsolated {guard let self,let scroll,!self.syncing else {return};self.syncing=true
          let other=scroll === self.left ? self.right:self.left
          other.contentView.scroll(to:NSPoint(x:other.contentView.bounds.minX,y:scroll.contentView.bounds.minY));other.reflectScrolledClipView(other.contentView);self.syncing=false}
      })
    }
    observers.append(NotificationCenter.default.addObserver(forName:StudioTheme.changed,object:nil,queue:.main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshSQLTheme(original:previewOriginal,edited:previewEdited,execution:execution) }
    })
    parent.beginSheet(panel)
    task=Task { [weak self] in
      let comparison=await Task.detached(priority:.userInitiated) {
        ignoringSQLWhitespace ? SQLTextDiff.compareIgnoringSQLWhitespace(previewOriginal,previewEdited):SQLTextDiff.compare(previewOriginal,previewEdited)
      }.value
      guard let self,!Task.isCancelled else {return}
      self.comparison=comparison
      if let inlinePreview {inlinePreview.display(comparison:comparison,original:previewOriginal,edited:previewEdited,changeIndex:-1,editedOnLeft:editedOnLeft)}
      else {render(comparison,to:left,old:true,source:previewOriginal);render(comparison,to:right,old:false,source:previewEdited)}
      summary.stringValue="−\(comparison.removed) kaldırılan  ·  +\(comparison.added) eklenen satır"+(comparison.simplified ? "  ·  Büyük değişiklik için blok karşılaştırması":"")
      let truncated=oversized || comparison.lines.count>10_000 || inlinePreview?.truncated == true
      if truncated {summary.stringValue="Büyük tanım: kısmi önizleme (en çok 10.000 satır). Buradan uygulanamaz; tam SQL sorgu sekmesindedir."}
      apply.isEnabled=canApply && !truncated && (executionSQL != nil || (comparison.added+comparison.removed)>0)
      if inlinePreview == nil {split.setPosition(split.bounds.width/2,ofDividerAt:0)}
    }
  }
  private func embed(_ child:NSView,in parent:NSView) {
    parent.addSubview(child);child.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:parent.leadingAnchor),child.trailingAnchor.constraint(equalTo:parent.trailingAnchor),child.topAnchor.constraint(equalTo:parent.topAnchor),child.bottomAnchor.constraint(equalTo:parent.bottomAnchor)])
  }
  private func configure(_ scroll:NSScrollView,text:String) {
    let view=NSTextView(usingTextLayoutManager:true);view.identifier = .init("sqlSourcePreview");view.isEditable=false;view.isSelectable=true;view.font=StudioTheme.codeFont
    view.backgroundColor=StudioTheme.editorCanvas;view.textColor=StudioTheme.editorText;view.textContentStorage?.textStorage?.setAttributedString(SQLSourceHighlighting.attributed(text));view.textContainerInset=NSSize(width:12,height:8)
    view.isVerticallyResizable=true;view.isHorizontallyResizable=true;view.autoresizingMask=[]
    view.textContainer?.widthTracksTextView=false;view.textContainer?.containerSize=NSSize(width:100_000,height:CGFloat.greatestFiniteMagnitude)
    scroll.documentView=view;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
    size(view,in:scroll,text:text)
  }
  private func size(_ view:NSTextView,in scroll:NSScrollView,text:String) {
    let lines=text.components(separatedBy:"\n")
    let width=(lines.map {($0 as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width}.max() ?? 0)+32
    view.textContainer?.containerSize=NSSize(width:max(490,width),height:CGFloat.greatestFiniteMagnitude)
    view.setFrameSize(NSSize(width:max(490,width),height:max(450,CGFloat(lines.count)*20+32)))
    let style=EditorController.codeParagraph()
    view.defaultParagraphStyle=style
    view.textContentStorage?.textStorage?.addAttribute(.paragraphStyle,value:style,range:NSRange(location:0,length:(view.string as NSString).length))
  }
  private func refreshSQLTheme(original:String,edited:String,execution:String) {
    for scroll in [left,right,script] {
      (scroll.documentView as? NSTextView)?.backgroundColor=StudioTheme.editorCanvas
    }
    if inlinePreview == nil,let comparison {
      render(comparison,to:left,old:true,source:original,revealChange:false)
      render(comparison,to:right,old:false,source:edited,revealChange:false)
    }
    if let view=script.documentView as? NSTextView {
      let selection=view.selectedRange(),viewport=script.contentView.bounds.origin
      view.textContentStorage?.textStorage?.setAttributedString(SQLSourceHighlighting.attributed(execution))
      size(view,in:script,text:execution)
      view.setSelectedRange(selection);script.contentView.scroll(to:viewport);script.reflectScrolledClipView(script.contentView)
    }
  }
  private func render(_ comparison:SQLTextDiff.Comparison,to scroll:NSScrollView,old:Bool,source:String,revealChange:Bool=true) {
    guard let view=scroll.documentView as? NSTextView else {return}
    let selection=view.selectedRange(),viewport=scroll.contentView.bounds.origin
    let attributed=NSMutableAttributedString(string:"")
    let colored=SQLSourceHighlighting.attributed(source)
    var offsets:[Int]=[],offset=0
    for line in source.components(separatedBy:"\n") {offsets.append(offset);offset += line.utf16.count+1}
    var firstChange:NSRange?
    for row in comparison.lines.prefix(10_000) {
      let number=old ? row.oldNumber:row.newNumber,value=old ? row.old:row.new
      let prefix=number.map {String(format:"%5d  ",$0)} ?? "       "
      let line=NSMutableAttributedString(string:prefix,attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.lineNumber])
      if let value,let number,offsets.indices.contains(number-1) {
        line.append(colored.attributedSubstring(from:NSRange(location:offsets[number-1],length:value.utf16.count)))
      }
      line.append(NSAttributedString(string:"\n",attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.editorText]))
      let start=attributed.length;attributed.append(line)
      if row.changed {
        attributed.addAttribute(.backgroundColor,value:(value == nil ? StudioTheme.panel:old ? StudioTheme.color(0xFCE5E5,0x502D36):StudioTheme.color(0xE3F3EA,0x254B3A)),range:NSRange(location:start,length:line.length))
        if let value {
          let a=Array(value.utf16),b=Array(((old ? row.new:row.old) ?? "").utf16)
          var prefixCount=0,suffixCount=0
          while prefixCount<min(a.count,b.count),a[prefixCount] == b[prefixCount] {prefixCount+=1}
          while suffixCount<min(a.count,b.count)-prefixCount,a[a.count-1-suffixCount] == b[b.count-1-suffixCount] {suffixCount+=1}
          // Keep UTF-16 ranges on composed-character boundaries (including emoji).
          let raw=NSRange(location:prefixCount,length:a.count-prefixCount-suffixCount)
          let changed=raw.length>0 ? (value as NSString).rangeOfComposedCharacterSequences(for:raw):raw
          let range=NSRange(location:start+prefix.utf16.count+changed.location,length:changed.length)
          if range.length>0 {attributed.addAttribute(.backgroundColor,value:old ? StudioTheme.color(0xF2BABA,0x784150):StudioTheme.color(0xACE0C4,0x3B7154),range:range)}
          if firstChange == nil {firstChange=range}
        }
      }
    }
    view.textContentStorage?.textStorage?.setAttributedString(attributed);size(view,in:scroll,text:attributed.string)
    if revealChange,let firstChange {view.scrollRangeToVisible(firstChange)}
    // Start at the line beginning: jumping to an inline change can otherwise hide
    // the object name and the first half of a long SQL line.
    if revealChange {scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.contentView.bounds.minY))}
    else {view.setSelectedRange(selection);scroll.contentView.scroll(to:viewport)}
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  @objc private func changeTab() {diffContent?.isHidden=tabs.selectedSegment != 0;script.isHidden=tabs.selectedSegment == 0}
  @objc private func submit() {guard apply.isEnabled else {return};let action=approved;dismiss();action?()}
  @objc private func closeReview() {dismiss()}
  private func dismiss() {
    task?.cancel();for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]
    panel.sheetParent?.endSheet(panel);panel.orderOut(nil);finished?();finished=nil;approved=nil
  }
  func windowShouldClose(_ sender:NSWindow) -> Bool {dismiss();return false}
}

