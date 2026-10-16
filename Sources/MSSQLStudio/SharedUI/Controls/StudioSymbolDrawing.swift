import AppKit

@MainActor enum StudioSymbolDrawing {
  static func rect(for image:NSImage,in bounds:NSRect)->NSRect {
    guard image.size.width>0,image.size.height>0 else {return .zero}
    let scale=min(bounds.width/image.size.width,bounds.height/image.size.height)
    let size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
    return NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height)
  }
  static func draw(_ image:NSImage,in bounds:NSRect) {image.draw(in:rect(for:image,in:bounds))}
}
