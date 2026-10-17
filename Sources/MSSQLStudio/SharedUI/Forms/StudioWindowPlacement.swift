import AppKit

@MainActor enum StudioWindowPlacement {
  static func name(_ role:String)->String {
    let fixture=Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" || ProcessInfo.processInfo.arguments.contains("--ui-smoke") || ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")})
    return (fixture ? "MSSQLStudio.fixture.\(ProcessInfo.processInfo.processIdentifier).":"MSSQLStudio.")+(role == "workbench" ? role:"window."+role)
  }
  static func restore(_ window:NSWindow,role:String,owner:NSWindow?=nil) {
    let key=name(role)
    let initialSize=window.frame.size
    // Native autosave tracks moves/resizes without polling.
    _ = window.setFrameAutosaveName(key)
    let restored=window.setFrameUsingName(key)
    if !window.styleMask.contains(.resizable) {window.setFrame(NSRect(origin:window.frame.origin,size:initialSize),display:false)}
    let screens=NSScreen.screens.map(\.visibleFrame)
    let preferred=owner?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    if !restored,let reference=owner?.frame ?? preferred {
      window.setFrameOrigin(centered(window.frame.size,in:reference).origin)
    }
    let contentMinimum=window.frameRect(forContentRect:NSRect(origin:.zero,size:window.contentMinSize)).size
    let minimum=NSSize(width:max(window.minSize.width,contentMinimum.width),height:max(window.minSize.height,contentMinimum.height))
    window.setFrame(fitted(window.frame,minimum:minimum,screens:screens,preferred:preferred),display:false)
  }
  static func save(_ window:NSWindow,role:String) {window.saveFrame(usingName:name(role))}
  /// A native sheet owns its attachment position; only its user-selected size is restored.
  static func restoreSheetSize(_ window:NSWindow,role:String,owner:NSWindow) {
    let origin=window.frame.origin
    _ = window.setFrameUsingName(name(role))
    let screen=owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    let contentMinimum=window.frameRect(forContentRect:NSRect(origin:.zero,size:window.contentMinSize)).size
    let minimum=NSSize(width:max(window.minSize.width,contentMinimum.width),height:max(window.minSize.height,contentMinimum.height))
    let frame=fitted(window.frame,minimum:minimum,screens:screen.map {[$0]} ?? [],preferred:screen)
    window.setFrame(NSRect(origin:origin,size:frame.size),display:false)
  }
  static func centered(_ size:NSSize,in reference:NSRect)->NSRect {
    NSRect(x:reference.midX-size.width/2,y:reference.midY-size.height/2,width:size.width,height:size.height)
  }
  static func fitted(_ frame:NSRect,minimum:NSSize,screens:[NSRect],preferred:NSRect?)->NSRect {
    guard !screens.isEmpty else {return frame}
    func area(_ screen:NSRect)->CGFloat {
      let intersection=frame.intersection(screen)
      return intersection.isNull ? 0:intersection.width*intersection.height
    }
    let best=screens.max {area($0)<area($1)}!
    let screen=area(best)>0 ? best:(preferred ?? best)
    let size=NSSize(width:min(screen.width,max(minimum.width,frame.width)),height:min(screen.height,max(minimum.height,frame.height)))
    let origin=NSPoint(x:min(max(frame.minX,screen.minX),screen.maxX-size.width),y:min(max(frame.minY,screen.minY),screen.maxY-size.height))
    return NSRect(origin:origin,size:size)
  }
}
