import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivitySQLTextPreviewTests {
  private func output(_ sql:String)->Execution {var e=Execution();e.results=[Rows(values:[[sql,String(sql.utf16.count*2)]])];return e}
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<300 where !condition() {try await Task.sleep(for:.milliseconds(5))}
    #expect(condition())
  }
  @Test func latestSelectionWaitsForPhysicalReaderAndFullTailRemainsReachable() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"")
    var calls:[String]=[],continuations:[CheckedContinuation<Execution,Never>]=[]
    let model=ActivitySQLTextPreviewModel(server:server,reader:{sql,limits in
      #expect(limits.totalBytes==4*1024*1024 && limits.timeout==10)
      calls.append(sql);return await withCheckedContinuation {continuations.append($0)}
    })
    model.show(handle:"0xAA",prefix:"first",generation:server.generation)
    try await wait {!continuations.isEmpty}
    model.show(handle:"0xBB",prefix:"second",generation:server.generation)
    model.show(handle:"0xCC",prefix:"third",generation:server.generation)
    #expect(calls.count==1 && model.text=="third")
    continuations.removeFirst().resume(returning:output("stale"))
    try await wait {calls.count==2}
    #expect(calls[1].contains("0xCC") && !calls[1].contains("0xBB"))
    let sql=String(repeating:"SELECT 1;\n",count:1200)+"SELECT N'END_MARKER';"
    continuations.removeFirst().resume(returning:output(sql))
    try await wait {model.complete}
    #expect(model.text==sql && model.error.isEmpty)
    model.show(handle:"0xCC",prefix:"new short sample",generation:server.generation)
    #expect(calls.count==2 && model.text==sql)
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:600,height:200))
    let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:600,height:200),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;defer {window.close()}
    preview.display(model.text);preview.layoutSubtreeIfNeeded()
    #expect(preview.textView.string==sql && preview.textView.frame.height>20000)
    let tail=(sql as NSString).range(of:"END_MARKER")
    preview.textView.setSelectedRange(tail);preview.textView.scrollRangeToVisible(tail)
    #expect(preview.textView.enclosingScrollView!.contentView.bounds.minY>10000)
  }
  @Test func nativePreviewLoadsFullSelectedHandleOnceAcrossSampleUpdates() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"")
    let sql=String(repeating:"SELECT N'Preview';\n",count:1200)+"SELECT N'END_MARKER';"
    var reads=0
    server.asyncCatalogFixture={query in
      reads+=1;#expect(query.contains("sys.dm_exec_sql_text"));return output(sql)
    }
    let host=NSHostingController(rootView:ActivitySQLTextPreview(server:server,handle:"0xAA",prefix:"short"))
    host.sizingOptions=[]
    let window=NSWindow(contentRect:NSRect(x:60,y:60,width:650,height:240),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host;window.setContentSize(NSSize(width:650,height:240));window.makeKeyAndOrderFront(nil);host.view.layoutSubtreeIfNeeded();defer {window.close()}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    func preview()->SQLPreviewView? {descendants(host.view).compactMap {$0 as? SQLPreviewView}.first}
    try await wait {preview()?.textView.string==sql}
    #expect(reads==1)
    host.rootView=ActivitySQLTextPreview(server:server,handle:"0xAA",prefix:"new periodic short sample")
    try await Task.sleep(for:.milliseconds(50))
    #expect(reads==1 && preview()?.textView.string==sql)
    window.setContentSize(NSSize(width:650,height:240));host.view.frame=NSRect(x:0,y:0,width:650,height:240);host.view.layoutSubtreeIfNeeded()
    let text=try #require(preview()?.textView)
    text.setSelectedRange((sql as NSString).range(of:"END_MARKER"))
    let scroll=try #require(text.enclosingScrollView)
    scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,text.frame.height-scroll.contentView.bounds.height)));scroll.reflectScrolledClipView(scroll.contentView)
    #expect(text.enclosingScrollView!.contentView.bounds.minY>10000)
    try await Task.sleep(for:.milliseconds(80));host.view.layoutSubtreeIfNeeded();host.view.displayIfNeeded()
    if let view=preview(),let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-activity-tail-real.png"))}
    let tail=(sql as NSString).range(of:"END_MARKER")
    let content=try #require(text.textContentStorage)
    let viewport=try #require(text.textLayoutManager?.textViewportLayoutController.viewportRange)
    let start=content.offset(from:content.documentRange.location,to:viewport.location)
    let end=content.offset(from:content.documentRange.location,to:viewport.endLocation)

    #expect(NSIntersectionRange(NSRange(location:start,length:end-start),tail)==tail)
  }
  @Test func generationChangeAndClosingDoNotPublishLateTextAndLegacyPrefixUpdates() async throws {
    let server=ConnectedServer(profile:.init(),password:"")
    var continuation:CheckedContinuation<Execution,Never>?
    let model=ActivitySQLTextPreviewModel(server:server,reader:{_,_ in await withCheckedContinuation {continuation=$0}})
    model.show(handle:"0xAA",prefix:"sample",generation:server.generation)
    try await wait {continuation != nil}
    server.generation=UUID();continuation?.resume(returning:output("stale"));continuation=nil
    try await wait {!model.loading}
    #expect(!model.complete && model.text=="sample" && !model.error.isEmpty)
    model.show(handle:"0xBB",prefix:"new",generation:server.generation)
    try await wait {continuation != nil}
    model.cancel();continuation?.resume(returning:output("closed"));continuation=nil
    try await Task.sleep(for:.milliseconds(20))
    #expect(!model.complete && model.text=="new")
    model.show(handle:nil,prefix:"legacy1",generation:server.generation)
    model.show(handle:nil,prefix:"legacy2",generation:server.generation)
    #expect(model.text=="legacy2" && !model.complete && !model.error.isEmpty)
  }
}
