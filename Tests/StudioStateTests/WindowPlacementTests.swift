import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor private final class ConfirmationState:ObservableObject {
  @Published var presented=false
  var approvals=0
  var cancellations=0
}
private struct ConfirmationFixture:View {
  @ObservedObject var state:ConfirmationState
  let role:String
  var body:some View {
    Text("Confirmation fixture").frame(maxWidth:.infinity,maxHeight:.infinity)
      .studioConfirmation("Fixture approval",isPresented:$state.presented,role:role,message:"No SQL is executed.",
        actions:[StudioConfirmationAction(title:"Apply",destructive:true) {state.approvals+=1}],cancel:{state.cancellations+=1})
  }
}

@MainActor @Suite(.serialized) struct WindowPlacementTests {
  private func window(_ size:NSSize=NSSize(width:480,height:320))->NSWindow {
    let window=NSWindow(contentRect:NSRect(origin:NSPoint(x:-20_000,y:0),size:size),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    return window
  }
  @Test func firstOpenCentersOnOwnerOrVisibleScreen() throws {
    _=NSApplication.shared
    let role="first-open-\(UUID())"
    defer {NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))}
    let screen=try #require(NSScreen.main?.visibleFrame)
    let owner=window(NSSize(width:800,height:600)),dialog=window()
    defer {dialog.close();owner.close()}
    owner.setFrameOrigin(NSPoint(x:screen.minX+40,y:screen.minY+40))
    StudioWindowPlacement.restore(dialog,role:role,owner:owner)
    #expect(abs(dialog.frame.midX-owner.frame.midX)<1)
    #expect(abs(dialog.frame.midY-owner.frame.midY)<1)
    dialog.setFrameAutosaveName("")
    NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))
    StudioWindowPlacement.restore(dialog,role:role)
    #expect(abs(dialog.frame.midX-screen.midX)<1)
    #expect(abs(dialog.frame.midY-screen.midY)<1)
  }
  @Test func nameValidationDoesNotShrinkUserSizedDialog() throws {
    _=NSApplication.shared
    let controller=StudioNameWindowController(title:"Fixture name",value:"",save:{_ in})
    let window=try #require(controller.window)
    defer {window.close()}
    #expect(window.styleMask.contains(.resizable))
    window.setContentSize(NSSize(width:650,height:400))
    let expanded=window.frame.size
    controller.saveName()
    #expect(!controller.errorLabel.stringValue.isEmpty && window.frame.size==expanded)
    controller.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
    #expect(controller.errorLabel.stringValue.isEmpty && window.frame.size==expanded)
  }
  @Test func sheetAlertRestoresSizeAndPreservesNativeApproval() async throws {
    _=NSApplication.shared
    let role="sheet-alert-\(UUID())"
    defer {NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))}
    let parent=window(NSSize(width:1000,height:750));parent.center();parent.orderFront(nil)
    defer {parent.close()}
    func alert()->StudioAlert {
      let alert=StudioAlert(role:role)
      alert.messageText="Fixture confirmation"
      alert.informativeText="No operation is performed."
      alert.addButton(withTitle:"Approve");alert.addButton(withTitle:"Cancel")
      return alert
    }
    let first=alert()
    var response:NSApplication.ModalResponse?
    first.beginSheetModal(for:parent) {response=$0}
    #expect(first.window.sheetParent === parent && first.window.styleMask.contains(.resizable))
    let target=NSSize(width:first.window.frame.width+120,height:first.window.frame.height+80)
    first.window.setFrame(NSRect(origin:first.window.frame.origin,size:target),display:false)
    parent.endSheet(first.window,returnCode:.alertSecondButtonReturn)
    for _ in 0..<100 where response==nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(response == .alertSecondButtonReturn)
    first.window.orderOut(nil)
    let second=alert()
    second.beginSheetModal(for:parent,completionHandler:nil)
    defer {parent.endSheet(second.window);second.window.orderOut(nil)}
    #expect(abs(second.window.frame.width-target.width)<1 && abs(second.window.frame.height-target.height)<1)
    #expect(second.window.sheetParent === parent)
    #expect(abs(second.window.frame.midX-parent.frame.midX)<1)
  }
  @Test func swiftUISheetRestoresSizeWithoutMovingItsParent() async throws {
    _=NSApplication.shared
    let role="swiftui-sheet-\(UUID())"
    defer {NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))}
    let parent=window(NSSize(width:1000,height:750));parent.center();parent.orderFront(nil)
    let parentFrame=parent.frame
    defer {parent.close()}
    func sheet()->NSWindow {
      let window=window()
      let host=NSHostingController(rootView:Text("Fixture sheet").frame(minWidth:400,maxWidth:.infinity,minHeight:260,maxHeight:.infinity)
        .studioSheetPlacement(role:role,minimum:NSSize(width:400,height:260)))
      host.sizingOptions=[];window.contentViewController=host
      return window
    }
    let first=sheet();parent.beginSheet(first,completionHandler:nil)
    try await Task.sleep(for:.milliseconds(80))
    first.setContentSize(NSSize(width:650,height:440))
    let target=first.frame.size
    parent.endSheet(first);first.orderOut(nil)
    try await Task.sleep(for:.milliseconds(80))
    let second=sheet();parent.beginSheet(second,completionHandler:nil)
    defer {parent.endSheet(second);second.orderOut(nil);first.close();second.close()}
    try await Task.sleep(for:.milliseconds(80))
    #expect(abs(second.frame.width-target.width)<1 && abs(second.frame.height-target.height)<1)
    #expect(second.sheetParent === parent && parent.frame==parentFrame)
    #expect(abs(second.frame.midX-parent.frame.midX)<1)
  }
  @Test func swiftUIConfirmationRequiresApprovalAndDiscardsStaleCompletion() async throws {
    _=NSApplication.shared
    let role="confirmation-\(UUID())"
    defer {NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))}
    let state=ConfirmationState(),parent=window(NSSize(width:900,height:650))
    let host=NSHostingController(rootView:ConfirmationFixture(state:state,role:role))
    host.sizingOptions=[];parent.contentViewController=host;parent.center();parent.orderFront(nil)
    defer {parent.close()}
    func presentedSheet() async throws -> NSWindow {
      for _ in 0..<100 where parent.attachedSheet==nil {try await Task.sleep(for:.milliseconds(10))}
      return try #require(parent.attachedSheet)
    }
    state.presented=true
    let cancelSheet=try await presentedSheet()
    #expect(cancelSheet.defaultButtonCell?.title=="Vazgeç")
    parent.endSheet(cancelSheet,returnCode:.alertFirstButtonReturn)
    for _ in 0..<100 where state.presented {try await Task.sleep(for:.milliseconds(10))}
    #expect(!state.presented && state.cancellations==1 && state.approvals==0)
    state.presented=true
    let approveSheet=try await presentedSheet()
    parent.endSheet(approveSheet,returnCode:.alertSecondButtonReturn)
    for _ in 0..<100 where state.approvals==0 {try await Task.sleep(for:.milliseconds(10))}
    #expect(!state.presented && state.approvals==1)
    state.presented=true
    let staleSheet=try await presentedSheet()
    state.presented=false
    try await Task.sleep(for:.milliseconds(50))
    parent.endSheet(staleSheet,returnCode:.alertSecondButtonReturn)
    try await Task.sleep(for:.milliseconds(50))
    #expect(state.approvals==1 && state.cancellations==1)
    let blocker=window()
    parent.beginSheet(blocker,completionHandler:nil)
    state.presented=true
    for _ in 0..<100 where parent.sheets.count<2 {try await Task.sleep(for:.milliseconds(10))}
    #expect(parent.sheets.count==2)
    state.presented=false
    try await Task.sleep(for:.milliseconds(50))
    parent.endSheet(blocker);blocker.orderOut(nil)
    try await Task.sleep(for:.milliseconds(50))
    #expect(parent.attachedSheet==nil && state.approvals==1)
    blocker.close()
  }
}
