import AppKit
import CoreText
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SQLDiffPreviewTests {
  private func preview(_ original: String, _ edited: String, index: Int = -1, width: CGFloat = 900, height: CGFloat = 240, ignoringWhitespace:Bool=false, editedOnLeft:Bool=false) -> SQLInlineDiffView {
    _=NSApplication.shared
    let view=SQLInlineDiffView(frame:NSRect(x:0,y:0,width:width,height:height))
    let comparison=ignoringWhitespace ? SQLTextDiff.compareIgnoringSQLWhitespace(original,edited):SQLTextDiff.compare(original,edited)
    view.display(comparison:comparison,original:original,edited:edited,changeIndex:index,editedOnLeft:editedOnLeft)
    view.layoutSubtreeIfNeeded()
    return view
  }
  private func hex(_ color: NSColor?) -> UInt32? {
    guard let color=color?.usingColorSpace(.sRGB) else {return nil}
    return UInt32((color.redComponent*255).rounded())<<16 | UInt32((color.greenComponent*255).rounded())<<8 | UInt32((color.blueComponent*255).rounded())
  }
  @Test func insertionDeletionRowsStayAlignedAndCopiedSQLHasNoRulerOrSyntheticRows() throws {
    let original="SELECT 1;\nSELECT 2;",edited="SELECT 1;\nSELECT N'Yeni 🥐';\nSELECT 2;"
    let view=preview(original,edited)
    #expect(view.leftText.textLayoutManager != nil && view.rightText.textLayoutManager != nil)
    #expect(view.renderedRows==3 && !view.truncated)
    #expect(view.leftText.string=="SELECT 1;\n\nSELECT 2;\n")
    #expect(view.rightText.string==edited+"\n")
    #expect(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count))==original)
    #expect(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count))==edited)
    #expect(view.leftRuler.ruleThickness==36)
    #expect(view.changeRows==[1])
    let reversed=preview(edited,original)
    #expect(reversed.rightText.string==view.leftText.string)
    #expect(reversed.rightText.selectedSQL(in:NSRange(location:0,length:reversed.rightText.string.utf16.count))==original)
  }
  @Test func sourceOnLeftSwapsPhysicalPanesAndRulersWithoutReversingDiffCopyOrViewport() throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    StudioTheme.apply("light")
    let rows=(0..<140).map {"SELECT \($0), ["+String(repeating:"LongName",count:20)+"];"}
    var changed=rows
    changed[80]=changed[80].replacingOccurrences(of:"SELECT 80,",with:"SELECT -2,")
    changed.insert("PRINT N'Yeni 🥐';",at:2)
    let original=rows.joined(separator:"\r\n"),edited=changed.joined(separator:"\r\n")
    let comparison=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
    for width in [CGFloat(900),CGFloat(901)] {
      let view=preview(original,edited,width:width,ignoringWhitespace:true,editedOnLeft:true)
      #expect(view.rightRuler.frame.minX==0 && view.leftRuler.frame.minX>view.right.frame.maxX)
      let accessibilityOrder=try #require(view.accessibilityChildren() as? [NSView])
      #expect(accessibilityOrder.count==2 && accessibilityOrder.first===view.right && accessibilityOrder.last===view.left)
      #expect(view.left.frame.minX==view.leftRuler.frame.maxX && view.right.frame.minX==view.rightRuler.frame.maxX)
      let originalRuler=view.leftRuler
      let editedRuler=view.rightRuler
      #expect(view.convert(editedRuler.bounds,from:editedRuler).minX<view.convert(originalRuler.bounds,from:originalRuler).minX)
      #expect(originalRuler.numbers[2]==nil && editedRuler.numbers[2]==3)
      #expect(comparison.added==2)
      #expect(comparison.removed==1)
      #expect(view.changeRows==[2,81])
      for (text,source) in [(view.leftText,original),(view.rightText,edited)] {
        #expect(Data(text.selectedSQL(in:NSRange(location:0,length:text.string.utf16.count)).utf8)==Data(source.utf8))
      }
      let old=try #require(view.leftText.textContentStorage?.textStorage),new=try #require(view.rightText.textContentStorage?.textStorage)
      let removed=(old.string as NSString).range(of:"SELECT 80,").location
      let added=(new.string as NSString).range(of:"Yeni 🥐").location
      #expect(hex(old.attribute(.backgroundColor,at:removed,effectiveRange:nil) as? NSColor)==0xFCE5E5)
      #expect(hex(new.attribute(.backgroundColor,at:added,effectiveRange:nil) as? NSColor)==0xACE0C4)
      view.left.contentView.scroll(to:NSPoint(x:44,y:1200))
      view.right.contentView.scroll(to:NSPoint(x:88,y:1300))
      #expect(abs(view.left.contentView.bounds.minY-1300)<1)
      let selection=NSRange(location:20,length:8)
      view.rightText.setSelectedRange(selection)
      let origins=[view.left.contentView.bounds.origin,view.right.contentView.bounds.origin],renders=view.renderCount
      view.display(comparison:comparison,original:original,edited:edited,changeIndex:-1)
      view.layoutSubtreeIfNeeded()
      #expect(view.leftRuler.frame.minX==0 && view.right.frame.minX>view.left.frame.maxX)
      let defaultAccessibilityOrder=try #require(view.accessibilityChildren() as? [NSView])
      #expect(defaultAccessibilityOrder.first===view.left && defaultAccessibilityOrder.last===view.right)
      #expect(view.renderCount==renders && view.rightText.selectedRange()==selection)
      // Native clip bounds round to backing pixels when a half-point pane origin moves.
      let pixel=1/max(1,view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
      for (scroll,expected) in zip([view.left,view.right],origins) {
        let actual=scroll.contentView.bounds.origin
        #expect(abs(actual.x-expected.x)<=pixel+0.001,"Horizontal clip origin \(actual.x), expected \(expected.x), pixel \(pixel)")
        #expect(abs(actual.y-expected.y)<=pixel+0.001,"Vertical clip origin \(actual.y), expected \(expected.y), pixel \(pixel)")
      }
      #expect(abs(view.left.contentView.bounds.minY-view.right.contentView.bounds.minY)<=pixel+0.001)
      #expect(hex(old.attribute(.backgroundColor,at:removed,effectiveRange:nil) as? NSColor)==0xFCE5E5)
      #expect(hex(new.attribute(.backgroundColor,at:added,effectiveRange:nil) as? NSColor)==0xACE0C4)
      view.display(comparison:comparison,original:original,edited:edited,changeIndex:1,editedOnLeft:true)
      view.layoutSubtreeIfNeeded()
      #expect(view.rightRuler.frame.minX==0 && view.left.contentView.bounds.minY>1500)
      #expect(abs(view.left.contentView.bounds.minY-view.right.contentView.bounds.minY)<1)
      #expect(view.renderCount==renders)
    }
  }
  @Test func viewWhitespaceOnlyRowsStayNeutralAndAddedProjectionKeepsExactCopiedSQL() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    StudioTheme.apply("light")
    let original="CREATE VIEW dbo.v AS   \r\nSELECT    A.ID,  -- Müşteri kodu  \r\n    C.InvoiceDate,   \r\n    A.Amount   -- Fatura tutarı  \r\nFROM dbo.T A;  "
    let edited="CREATE VIEW dbo.v AS     \nSELECT A.ID, -- Müşteri kodu    \n\tC.InvoiceDate,\n\tC.INCKEYNO AS ExternalOrderId,\n\tA.Amount -- Fatura tutarı    \nFROM dbo.T A;    "
    let view=preview(original,edited,ignoringWhitespace:true)
    #expect(view.renderedRows==6 && view.changeRows==[3])
    #expect(!view.leftText.string.contains("\r") && !view.rightText.string.contains("\r"))
    #expect(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count))==original)
    #expect(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count))==edited)
    let old=try #require(view.leftText.textContentStorage?.textStorage),new=try #require(view.rightText.textContentStorage?.textStorage)
    for (storage,needle) in [(old,"SELECT"),(new,"SELECT"),(old,"Amount"),(new,"Amount")] {
      #expect(storage.attribute(.backgroundColor,at:(storage.string as NSString).range(of:needle).location,effectiveRange:nil)==nil)
    }
    let added=(new.string as NSString).range(of:"ExternalOrderId")
    #expect(hex(new.attribute(.backgroundColor,at:added.location,effectiveRange:nil) as? NSColor)==0xACE0C4)
    let indentation=(new.string as NSString).range(of:"\tC.INCKEYNO")
    #expect(hex(new.attribute(.backgroundColor,at:indentation.location,effectiveRange:nil) as? NSColor)==0xE3F3EA)
    let oldRuler=view.leftRuler,newRuler=view.rightRuler
    #expect(oldRuler.numbers==[1,2,3,nil,4,5] && newRuler.numbers==[1,2,3,4,5,6])
    let select=(view.leftText.string as NSString).range(of:"SELECT    A.ID,  -- Müşteri kodu  \n")
    #expect(view.leftText.selectedSQL(in:select)=="SELECT    A.ID,  -- Müşteri kodu  \r\n")
  }
  @Test func viewCRLineDelimitersAndProtectedBlankLinesRenderAndCopyWithStableGeometry() throws {
    let original="CREATE VIEW dbo.v AS\rSELECT N'Bir\r\rİki' AS [Name],\r    1 AS [Count];\r"
    let edited="CREATE VIEW dbo.v AS\rSELECT N'Bir\r\rİki' AS [Name],\r    2 AS [Count];\r"
    let view=preview(original,edited,height:300,ignoringWhitespace:true)
    #expect(view.renderedRows==6 && view.changeRows==[4])
    #expect(view.leftText.string.contains("SELECT N'Bir\n\nİki' AS [Name],\n    1 AS [Count];"))
    #expect(!view.leftText.string.contains("\r"))
    #expect(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count))==original)
    #expect(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count))==edited)
    for row in [0,2,4,5] {
      let geometry=try #require(view.leftText.lineGeometry(forRow:row))
      #expect(abs(geometry.rect.minY-(8+CGFloat(row)*20))<0.01)
    }
  }
  @Test func changingDiffPolicyForSameSQLRefreshesStylesWithoutReformattingSources() {
    let original="SELECT  1;",edited=" SELECT 1;  "
    let view=preview(original,edited)
    #expect(view.changeRows==[0])
    let count=view.renderCount
    view.display(comparison:SQLTextDiff.compareIgnoringSQLWhitespace(original,edited),original:original,edited:edited,changeIndex:-1)
    #expect(view.renderCount==count+1 && view.changeRows.isEmpty)
    #expect(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count))==original)
    #expect(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count))==edited)
  }
  @Test func canonicallyEquivalentLiteralUpdatesRefreshNativeColorAndByteExactCopy() throws {
    let original="SELECT N'base';",first="SELECT N'Å';",second="SELECT N'Å';"
    let view=preview(original,first,ignoringWhitespace:true),count=view.renderCount
    let comparison=SQLTextDiff.compareIgnoringSQLWhitespace(original,second)
    view.display(comparison:comparison,original:original,edited:second,changeIndex:-1)
    #expect(view.renderCount==count+1 && view.changeRows==[0])
    let copied=view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count))
    #expect(Data(copied.utf8)==Data(second.utf8))
    let storage=try #require(view.rightText.textContentStorage?.textStorage)
    #expect(storage.attribute(.backgroundColor,at:(storage.string as NSString).range(of:"Å").location,effectiveRange:nil) != nil)
    let canonical=SQLTextDiff.compareIgnoringSQLWhitespace("SELECT N'é';","SELECT N'e\u{301}';")
    #expect(canonical.lines.first?.changed==true)
  }
  @Test func longRepeatedProcedureKeepsTwoChangeGroupsSyntaxColorsAndExactCopyAfterShift() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    StudioTheme.apply("light")
    let rows=Array(repeating:"    SELECT 1;",count:1500)
    var modified=rows;modified[10]="    SELECT 2;";modified[1480]="    SELECT 3;"
    let original="CREATE PROCEDURE dbo.p AS\nBEGIN\n"+rows.joined(separator:"\n")+"\nEND;"
    let edited="CREATE PROCEDURE dbo.p AS\r\nBEGIN\r\n\r\n"+modified.map {$0+"  "}.joined(separator:"\r\n")+"\r\nEND;"
    let comparison=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited),view=preview(original,edited,ignoringWhitespace:true)
    #expect(!comparison.simplified && comparison.added==2 && comparison.removed==2)
    #expect(view.changeRows.count==2 && view.renderedRows==1504 && !view.truncated)
    #expect(Data(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count)).utf8)==Data(original.utf8))
    #expect(Data(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count)).utf8)==Data(edited.utf8))
    for text in [view.leftText,view.rightText] {
      let storage=try #require(text.textContentStorage?.textStorage)
      let middle=(storage.string as NSString).range(of:"SELECT 1;",options:[],range:NSRange(location:storage.length/2,length:storage.length-storage.length/2))
      #expect(storage.attribute(.backgroundColor,at:middle.location,effectiveRange:nil)==nil)
      #expect(hex(storage.attribute(.foregroundColor,at:middle.location,effectiveRange:nil) as? NSColor)==0x0000FF)
    }
    #expect(comparison.lines.filter(\.changed).allSatisfy {$0.old != $0.new})
    view.display(comparison:comparison,original:original,edited:edited,changeIndex:1)
    #expect(view.left.contentView.bounds.minY>20_000)
  }
  @Test func routineReflowAndBlankRowsDoNotCreateExtraNativeChanges() throws {
    let rows=Array(repeating:"SELECT 1;",count:1500)
    var modified=rows;modified[10]="SELECT 2;";modified[1480]="SELECT 3;"
    modified[5]="\nSELECT\n    1;";modified[1475]="\nSELECT\n    1;"
    let original=rows.joined(separator:"\n"),edited=modified.joined(separator:"\r\n")
    let comparison=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited),view=preview(original,edited,ignoringWhitespace:true)
    #expect(!comparison.simplified && comparison.added==2 && comparison.removed==2)
    #expect(view.changeRows.count==2 && comparison.lines.filter(\.changed).count==2)
    #expect(comparison.lines.filter(\.changed).allSatisfy {$0.old != $0.new})
    #expect(Data(view.leftText.selectedSQL(in:NSRange(location:0,length:view.leftText.string.utf16.count)).utf8)==Data(original.utf8))
    #expect(Data(view.rightText.selectedSQL(in:NSRange(location:0,length:view.rightText.string.utf16.count)).utf8)==Data(edited.utf8))
  }
  @Test func lightAndDarkSSMSColorsCoexistWithLineAndComposedCharacterDiffHighlights() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    let original="-- heading\nSELECT N'old 🥐', 1;",edited="-- heading\nSELECT N'new 🍎', 1;"
    StudioTheme.apply("light")
    let view=preview(original,edited)
    for (theme,keyword,stringColor,lineColor,inlineColor) in [
      ("light",UInt32(0x0000FF),UInt32(0xFF0000),UInt32(0xFCE5E5),UInt32(0xF2BABA)),
      ("dark",UInt32(0x6CA0FF),UInt32(0xFF8080),UInt32(0x502D36),UInt32(0x784150))
    ] {
      StudioTheme.apply(theme)
      let storage=try #require(view.leftText.textContentStorage?.textStorage)
      let keywordOffset=(storage.string as NSString).range(of:"SELECT").location
      let literal=(storage.string as NSString).range(of:"old 🥐")
      #expect(hex(storage.attribute(.foregroundColor,at:keywordOffset,effectiveRange:nil) as? NSColor)==keyword)
      #expect(hex(storage.attribute(.foregroundColor,at:literal.location,effectiveRange:nil) as? NSColor)==stringColor)
      #expect(hex(storage.attribute(.backgroundColor,at:keywordOffset,effectiveRange:nil) as? NSColor)==lineColor)
      #expect(hex(storage.attribute(.backgroundColor,at:literal.location,effectiveRange:nil) as? NSColor)==inlineColor)
      let emoji=(storage.string as NSString).range(of:"🥐")
      #expect(hex(storage.attribute(.backgroundColor,at:emoji.location,effectiveRange:nil) as? NSColor)==inlineColor)
      #expect(hex(storage.attribute(.backgroundColor,at:emoji.location+1,effectiveRange:nil) as? NSColor)==inlineColor)
      let target=try #require(view.rightText.textContentStorage?.textStorage)
      let new=(target.string as NSString).range(of:"new 🍎").location
      #expect(hex(target.attribute(.backgroundColor,at:new,effectiveRange:nil) as? NSColor)==(theme=="light" ? 0xACE0C4 : 0x3B7154))
    }
  }
  @Test func nativeScrollSyncNavigationAndThemeKeepIndependentHorizontalViewportAndSelection() throws {
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    let lines=(0..<250).map {"SELECT \($0), ["+String(repeating:"LongName",count:25)+"];"}
    var changed=lines;changed[80]+=" -- first";changed[81]+=" -- adjacent";changed[180]+=" -- second"
    let original=lines.joined(separator:"\n"),edited=changed.joined(separator:"\n")
    let comparison=SQLTextDiff.compare(original,edited),view=preview(original,edited)
    #expect(SQLInlineDiffView.changeRows(in:comparison)==[80,180])
    #expect(view.left.contentView.bounds.minY>1400)
    #expect(abs(view.left.contentView.bounds.minY-view.right.contentView.bounds.minY)<1)
    view.left.contentView.scroll(to:NSPoint(x:44,y:2000));view.left.reflectScrolledClipView(view.left.contentView)
    #expect(abs(view.right.contentView.bounds.minY-2000)<1)
    #expect(view.right.contentView.bounds.minX == -view.right.contentView.contentInsets.left)
    view.right.contentView.scroll(to:NSPoint(x:88,y:2200));view.right.reflectScrolledClipView(view.right.contentView)
    #expect(abs(view.left.contentView.bounds.minY-2200)<1)
    #expect(view.left.contentView.bounds.minX==44)
    let selection=NSRange(location:10,length:12);view.leftText.setSelectedRange(selection)
    let leftOrigin=view.left.contentView.bounds.origin,rightOrigin=view.right.contentView.bounds.origin
    StudioTheme.apply(StudioTheme.dark ? "light":"dark")
    #expect(view.leftText.selectedRange()==selection)
    #expect(view.left.contentView.bounds.origin==leftOrigin && view.right.contentView.bounds.origin==rightOrigin)
    let count=view.renderCount
    view.display(comparison:comparison,original:original,edited:edited,changeIndex:-1)
    #expect(view.renderCount==count && view.left.contentView.bounds.origin==leftOrigin)
    view.display(comparison:comparison,original:original,edited:edited,changeIndex:1)
    #expect(view.left.contentView.bounds.minY>3500 && view.left.contentView.bounds.minX == -view.left.contentView.contentInsets.left)
    view.left.contentView.scroll(to:NSPoint(x:0,y:2400))
    view.display(comparison:comparison,original:original,edited:edited,changeIndex:1)
    #expect(view.left.contentView.bounds.minY==2400 && view.renderCount==count)
    let short=(0..<100).map {"SELECT \($0);"},long=short.enumerated().map { $0.offset==99 ? $0.element+String(repeating:" -- wider",count:100):$0.element }
    let legacy=preview(short.joined(separator:"\n"),long.joined(separator:"\n"))
    legacy.left.scrollerStyle = .legacy;legacy.right.scrollerStyle = .legacy
    legacy.needsLayout=true;legacy.layoutSubtreeIfNeeded()
    let leftMaximum=legacy.leftText.bounds.height-legacy.left.contentView.bounds.height+legacy.left.contentView.contentInsets.bottom
    let rightMaximum=legacy.rightText.bounds.height-legacy.right.contentView.bounds.height+legacy.right.contentView.contentInsets.bottom
    #expect(abs(leftMaximum-rightMaximum)<1)
    legacy.right.contentView.scroll(to:NSPoint(x:0,y:rightMaximum))
    #expect(abs(legacy.left.contentView.bounds.minY-legacy.right.contentView.bounds.minY)<1)
    let legacyOriginal=short.joined(separator:"\n"),legacyEdited=long.joined(separator:"\n")
    legacy.display(comparison:SQLTextDiff.compare(legacyOriginal,legacyEdited),original:legacyOriginal,edited:legacyEdited,changeIndex:0)
    #expect(abs(legacy.left.contentView.bounds.minY-legacy.right.contentView.bounds.minY)<1)
  }
  @Test func narrowViewportUsesItsOwnSizeAndNewContentClearsPreviousDiffWithoutForcedMinimums() throws {
    let source="SELECT ["+String(repeating:"LongName",count:100)+"];",view=preview(source,source+" -- changed",width:520,height:160)
    #expect(view.left.bounds.width<260 && view.leftText.bounds.width>view.left.contentView.bounds.width)
    let replacement="SELECT 1;"
    view.display(comparison:SQLTextDiff.compare(replacement,replacement),original:replacement,edited:replacement,changeIndex:-1)
    view.layoutSubtreeIfNeeded()
    #expect(view.leftText.string==replacement+"\n" && view.changeRows.isEmpty)
    #expect(view.leftText.bounds.width==view.left.contentView.bounds.width-view.left.contentView.contentInsets.left)
    #expect(view.leftText.bounds.height==view.left.contentView.bounds.height)
    #expect(view.left.contentView.bounds.origin == NSPoint(x:-view.left.contentView.contentInsets.left,y:0))
    #expect(view.fittingSize.width<=520 && view.fittingSize.height<=160)
  }
  @Test func largePreviewHasExplicitRowAndCharacterBudgets() throws {
    let source=Array(repeating:"SELECT 1;",count:10_010).joined(separator:"\n")
    let view=preview(source,source)
    #expect(view.renderedRows==SQLInlineDiffView.maximumRows && view.truncated)
    #expect(view.leftRuler.ruleThickness==51 && view.rightRuler.ruleThickness==51)
    #expect(view.left.contentView.bounds.minX == -view.left.contentView.contentInsets.left)
    let huge=String(repeating:"x",count:SQLInlineDiffView.maximumCharacters+1)
    view.display(comparison:SQLTextDiff.compare(huge,huge),original:huge,edited:huge,changeIndex:-1)
    #expect(view.renderedRows==0 && view.truncated && view.leftText.string.isEmpty)
  }
  @Test func nativeFragmentGeometryKeepsFirstTenthAndFinalRowsWithRulerAndStripeAligned() throws {
    // Match the real app's optional Consolas registration without changing an
    // already registered font or retaining new registration after the test.
    let fontURL=URL(fileURLWithPath:"/Applications/Microsoft Word.app/Contents/Resources/DFonts/Consola.ttf")
    let registered=NSFont(name:"Consolas",size:13)==nil && FileManager.default.fileExists(atPath:fontURL.path)
      ? CTFontManagerRegisterFontsForURL(fontURL as CFURL,.process,nil):false
    defer {if registered {CTFontManagerUnregisterFontsForURL(fontURL as CFURL,.process,nil)}}
    let original=(1...12).map {"SELECT \($0);"}.joined(separator:"\n")
    let edited=original.replacingOccurrences(of:"SELECT 10;",with:"SELECT 10, N'Yeni 🥐';")
    let view=preview(original,edited,height:340)
    #expect(view.clipsToBounds && view.left.clipsToBounds && view.right.clipsToBounds)
    let fonts=[StudioTheme.codeFont,try #require(NSFont(name:"Arial",size:13))]
    for font in fonts {
      for (scroll,text) in [(view.left,view.leftText),(view.right,view.rightText)] {
        let storage=try #require(text.textContentStorage?.textStorage)
        storage.addAttribute(.font,value:font,range:NSRange(location:0,length:storage.length))
        let ruler=scroll === view.left ? view.leftRuler:view.rightRuler
        #expect(ruler.clipsToBounds && text.textLayoutManager?.usesFontLeading==false)
        for row in [0,9,11] {
          let geometry=try #require(text.lineGeometry(forRow:row))
          let background=text.backgroundFrame(forRow:row)
          #expect(abs(geometry.rect.minY-background.minY)<0.01)
          #expect(abs(geometry.rect.height-background.height)<0.01)
          #expect(abs(geometry.rect.minY-(8+CGFloat(row)*20))<0.01)
          let label=try #require(ruler.labelOrigin(forRow:row))
          let labelFont=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular)
          #expect(abs(label.y+labelFont.ascender+scroll.contentView.bounds.minY-geometry.baseline)<0.01)
          #expect(ruler.numbers[row]==row+1)
          #expect(geometry.rect.maxY<=text.bounds.maxY)
        }
      }
    }
  }
}
