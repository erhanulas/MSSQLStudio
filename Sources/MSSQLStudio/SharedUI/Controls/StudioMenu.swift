import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor enum StudioPopover {
  static func placement(anchor:NSRect,viewport:NSRect,preferred:NSSize,flipped:Bool) -> (size:NSSize,edge:NSRectEdge) {
    let above=flipped ? anchor.minY-viewport.minY:viewport.maxY-anchor.maxY
    let below=flipped ? viewport.maxY-anchor.maxY:anchor.minY-viewport.minY
    let down=below>=preferred.height+24 || (above<preferred.height+24 && below>above)
    let height=min(preferred.height,max(220,(down ? below:above)-24))
    return (NSSize(width:min(preferred.width,max(240,viewport.width-32)),height:height),down ? (flipped ? .maxY:.minY):(flipped ? .minY:.maxY))
  }
  static func show<Content:View>(_ popup:NSPopover,content:Content,from anchor:NSView,rect:NSRect?=nil,size:NSSize) {
    guard let host=anchor.window?.contentView else {return}
    let visible=(rect ?? anchor.bounds).intersection(anchor.visibleRect)
    guard !visible.isNull,!visible.isEmpty else {return}
    let converted=host.convert(visible,from:anchor)
    let point=NSRect(x:converted.midX-4,y:converted.minY,width:8,height:converted.height)
    let placement=placement(anchor:point,viewport:host.bounds,preferred:size,flipped:host.isFlipped)
    let controller=NSHostingController(rootView:content.frame(width:placement.size.width,height:placement.size.height))
    controller.sizingOptions=[]
    controller.view.frame=NSRect(origin:.zero,size:placement.size)
    popup.animates=false;popup.behavior = .transient
    popup.contentViewController=controller;popup.contentSize=placement.size
    popup.show(relativeTo:point,of:host,preferredEdge:placement.edge)
  }
}

/// Keep native menu selection, accessibility and keyboard navigation.
@MainActor final class StudioMenu:NSMenu {
  override func addItem(_ newItem:NSMenuItem) {super.addItem(newItem);decorate(newItem)}
  override func insertItem(_ newItem:NSMenuItem,at index:Int) {super.insertItem(newItem,at:index);decorate(newItem)}
  override func addItem(withTitle title:String,action:Selector?,keyEquivalent:String)->NSMenuItem {
    let item=super.addItem(withTitle:title,action:action,keyEquivalent:keyEquivalent);decorate(item);return item
  }
  override func update() {super.update();for item in items {decorate(item)}}
  nonisolated private func decorate(_ item:NSMenuItem) {
    font = .systemFont(ofSize:13);minimumWidth=224
    guard !item.isSeparatorItem else {return}
    let name=item.title.lowercased(),action=item.action.map(NSStringFromSelector)?.lowercased() ?? ""
    let destructive=action.contains("delete") || action.contains("drop") || name.contains("kaydetmeden")
    guard item.image == nil else {return}
    let icon:String?
    if destructive {icon="trash"}
    else if name.contains("klasör") || name.contains("folder") {icon="folder"}
    else if name.contains("rename") || name.contains("adlandır") || name.contains("düzenle") {icon="pencil"}
    else if name.contains("copy") || name.contains("kopyala") {icon="doc.on.doc"}
    else if name.contains("close") || name.contains("kapat") {icon="xmark"}
    else if name.contains("pin") || name.contains("sabitle") {icon="pin"}
    else if name.contains("refresh") || name.contains("yenile") {icon="arrow.clockwise"}
    else if name.contains("connect") || name.contains("bağlan") {icon="network"}
    else if name.contains("new") || name.contains("yeni") {icon="plus"}
    else if name.contains("open") || name.contains("aç") {icon="arrow.up.forward.square"}
    else if name.contains("export") || name.contains("aktar") {icon="square.and.arrow.up"}
    else if name.contains("color") || name.contains("renk") {icon="paintpalette"}
    else if name.contains("properties") || name.contains("özellik") {icon="slider.horizontal.3"}
    else {icon=nil}
    if let icon {item.image=NSImage(systemSymbolName:icon,accessibilityDescription:nil);if destructive {item.image=item.image?.withSymbolConfiguration(.init(paletteColors:[NSColor.systemRed]))}}
  }
}

/// Common keyboard behavior for auxiliary windows, without stealing editor Tab.
