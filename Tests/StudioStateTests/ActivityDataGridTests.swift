import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityDataGridTests {
  private struct Row:Identifiable {let id:Int;let value:String?}
  @Test func headerSortUsesRawDurationAndPreservesSelectionThroughThreeStates() async throws {
    _=NSApplication.shared
    let rows=[Row(id:1,value:"120000"),Row(id:2,value:"9000"),Row(id:3,value:nil)]
    var selected:Int?=1
    let host=NSHostingView(rootView:StudioDataGrid(rows:rows,columns:[.init(title:"Süre",numeric:true,value:{$0.value},display:{ActivityFormat.duration($0.value.flatMap(Int64.init))})],selection:Binding(get:{selected},set:{selected=$0})))
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:500,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer {window.close()}
    host.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let table=try #require(children(host).compactMap {$0 as? NSTableView}.first)
    let owner=try #require(table.delegate as? StudioDataGrid<Row>.Coordinator),column=table.tableColumns[0]
    for state in 0..<3 {
      owner.tableView(table,didClick:column)
      for _ in 0..<100 where table.numberOfRows != 3 {try await Task.sleep(for:.milliseconds(5))}
      try await Task.sleep(for:.milliseconds(20))
      #expect(selected==1)
      let first=try #require(owner.tableView(table,viewFor:column,row:0) as? NSTextField)
      if state==0 {#expect(first.stringValue=="—" && table.selectedRow==2)}
      else {#expect(first.stringValue=="2 dk" && table.selectedRow==0)}
      #expect((column.headerCell as? FilterHeaderCell)?.ascending == (state==2 ? nil:state==0))
    }
    owner.cancel()
  }
  @Test func nativeSelectionAndNumericFiltersUseResultRulesWithoutChangingSource() async throws {
    _=NSApplication.shared
    let rows=[Row(id:1,value:"1"),Row(id:2,value:"12"),Row(id:3,value:nil)]
    var selected:Int?
    let binding=Binding<Int?>(get:{selected},set:{selected=$0})
    let host=NSHostingView(rootView:StudioDataGrid(rows:rows,columns:[.init(title:"Value",numeric:true,value:{$0.value})],selection:binding))
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:500,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer {window.close()}
    host.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let table=try #require(children(host).compactMap {$0 as? NSTableView}.first)
    let owner=try #require(table.delegate as? StudioDataGrid<Row>.Coordinator)
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
    let empty=StudioDataGrid<Row>.Coordinator(selection:.constant(nil))
    empty.update(rows:[],columns:[.init(title:"Value",numeric:true,value:{$0.value})],table:table)
    #expect(throws:SQLFailure.self) {try empty.setRule(rule,column:0,table:table)}
    empty.cancel()
  }
}
