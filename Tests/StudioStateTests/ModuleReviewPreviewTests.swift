import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ModuleReviewPreviewTests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  private func parent()->NSWindow {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    return window
  }
  private func ready(_ summary:NSTextField) async throws {
    let deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while summary.stringValue=="Farklar hazırlanıyor…",ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(20))}
    #expect(summary.stringValue != "Farklar hazırlanıyor…")
  }
  private func controls(_ window:NSWindow) throws -> (NSView,NSTextField,NSButton,NSButton) {
    let content=try #require(window.attachedSheet?.contentView),children=descendants(content)
    let summary=try #require(children.compactMap {$0 as? NSTextField}.first {$0.stringValue=="Farklar hazırlanıyor…"})
    let buttons=children.compactMap {$0 as? NSButton}
    return (content,summary,try #require(buttons.first {$0.title=="Veritabanına Gönder"}),try #require(buttons.first {$0.title=="Vazgeç"}))
  }
  @Test func ddlPreviewUsesSemanticRangesForLongShiftedRoutineAndRetainsExactExecutionAndCopy() async throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    StudioTheme.apply("light")
    let window=parent()
    let rows=Array(repeating:"    SELECT 1;",count:1500)
    var changed=rows;changed[10]="    SELECT 2;";changed[1480]="    SELECT 3;"
    changed[5]="\nSELECT\n    1;";changed[1475]="\nSELECT\n    1;"
    let original="CREATE PROCEDURE dbo.p AS\nBEGIN\n"+rows.joined(separator:"\n")+"\nEND;"
    let edited="CREATE PROCEDURE dbo.p AS\r\nBEGIN\r\n\r\n"+changed.map {$0+"  "}.joined(separator:"\r\n")+"\r\nEND;"
    let execution="SET ANSI_NULLS OFF;\r\nGO\r\n"+edited.replacingOccurrences(of:"CREATE PROCEDURE",with:"ALTER PROCEDURE")
    var approved=0
    let review=ModuleReviewController(parent:window,title:"Source → Target / dbo.p",original:original,edited:edited,canApply:true,leftTitle:"TargetDB",rightTitle:"SourceDB",executionSQL:execution,ignoringSQLWhitespace:true,editedOnLeft:true,approved:{approved+=1},finished:{})
    let (content,summary,submit,cancel)=try controls(window)
    defer {cancel.performClick(nil);window.close();withExtendedLifetime(review) {}}
    try await ready(summary)
    content.layoutSubtreeIfNeeded()
    let preview=try #require(descendants(content).compactMap {$0 as? SQLInlineDiffView}.first)
    let sourceTitle=try #require(descendants(content).compactMap {$0 as? NSTextField}.first {$0.stringValue=="SourceDB"})
    let targetTitle=try #require(descendants(content).compactMap {$0 as? NSTextField}.first {$0.stringValue=="TargetDB"})
    #expect(content.convert(preview.right.bounds,from:preview.right).minX<content.convert(preview.left.bounds,from:preview.left).minX)
    #expect(content.convert(sourceTitle.bounds,from:sourceTitle).minX<content.convert(targetTitle.bounds,from:targetTitle).minX)
    #expect(preview.changeRows.count==2 && !preview.truncated)
    #expect(summary.stringValue=="−2 kaldırılan  ·  +2 eklenen satır")
    #expect(Data(preview.leftText.selectedSQL(in:NSRange(location:0,length:preview.leftText.string.utf16.count)).utf8)==Data(original.utf8))
    #expect(Data(preview.rightText.selectedSQL(in:NSRange(location:0,length:preview.rightText.string.utf16.count)).utf8)==Data(edited.utf8))
    #expect(!preview.leftText.string.contains("\r") && !preview.rightText.string.contains("\r"))
    for text in [preview.leftText,preview.rightText] {
      let storage=try #require(text.textContentStorage?.textStorage)
      let middle=(storage.string as NSString).range(of:"SELECT 1;",options:[],range:NSRange(location:storage.length/2,length:storage.length-storage.length/2))
      #expect(middle.location != NSNotFound)
      #expect(storage.attribute(.backgroundColor,at:middle.location,effectiveRange:nil)==nil)
      #expect(storage.attribute(.foregroundColor,at:middle.location,effectiveRange:nil) as? NSColor==StudioTheme.syntax(.keyword))
    }
    let script=try #require(descendants(content).compactMap {$0 as? NSTextView}.first {$0 !== preview.leftText && $0 !== preview.rightText})
    #expect(Data(script.string.utf8)==Data(execution.utf8))
    #expect(submit.isEnabled && approved==0)
    submit.performClick(nil)
    #expect(approved==1 && window.attachedSheet==nil)
  }
  @Test func ordinaryModuleReviewRetainsExactWhitespacePolicyByDefault() async throws {
    let window=parent(),original="ALTER PROC dbo.p AS SELECT 1;",edited="ALTER PROC dbo.p AS  SELECT 1;"
    var approved=0
    let review=ModuleReviewController(parent:window,title:"Module",original:original,edited:edited,canApply:true,approved:{approved+=1},finished:{})
    let (content,summary,submit,cancel)=try controls(window)
    defer {cancel.performClick(nil);window.close();withExtendedLifetime(review) {}}
    try await ready(summary)
    #expect(descendants(content).allSatisfy {!($0 is SQLInlineDiffView)})
    #expect(summary.stringValue=="−1 kaldırılan  ·  +1 eklenen satır")
    #expect(submit.isEnabled && approved==0)
  }
  @Test func exactDDLReviewPlacesSourceAndItsCaptionOnLeftAndTargetOnRight() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    StudioTheme.apply("light")
    let window=parent(),original="CREATE TABLE dbo.Target (ID int);",edited="CREATE TABLE dbo.Source (ID bigint);"
    let execution="ALTER TABLE dbo.Target ALTER COLUMN ID bigint;"
    let review=ModuleReviewController(parent:window,title:"Table transfer",original:original,edited:edited,canApply:true,leftTitle:"TargetDB",rightTitle:"SourceDB",executionSQL:execution,editedOnLeft:true,approved:{},finished:{})
    let (content,summary,submit,cancel)=try controls(window)
    defer {cancel.performClick(nil);window.close();withExtendedLifetime(review) {}}
    try await ready(summary)
    content.layoutSubtreeIfNeeded()
    #expect(descendants(content).allSatisfy {!($0 is SQLInlineDiffView)})
    let texts=descendants(content).compactMap {$0 as? NSTextView}
    let source=try #require(texts.first {$0.string.contains("dbo.Source")})
    let target=try #require(texts.first {$0.string.contains("ID int")})
    #expect(content.convert(source.bounds,from:source).minX<content.convert(target.bounds,from:target).minX)
    for (text,title) in [(source,"SourceDB"),(target,"TargetDB")] {
      let column=try #require(text.enclosingScrollView?.superview as? NSStackView)
      #expect(column.arrangedSubviews.compactMap {$0 as? NSTextField}.first?.stringValue==title)
    }
    let added=try #require(source.textContentStorage?.textStorage),removed=try #require(target.textContentStorage?.textStorage)
    #expect(added.attribute(.backgroundColor,at:0,effectiveRange:nil) as? NSColor==StudioTheme.color(0xE3F3EA,0x254B3A))
    #expect(removed.attribute(.backgroundColor,at:0,effectiveRange:nil) as? NSColor==StudioTheme.color(0xFCE5E5,0x502D36))
    #expect(texts.contains {$0.string==execution} && submit.isEnabled)
  }
  @Test func ddlMetadataChangeCanBeApprovedWithNoTextChangeAndDoesNotAlterExecutionSQL() async throws {
    let window=parent(),source="CREATE TRIGGER dbo.tr ON dbo.T AFTER INSERT AS SELECT 1;"
    let execution="SET ANSI_NULLS OFF;\r\nGO\r\nDISABLE TRIGGER [dbo].[tr] ON [dbo].[T];"
    var approved=0
    let review=ModuleReviewController(parent:window,title:"Trigger state",original:source,edited:source,canApply:true,executionSQL:execution,ignoringSQLWhitespace:true,approved:{approved+=1},finished:{})
    let (content,summary,submit,cancel)=try controls(window)
    defer {cancel.performClick(nil);window.close();withExtendedLifetime(review) {}}
    try await ready(summary)
    let preview=try #require(descendants(content).compactMap {$0 as? SQLInlineDiffView}.first)
    #expect(preview.changeRows.isEmpty && summary.stringValue=="−0 kaldırılan  ·  +0 eklenen satır")
    let script=try #require(descendants(content).compactMap {$0 as? NSTextView}.first {$0 !== preview.leftText && $0 !== preview.rightText})
    #expect(Data(script.string.utf8)==Data(execution.utf8))
    #expect(submit.isEnabled && approved==0)
  }
  @Test func incompleteDDLPreviewKeepsSubmissionDisabled() async throws {
    let window=parent(),source=Array(repeating:"SELECT 1;",count:SQLInlineDiffView.maximumRows+1).joined(separator:"\n")
    var approved=0
    let review=ModuleReviewController(parent:window,title:"Large DDL",original:source,edited:source,canApply:true,executionSQL:source,ignoringSQLWhitespace:true,approved:{approved+=1},finished:{})
    let (content,summary,submit,cancel)=try controls(window)
    defer {cancel.performClick(nil);window.close();withExtendedLifetime(review) {}}
    try await ready(summary)
    let preview=try #require(descendants(content).compactMap {$0 as? SQLInlineDiffView}.first)
    #expect(preview.truncated && preview.renderedRows==SQLInlineDiffView.maximumRows)
    #expect(summary.stringValue.contains("kısmi önizleme") && !submit.isEnabled)
    submit.performClick(nil)
    #expect(approved==0 && window.attachedSheet != nil)
  }
}
