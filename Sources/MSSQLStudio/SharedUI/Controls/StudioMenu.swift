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
  static func adopting(_ source:NSMenu?)->StudioMenu {
    if let source=source as? StudioMenu {return source}
    let menu=StudioMenu(title:source?.title ?? "")
    if let source {
      menu.autoenablesItems=source.autoenablesItems;menu.delegate=source.delegate
      for item in source.items {
        guard let copy=item.copy() as? NSMenuItem else {continue}
        if let child=item.submenu {copy.submenu=adopting(child)}
        menu.addItem(copy)
      }
    }
    return menu
  }
  override func addItem(_ newItem:NSMenuItem) {super.addItem(newItem);decorate(newItem)}
  override func insertItem(_ newItem:NSMenuItem,at index:Int) {super.insertItem(newItem,at:index);decorate(newItem)}
  override func addItem(withTitle title:String,action:Selector?,keyEquivalent:String)->NSMenuItem {
    let item=super.addItem(withTitle:title,action:action,keyEquivalent:keyEquivalent);decorate(item);return item
  }
  override func update() {super.update();for item in items {decorate(item)}}
  nonisolated private func decorate(_ item:NSMenuItem) {
    font = .systemFont(ofSize:14,weight:.regular);minimumWidth=280
    StudioCommandCatalog.decorate(item)
    guard !item.isSeparatorItem else {return}
    // Sparse, quiet symbols leave the action label and native shortcut column dominant.
    // Explicit non-template images (folder color swatches, for example) retain their meaning.
    if let image=item.image?.copy() as? NSImage {
      image.size=NSSize(width:16,height:16)
      item.image=image.isTemplate ? image.withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor])):image
      item.preferredImageVisibility = .visible
      return
    }
    let selector=item.action.map(NSStringFromSelector) ?? ""
    let symbols:[String:String]=[
      "newQuery":"plus","newQueryAtNode":"plus","showConnect":"plus",
      "refreshContextNode":"arrow.triangle.2.circlepath","refreshContextParent":"arrow.triangle.2.circlepath",
      "goToDefinition:":"arrow.up.forward.square","revealExplorerObject:":"scope",
      "runSQLStatement:":"play","execute":"play","formatSQL":"text.alignleft","formatSQLText:":"text.alignleft",
      "copy:":"doc.on.doc","paste:":"clipboard","cut:":"scissors",
      "showFavoritesAtNode":"star","showFavorites":"star","createExplorerGroup:":"folder.badge.plus"
    ]
    if let symbol=symbols[selector] {
      item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?
        .withSymbolConfiguration(.init(pointSize:13,weight:.regular))?
        .withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor]))
      item.image?.size=NSSize(width:16,height:16)
      item.preferredImageVisibility = .visible
    }
    // No generic fallback icon: secondary actions share the native text gutter.

  }
}

/// Common keyboard behavior for auxiliary windows, without stealing editor Tab.

/// Native text commands keep their responder/validation behavior across all owned text surfaces.
@MainActor class StudioTextView:NSTextView {
  override func menu(for event:NSEvent)->NSMenu? {StudioMenu.adopting(super.menu(for:event))}
}
