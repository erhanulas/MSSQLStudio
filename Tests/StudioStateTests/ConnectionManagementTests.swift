import AppKit
import SQLServerKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ConnectionManagementTests {
  private func status(_ available: Bool) -> ODBCDriverSetup.Status {
    .init(available:available,version:available ? "18.7.1.1":"18",detail:"Synthetic driver",brew:"/synthetic/brew")
  }
  @Test func driverInstallationRequiresApprovalUsesOfficialCommandsAndRedetects() async {
    let model=DriverSetupModel(); var calls:[[String]]=[], inspections=0
    model.inspect={ inspections += 1; return self.status(inspections > 1) }
    model.execute={ executable,args,license,output in
      #expect(executable == "/synthetic/brew")
      calls.append(args)
      if args == ["--version"] {#expect(!license);return "Homebrew 6.0.1"}
      #expect(license);output("Synthetic progress\n");return ""
    }
    await model.refresh()
    await model.install(approved:false)
    #expect(calls.isEmpty && inspections == 1 && !model.busy)
    await model.install(approved:true)
    #expect(calls == [["--version"]]+ODBCDriverSetup.installationCommands(homebrewMajor:6).map(\.arguments))
    #expect(inspections == 2 && model.status?.available == true && model.error.isEmpty && !model.busy)
    await model.install(approved:true)
    #expect(inspections == 2)
    #expect(!ODBCDriverSetup.installationCommands(homebrewMajor:5).contains {$0.arguments.first == "trust"})
  }
  @Test func failedInstallDisplaysErrorRedetectsAndAllowsRetry() async {
    let model=DriverSetupModel(); var inspections=0
    model.inspect={inspections += 1; return self.status(false)}
    model.execute={_,args,_,_ in
      if args == ["--version"] {return "Homebrew 5.0"}
      throw SQLFailure("Synthetic permission error")
    }
    await model.refresh(); await model.install(approved:true)
    #expect(inspections == 2 && model.error.contains("Synthetic permission error") && !model.busy)
    await model.install(approved:true)
    #expect(inspections == 3 && !model.busy)
  }
  @Test func newManagerUsesInMemoryProfilesWithoutConnectingOrReadingVault() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(name:"Synthetic saved"),password:"")
    server.online=false; var actions=0
    let manager=ConnectionManager(servers:[server],initial:nil,connect:{_,_,_ in actions += 1},save:{_,_,_,_ in actions += 1},loadingChanged:{_ in},cancel:{})
    let host=NSHostingView(rootView:manager)
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:1020,height:680),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;defer {window.close()}
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width <= 1030 && host.fittingSize.height <= 700)
    #expect(actions == 0 && !server.online && server.profile.name == "Synthetic saved")
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    for mode in ["light","dark"] {
      StudioTheme.apply(mode);window.orderFront(nil)
      try await Task.sleep(for:.milliseconds(100))
      host.layoutSubtreeIfNeeded();window.displayIfNeeded()
      let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds))
      host.cacheDisplay(in:host.bounds,to:bitmap)
      let scale=CGFloat(bitmap.pixelsWide)/host.bounds.width
      let card=try #require(bitmap.colorAt(x:Int(30*scale),y:Int(250*scale))?.usingColorSpace(.sRGB))
      #expect(mode == "dark" ? card.redComponent < 0.3 : card.redComponent > 0.9)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/MSSQLStudio-connections-106-\(mode).png"))
    }
  }
}
