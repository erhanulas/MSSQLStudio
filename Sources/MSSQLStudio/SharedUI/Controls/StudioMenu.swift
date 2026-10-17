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
  static func show<Content:View>(_ popup:NSPopover,content:Content,from anchor:NSView,rect:NSRect?=nil,size:NSSize,updatingExisting:Bool=false,behavior:NSPopover.Behavior = .transient) {
    guard let host=anchor.window?.contentView else {return}
    let visible=(rect ?? anchor.bounds).intersection(anchor.visibleRect)
    guard !visible.isNull,!visible.isEmpty else {return}
    let converted=host.convert(visible,from:anchor)
    let point=NSRect(x:converted.midX-4,y:converted.minY,width:8,height:converted.height)
    let placement=placement(anchor:point,viewport:host.bounds,preferred:size,flipped:host.isFlipped)
    let framed=content.frame(width:placement.size.width,height:placement.size.height)
    let controller:NSViewController
    if updatingExisting {
      let existing=(popup.contentViewController as? NSHostingController<AnyView>) ?? NSHostingController(rootView:AnyView(framed))
      existing.rootView=AnyView(framed);existing.sizingOptions=[];controller=existing
    } else {
      let fresh=NSHostingController(rootView:framed);fresh.sizingOptions=[];controller=fresh
    }
    // AppKit owns the hosting view origin inside the native popover chrome.
    // Resetting it while reusing the controller shifts content into its insets.
    controller.view.setFrameSize(placement.size)
    popup.animates=false;popup.behavior=behavior
    if popup.contentViewController !== controller {popup.contentViewController=controller}
    popup.contentSize=placement.size
    (anchor.window as? StudioPanelWindow)?.activePopover=popup
    if updatingExisting,popup.isShown {popup.positioningRect=point}
    else {popup.show(relativeTo:point,of:host,preferredEdge:placement.edge)}
  }
}

/// Keep native menu selection, accessibility and keyboard navigation.
@MainActor final class StudioMenu:NSMenu {
  /// Opt-in semantic colors for action menus; custom swatches keep their own colors.
  func applySemanticActionColors() {
    for item in items where !item.isSeparatorItem {
      (item.submenu as? StudioMenu)?.applySemanticActionColors()
      let title=item.title.lowercased()
      let color:NSColor?
      if ["delete","drop","sil","kaldır"].contains(where:title.contains) {color = .systemRed}
      else if ["disable","durdur","stop","disconnect","bağlantıyı kes"].contains(where:title.contains) {color = .systemOrange}
      else if ["enable","başlat","start","connect","bağlan"].contains(where:title.contains) {color = .systemGreen}
      else if ["refresh","yenile","new","yeni","modify","düzenle","properties","özellik","script","select"].contains(where:title.contains) {color = .systemBlue}
      else {color=nil}
      guard let color else {continue}
      let symbol=title.contains("disable") ? "bolt.slash":title.contains("enable") ? "bolt":nil
      let source=symbol.flatMap {NSImage(systemSymbolName:$0,accessibilityDescription:nil)} ?? item.image
      guard let image=source?.withSymbolConfiguration(.init(paletteColors:[color])) else {continue}
      image.isTemplate=false;image.size=NSSize(width:16,height:16);item.image=image
    }
  }
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
    // Every action gets a consistent symbol; explicit images retain their meaning.
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
      "copy:":"doc.on.doc","paste:":"clipboard","cut:":"scissors","previewDataEditing":"eye",
      "showFavoritesAtNode":"star","showFavorites":"star","createExplorerGroup:":"folder.badge.plus"
    ]
    let title=item.title.lowercased()
    let titleSymbols:[(String,String)]=[("sil","trash"),("delete","trash"),("drop","trash"),("kapat","xmark"),("close","xmark"),("kaydet","square.and.arrow.down"),("save","square.and.arrow.down"),("kopy","doc.on.doc"),("copy","doc.on.doc"),("yenile","arrow.clockwise"),("refresh","arrow.clockwise"),("aç","arrow.up.forward.square"),("open","arrow.up.forward.square"),("select","tablecells"),("script","doc.text"),("özellik","slider.horizontal.3"),("properties","slider.horizontal.3"),("ayar","gearshape"),("düzenle","pencil"),("edit","pencil"),("new","plus"),("yeni","plus"),("find","magnifyingglass"),("ara","magnifyingglass"),("undo","arrow.uturn.backward"),("redo","arrow.uturn.forward"),("dışa aktar","square.and.arrow.up"),("export","square.and.arrow.up"),("içe aktar","square.and.arrow.down"),("import","square.and.arrow.down"),("bağlantı","network"),("connection","network"),("bağlan","network"),("filtre","line.3.horizontal.decrease.circle"),("filter","line.3.horizontal.decrease.circle"),("taşı","folder"),("move","folder"),("sabitle","pin"),("pin","pin"),("rename","pencil"),("yeniden ad","pencil"),("geri","arrow.uturn.backward"),("seç","checkmark.circle"),("select all","checkmark.circle")]
    let symbol=symbols[selector] ?? titleSymbols.first(where:{title.contains($0.0)})?.1 ?? (item.submenu != nil ? "folder":"ellipsis.circle")
    do {
      item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?
        .withSymbolConfiguration(.init(pointSize:13,weight:.regular))?
        .withSymbolConfiguration(.init(paletteColors:[.secondaryLabelColor]))
      item.image?.size=NSSize(width:16,height:16)
      item.preferredImageVisibility = .visible
    }


  }
}

/// Common keyboard behavior for auxiliary windows, without stealing editor Tab.

/// Native text commands keep their responder/validation behavior across all owned text surfaces.
@MainActor class StudioTextView:NSTextView {
  override func menu(for event:NSEvent)->NSMenu? {StudioMenu.adopting(super.menu(for:event))}
}
