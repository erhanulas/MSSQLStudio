import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct HeaderCellLifecycleTests {
  @Test func copiedHeadersSurviveRepeatedResultReplacementPinAndTableTeardown() throws {
    _=NSApplication.shared
    for pass in 0..<40 {
      let copies:[FilterHeaderCell]=try autoreleasepool {
        let grid=ResultController();_=grid.view
        grid.update(Rows(fields:(0..<6).map {Field("Column\($0)",type:3,size:28,scale:8)},values:(0..<20).map {row in (0..<6).map {_ in "\(row).00000000"}}))
        grid.setColumnPinned(2,pinned:true);grid.setColumnPinned(0,pinned:true)
        var copied:[FilterHeaderCell]=[]
        for column in grid.table.tableColumns+grid.frozenTable.tableColumns {
          if let header=column.headerCell as? FilterHeaderCell {
            header.typeDetail="metadata-\(pass)-"+String(repeating:"large type description ",count:32)
            copied.append(try #require(header.copy() as? FilterHeaderCell))
          }
        }
        grid.update(Rows(fields:[Field("Replacement")],values:[["text"]]),generation:pass+1)
        return copied
      }
      #expect(!copies.isEmpty && copies.allSatisfy {$0.typeDetail.hasPrefix("metadata-\(pass)-")})
    }
  }
  @Test func copiedHeaderOwnsHeapStringsAfterOriginalAndColumnAreReleased() throws {
    _=NSApplication.shared
    let copy:FilterHeaderCell=try autoreleasepool {
      let original=FilterHeaderCell(textCell:"Column")
      original.typeDetail=String(repeating:"nvarchar(100) ",count:128)+"END_TYPE"
      original.typeSymbol="symbol-"+UUID().uuidString
      original.active=true;original.pinned=true;original.primaryKey=true
      original.hovered=true;original.navigationTarget=true;original.showsFilter=false;original.ascending=false
      original.alignment = .right;original.font = .systemFont(ofSize:15)
      let column=NSTableColumn(identifier:.init("copy-source"));column.headerCell=original
      let copied=try #require(original.copy() as? FilterHeaderCell)
      #expect(copied !== original)
      return copied
    }
    let churn=(0..<100).map {String(repeating:String($0),count:2000)}
    #expect(!churn.isEmpty && copy.typeDetail.hasSuffix("END_TYPE") && copy.typeSymbol.hasPrefix("symbol-"))
    #expect(copy.active && copy.pinned && copy.primaryKey && copy.hovered && copy.navigationTarget && !copy.showsFilter && copy.ascending==false)
    #expect(copy.stringValue=="Column" && copy.alignment == .right && copy.font?.pointSize==15)
    let second=try #require(copy.copy() as? FilterHeaderCell)
    second.typeDetail="Changed";second.typeSymbol="Changed";second.active=false
    #expect(copy.typeDetail.hasSuffix("END_TYPE") && copy.typeSymbol.hasPrefix("symbol-") && copy.active)
  }
}
