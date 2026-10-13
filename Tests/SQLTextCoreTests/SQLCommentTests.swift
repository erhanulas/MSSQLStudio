import Foundation
import Testing
import SQLTextCore

@Suite struct SQLCommentTests {
  private func apply(_ source:String,_ edit:SQLComments.Edit)->String {(source as NSString).replacingCharacters(in:edit.range,with:edit.replacement)}
  @Test func mixedIndentationCommentsAndCRLFRoundTrip() throws {
    let sql="  SELECT N'😀 İstanbul';\r\n\t-- existing\r\n  \r\nSELECT 2;\r\n"
    let first=try #require(SQLComments.edit(sql,selection:NSRange(location:0,length:sql.utf16.count)))
    let commented=apply(sql,first)
    #expect(commented=="  -- SELECT N'😀 İstanbul';\r\n\t-- -- existing\r\n  \r\n-- SELECT 2;\r\n")
    #expect(SQLComments.isCommented(commented,selection:first.selection))
    let second=try #require(SQLComments.edit(commented,selection:first.selection))
    #expect(apply(commented,second)==sql)
  }
  @Test func selectionEndingAtNextLineStartDoesNotCommentNextLine() throws {
    let sql="SELECT 1;\nSELECT 2;\nSELECT 3;"
    let edit=try #require(SQLComments.edit(sql,selection:NSRange(location:3,length:7)))
    #expect(apply(sql,edit)=="-- SELECT 1;\nSELECT 2;\nSELECT 3;")
    let current=try #require(SQLComments.edit(sql,selection:NSRange(location:13,length:0)))
    #expect(apply(sql,current)=="SELECT 1;\n-- SELECT 2;\nSELECT 3;")
  }
  @Test func explicitUncommentOnlyRemovesExistingLineMarkers() throws {
    let sql="  --SELECT 1;\n  SELECT 2;\n\t-- SELECT 3;"
    let edit=try #require(SQLComments.edit(sql,selection:NSRange(location:0,length:sql.utf16.count),uncomment:true))
    #expect(apply(sql,edit)=="  SELECT 1;\n  SELECT 2;\n\tSELECT 3;")
    #expect(SQLComments.edit("SELECT 1;",selection:NSRange(location:0,length:4),uncomment:true)==nil)
  }
  @Test func emptyWhitespaceAndInvalidRangesAreSafe() {
    for sql in ["", "  \t", "\r\n \r\n"] {#expect(SQLComments.edit(sql,selection:NSRange(location:0,length:sql.utf16.count))==nil)}
    #expect(SQLComments.edit("SELECT",selection:NSRange(location:NSNotFound,length:0))==nil)
    #expect(SQLComments.edit("SELECT",selection:NSRange(location:6,length:1))==nil)
  }
}
