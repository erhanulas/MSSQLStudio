import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ProfilerChoicesTests {
  private func server()->ConnectedServer {
    let server=ConnectedServer(profile:ServerProfile(login:"current"),password:"");server.online=false
    server.databases=[CatalogItem(id:5,name:"Warehouse"),CatalogItem(id:6,name:"Sales")];return server
  }
  private func result(_ names:[String])->Execution {
    var execution=Execution();execution.results=[Rows(fields:[Field("principal_id"),Field("name"),Field(""),Field("type_desc")],values:names.enumerated().map {[String($0.offset),$0.element,"","SQL_LOGIN"]})];return execution
  }
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<200 where !condition() {try await Task.sleep(for:.milliseconds(3))}
    #expect(condition())
  }
  @Test func loadedExplorerBranchesAndOfflineChoicesDoNotConnectOrChangeFilters() throws {
    let server=server();var reads=0
    let choices=ProfilerChoicesModel(server:server,explorer:{.init(databases:["Warehouse","Sales"],logins:["reader","writer"])},reader:{_,_ in reads+=1;throw SQLFailure("unexpected")})
    choices.refresh(automatic:true)
    #expect(reads==0 && choices.values(for:.database)==["","Sales","Warehouse"])
    #expect(choices.values(for:.login)==["","current","reader","writer"])
    choices.refresh();#expect(reads==0 && choices.note.contains("Çevrimdışı"))
  }
  @Test func missingLoginBranchLoadsOncePerGenerationAndRejectsPartialOrLateMetadata() async throws {
    let server=server();server.catalogFixture={_ in Execution()}
    var reads=0,pending:CheckedContinuation<Execution,Never>?
    let choices=ProfilerChoicesModel(server:server,reader:{sql,limits in
      #expect(sql==Catalog.objects(.logins) && limits.rows==5001 && limits.timeout==10)
      reads+=1;return await withCheckedContinuation {pending=$0}
    })
    choices.refresh(automatic:true);choices.refresh(automatic:true)
    try await wait {pending != nil}
    #expect(reads==1 && choices.loading)
    pending?.resume(returning:result(["app_login"]));pending=nil
    try await wait {!choices.loading}
    #expect(choices.values(for:.login)==["","app_login","current"])
    choices.refresh(automatic:true);#expect(!choices.loading && reads==1)
    choices.refresh();try await wait {pending != nil}
    var partial=result(["bad"]);partial.partial=true
    pending?.resume(returning:partial);pending=nil
    try await wait {!choices.loading}
    #expect(!choices.error.isEmpty && choices.values(for:.login).contains("app_login") && !choices.values(for:.login).contains("bad"))
    choices.refresh();try await wait {pending != nil}
    server.generation=UUID();pending?.resume(returning:result(["stale"]));pending=nil
    try await wait {!choices.loading}
    #expect(choices.error.contains("değişti") && !choices.values(for:.login).contains("stale"))
    choices.refresh();try await wait {pending != nil}
    let count=reads;choices.cancel();choices.refresh()
    #expect(choices.loading && reads==count)
    pending?.resume(returning:result(["cancelled"]));pending=nil
    try await wait {!choices.loading}
    #expect(!choices.values(for:.login).contains("cancelled"))
  }
  @Test func nativeSearchableSelectionUsesExplorerValuesAndPreservesCustomEntryWithoutStartingCapture() async throws {
    _=NSApplication.shared
    let server=server(),model=ProfilerModel(server:server,executor:{_ in Issue.record("Capture must not execute");return Execution()},disconnect:{})
    model.configuration.database="CustomDB"
    let host=NSHostingController(rootView:ProfilerFilters(model:model,showClients:.constant(false)));host.sizingOptions=[]
    let window=ProfilerWindow(contentViewController:host);window.isReleasedWhenClosed=false
    window.setContentSize(NSSize(width:960,height:240));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let picker=try #require(descendants(host.view).compactMap {$0 as? StudioSearchablePopUpButton}.first {$0.accessibilityLabel()=="Veritabanı"})
    #expect(picker.titleOfSelectedItem=="CustomDB" && picker.itemTitles.contains("Sales") && picker.itemTitles.contains("Tümü"))
    picker.showChoices()
    let choices=try #require(picker.choices);choices.beginSearch("Ware")
    #expect(model.configuration.database=="CustomDB")
    #expect(choices.filtered==["Warehouse"])
    choices.commit()
    #expect(model.configuration.database=="Warehouse" && !model.hasSession)
    picker.showChoices();picker.choices?.beginSearch("Tümü");picker.choices?.commit()
    #expect(model.configuration.database.isEmpty && !model.running)
    server.profile.host="other-host";model.choices.refresh()
    #expect(model.choices.error.contains("değişti"))
  }
}
