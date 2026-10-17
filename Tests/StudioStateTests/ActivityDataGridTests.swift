import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityDataGridTests {
  private struct Row:Identifiable {let id:Int;let value:String?}
  @Test func nativeSelectionAndNumericFiltersUseResultRulesWithoutChangingSource() async throws {
    _=NSApplication.shared
    let rows=[Row(id:1,value:"1"),Row(id:2,value:"12"),Row(id:3,value:nil)]
    var selected:Int?
    let binding=Binding<Int?>(get:{selected},set:{selected=$0})
    let host=NSHostingView(rootView:ActivityDataGrid(rows:rows,columns:[.init(title:"Value",numeric:true,value:{$0.value})],selection:binding))
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:500,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer {window.close()}
    host.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let table=try #require(children(host).compactMap {$0 as? NSTableView}.first)
    let owner=try #require(table.delegate as? ActivityDataGrid<Row>.Coordinator)
    #expect(table.numberOfRows==3 && table.headerView is FilterHeader)
    table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
    #expect(selected==2)
    var rule=ColumnRule();rule.operation = .atLeast;rule.first="10"
    try owner.setRule(rule,column:0,table:table)
    for _ in 0..<100 where table.numberOfRows != 1 {try await Task.sleep(for:.milliseconds(10))}
    #expect(table.numberOfRows==1 && selected==2)
    #expect((table.tableColumns[0].headerCell as? FilterHeaderCell)?.active==true)
    rule.first="invalid"
    #expect(throws:SQLFailure.self) {try owner.setRule(rule,column:0,table:table)}
    try owner.setRule(.init(),column:0,table:table)
    #expect(table.numberOfRows==3 && table.selectedRow==1 && rows.count==3)
    owner.update(rows:[],columns:[.init(title:"Value",numeric:true,value:{$0.value})],table:table)
    try owner.setRule(.init(),column:0,table:table)
    #expect(table.numberOfRows==0)
    owner.cancel()
    let empty=ActivityDataGrid<Row>.Coordinator(selection:.constant(nil))
    empty.update(rows:[],columns:[.init(title:"Value",numeric:true,value:{$0.value})],table:table)
    #expect(throws:SQLFailure.self) {try empty.setRule(rule,column:0,table:table)}
    empty.cancel()
  }
}
