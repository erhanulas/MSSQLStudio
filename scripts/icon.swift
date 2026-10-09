import AppKit
import Foundation
let folder = URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus();let scale=CGFloat(size)/1024
    NSGraphicsContext.current?.cgContext.scaleBy(x:scale,y:scale)
    let body=NSBezierPath(roundedRect:NSRect(x:30,y:30,width:964,height:964),xRadius:210,yRadius:210)
    NSGradient(starting:NSColor(calibratedRed:0.12,green:0.28,blue:0.62,alpha:1),ending:NSColor(calibratedRed:0.03,green:0.08,blue:0.20,alpha:1))!.draw(in:body,angle:270)
    NSColor(calibratedWhite:1,alpha:0.94).setStroke();NSColor(calibratedWhite:1,alpha:0.08).setFill()
    let cylinder=NSBezierPath();cylinder.move(to:NSPoint(x:245,y:650));cylinder.line(to:NSPoint(x:245,y:430));cylinder.curve(to:NSPoint(x:779,y:430),controlPoint1:NSPoint(x:245,y:300),controlPoint2:NSPoint(x:779,y:300));cylinder.line(to:NSPoint(x:779,y:650));cylinder.lineWidth=40;cylinder.stroke()
    for y:CGFloat in [650,540,430] { let ellipse=NSBezierPath(ovalIn:NSRect(x:245,y:y-64,width:534,height:128));ellipse.lineWidth=32;if y==650 { ellipse.fill() };ellipse.stroke() }
    let text="SQL" as NSString;let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:172,weight:.bold),.foregroundColor:NSColor.white];let metrics=text.size(withAttributes:attributes);text.draw(at:NSPoint(x:(1024-metrics.width)/2,y:135),withAttributes:attributes)
    image.unlockFocus();let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!;try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("\(size).png"))
}
