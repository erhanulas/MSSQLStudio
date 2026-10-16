import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SharedTabThemeTests {
  @Test func mountedTabsRepaintBothDirectionsWithoutHoverOrSelectionChange() async throws {
    _=NSApplication.shared
    let original=StudioTheme.mode;defer {StudioTheme.apply(original)}
    StudioTheme.apply("light")
    let tabs=StudioTabControl(items:[.init(id:0,title:"Nesneler",icon:"square.stack.3d.up"),.init(id:1,title:"Arama",icon:"magnifyingglass")])
    tabs.selectedSegment=1
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:360,height:38),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=tabs;window.orderFront(nil)
    defer {window.close()}
    var colors:[NSColor]=[]
    for theme in ["light","dark","light"] {
      StudioTheme.apply(theme)
      try await Task.sleep(for:.milliseconds(120))
      tabs.layoutSubtreeIfNeeded();window.displayIfNeeded()
      #expect(tabs.selectedSegment==1)
      let bitmap=try #require(tabs.bitmapImageRepForCachingDisplay(in:tabs.bounds))
      tabs.cacheDisplay(in:tabs.bounds,to:bitmap)
      let x=bitmap.pixelsWide/2,y=bitmap.pixelsHigh/2
      let painted=try #require(bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB))
      // Compare like-for-like raster colors, including macOS HDR/color conversion.
      let reference=StudioTabControl(items:[.init(id:0,title:"Nesneler",icon:"square.stack.3d.up"),.init(id:1,title:"Arama",icon:"magnifyingglass")])
      reference.selectedSegment=1
      let freshWindow=NSWindow(contentRect:NSRect(x:-21000,y:0,width:360,height:38),styleMask:[.titled],backing:.buffered,defer:false)
      freshWindow.isReleasedWhenClosed=false;freshWindow.contentView=reference;freshWindow.orderFront(nil)
      try await Task.sleep(for:.milliseconds(60));reference.layoutSubtreeIfNeeded();freshWindow.displayIfNeeded()
      let freshBitmap=try #require(reference.bitmapImageRepForCachingDisplay(in:reference.bounds))
      reference.cacheDisplay(in:reference.bounds,to:freshBitmap)
      let expected=try #require(freshBitmap.colorAt(x:freshBitmap.pixelsWide/2,y:freshBitmap.pixelsHigh/2)?.usingColorSpace(.sRGB))
      freshWindow.close()
      #expect(abs(painted.redComponent-expected.redComponent)<0.02 && abs(painted.greenComponent-expected.greenComponent)<0.02 && abs(painted.blueComponent-expected.blueComponent)<0.02)
      colors.append(painted)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-mounted-tabs-"+theme+".png"))
    }
    #expect(colors[0] != colors[1])
    #expect(colors[0] == colors[2])
  }
}
