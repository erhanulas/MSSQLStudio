import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor class StudioAssociatedWindow:NSWindow {
  static let visibilityChanged=Notification.Name("studioAssociatedWindowVisibilityChanged")
  var framePersistenceRole:String?
  private var placementPrepared=false
  private func preparePlacement() {
    guard !placementPrepared,let framePersistenceRole else {return}
    placementPrepared=true
    StudioWindowPlacement.restore(self,role:framePersistenceRole,owner:associatedOwner)
  }
  var didClose:(()->Void)?
  private(set) weak var associatedOwner:NSWindow?
  func associate(with owner:NSWindow?) {
    if associatedOwner == nil,let owner,owner !== self {associatedOwner=owner}
    // A child window is composited with its parent in Mission Control and cannot
    // be selected independently. Ownership must not impose native child ordering.
    parent?.removeChildWindow(self)
    level = .normal
    collectionBehavior.subtract([.transient,.ignoresCycle])
    collectionBehavior.formUnion([.managed,.participatesInCycle,.fullScreenAuxiliary])
    isExcludedFromWindowsMenu=false
    tabbingMode = .disallowed
  }
  override func order(_ place:NSWindow.OrderingMode,relativeTo otherWin:Int) {
    if place != .out {
      let focused=NSApp.keyWindow ?? NSApp.mainWindow
      associate(with:focused?.sheetParent ?? focused)
      preparePlacement()
    }
    super.order(place,relativeTo:otherWin)
    NotificationCenter.default.post(name:Self.visibilityChanged,object:self)
    if place != .out,!title.isEmpty {NSApp.addWindowsItem(self,title:title,filename:false)}
  }
  override func makeKeyAndOrderFront(_ sender:Any?) {
    let focused=NSApp.keyWindow ?? NSApp.mainWindow
    associate(with:focused?.sheetParent ?? focused)
    super.makeKeyAndOrderFront(sender)
  }
  override func close() {
    if placementPrepared,let framePersistenceRole {
      StudioWindowPlacement.save(self,role:framePersistenceRole)
      _ = setFrameAutosaveName("");placementPrepared=false
    }
    let callback=didClose;didClose=nil
    parent?.removeChildWindow(self)
    associatedOwner=nil;NSApp.removeWindowsItem(self)
    super.close();callback?()
  }
}

@MainActor class StudioPanelWindow:StudioAssociatedWindow {
  var cancelAction:(()->Void)?
  weak var activePopover:NSPopover?
  var focusOrder:[NSView]=[]
  @discardableResult func advanceDialogFocus(backward:Bool=false)->Bool {
    let available=focusOrder.filter {!$0.isHiddenOrHasHiddenAncestor && ($0 as? NSControl)?.isEnabled != false}
    guard !available.isEmpty else {if backward {selectPreviousKeyView(nil)} else {selectNextKeyView(nil)};return true}
    let responder=firstResponder
    let current=(responder as? NSTextView).flatMap {$0.isFieldEditor ? $0.delegate as? NSView:nil} ?? (responder as? NSView)
    let index=current.flatMap {view in available.firstIndex {$0 === view}} ?? (backward ? 0:available.count-1)
    (current as? NSControl)?.validateEditing()
    return makeFirstResponder(available[(index+(backward ? available.count-1:1)) % available.count])
  }
  override func sendEvent(_ event:NSEvent) {
    if event.type == .keyDown,NSApp.modalWindow == nil,attachedSheet == nil,event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
      if event.keyCode==53 {cancelOperation(nil);return}
      if event.keyCode==48 {
        let text=firstResponder as? NSTextView
        if text == nil || text?.isFieldEditor == true {advanceDialogFocus(backward:event.modifierFlags.contains(.shift));return}
      }
    }
    super.sendEvent(event)
  }
  override func cancelOperation(_ sender:Any?) {
    // Native popovers may leave keyboard events on their owning panel.
    if let activePopover,activePopover.isShown {activePopover.close();return}
    if let cancelAction {cancelAction()} else {performClose(sender)}
  }
}

@MainActor class StudioDialogButton:NSButton {
  override var acceptsFirstResponder:Bool {true}
  override func performClick(_ sender:Any?) {
    guard isEnabled,let action else {return}
    // Dispatch immediately instead of running a nested AppKit click animation.
    highlight(true);defer {highlight(false)}
    _ = sendAction(action,to:target)
  }
}

/// Non-modal input: field binding, validation and saving share one visible window.
@MainActor final class StudioNameWindowController:NSWindowController,NSWindowDelegate,NSTextFieldDelegate {
  let nameField=NSTextField(string:"")
  let saveButton=StudioDialogButton(title:"Kaydet",target:nil,action:nil)
  let cancelButton=StudioDialogButton(title:"Vazgeç",target:nil,action:nil)
  let errorLabel=NSTextField(wrappingLabelWithString:"")
  private let submit:(String) async throws->Void
  private(set) var saving=false
  var closed:(()->Void)?
  init(title:String,value:String,save:@escaping (String) async throws->Void) {
    submit=save
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:480,height:210),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed=false;window.title=title
    super.init(window:window);window.delegate=self
    let body=NSView();StudioTheme.surface(body,card:true);window.contentView=body
    let heading=NSTextField(labelWithString:title);heading.font = .systemFont(ofSize:16,weight:.semibold);heading.textColor=StudioTheme.text
    let icon=NSImageView(image:NSImage(systemSymbolName:title.localizedLowercase.contains("klasör") ? "folder.badge.plus":"server.rack",accessibilityDescription:nil)!);icon.contentTintColor=StudioTheme.accent
    let header=NSStackView(views:[icon,heading]);header.spacing=10
    let hint=NSTextField(wrappingLabelWithString:"Yerel adlandırma · Veritabanına bağlantı gerekmez");hint.font = .systemFont(ofSize:11);hint.textColor=StudioTheme.muted
    nameField.stringValue=value;nameField.placeholderString="Ad girin";nameField.isEditable=true;nameField.isSelectable=true;nameField.delegate=self;nameField.font = .systemFont(ofSize:13);nameField.setAccessibilityIdentifier("explorerNameInput")
    errorLabel.font = .systemFont(ofSize:11);errorLabel.textColor=StudioTheme.danger;errorLabel.maximumNumberOfLines=3;errorLabel.lineBreakMode = .byTruncatingTail
    saveButton.target=self;saveButton.action=#selector(saveName);saveButton.keyEquivalent="\r";saveButton.bezelStyle = .rounded;saveButton.setAccessibilityIdentifier("explorerNameSave")
    cancelButton.target=self;cancelButton.action=#selector(cancelName);cancelButton.keyEquivalent="\u{1b}";cancelButton.bezelStyle = .rounded
    let spacer=NSView();let actions=NSStackView(views:[spacer,cancelButton,saveButton]);actions.spacing=8
    let stack=NSStackView(views:[header,hint,nameField,errorLabel,actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
    body.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),stack.bottomAnchor.constraint(lessThanOrEqualTo:body.bottomAnchor,constant:-16),nameField.widthAnchor.constraint(equalTo:stack.widthAnchor),nameField.heightAnchor.constraint(equalToConstant:26),actions.widthAnchor.constraint(equalTo:stack.widthAnchor),icon.widthAnchor.constraint(equalToConstant:24),icon.heightAnchor.constraint(equalToConstant:24)])
    nameField.nextKeyView=saveButton;saveButton.nextKeyView=cancelButton;cancelButton.nextKeyView=nameField
    window.focusOrder=[nameField,saveButton,cancelButton]
    window.framePersistenceRole="nameEntry"
    window.initialFirstResponder=nameField;window.center()
  }
  required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
  private func setDialogHeight(_ height:CGFloat) {
    guard let window else {return}
    var frame=window.frame
    let target=window.frameRect(forContentRect:NSRect(x:0,y:0,width:480,height:height)).height
    frame.origin.y+=frame.height-target;frame.size.height=target
    window.setFrame(frame,display:true,animate:false)
  }
  func controlTextDidChange(_ notification:Notification) {errorLabel.stringValue="";setDialogHeight(210)}
  @objc func saveName() {
    guard !saving else {return}
    // Own an immutable input snapshot and commit the field editor before disabling
    // the control. Its backing NSString must not be read after the async handoff.
    let editing=nameField.currentEditor()?.string ?? nameField.stringValue
    let text=String(decoding:Array(editing.utf8),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    guard !text.isEmpty else {errorLabel.stringValue="Bir ad girin.";setDialogHeight(244);window?.makeFirstResponder(nameField);return}
    nameField.validateEditing();nameField.stringValue=text;window?.makeFirstResponder(saveButton)
    saving=true;saveButton.title="Kaydediliyor…";saveButton.isEnabled=false;cancelButton.isEnabled=false;nameField.isEnabled=false
    Task { [weak self] in
      guard let self else {return}
      do {try await submit(text);saving=false;window?.performClose(nil)}
      catch {saving=false;errorLabel.stringValue=error.localizedDescription;errorLabel.toolTip=error.localizedDescription;setDialogHeight(244);saveButton.title="Kaydet";saveButton.isEnabled=true;cancelButton.isEnabled=true;nameField.isEnabled=true;window?.makeFirstResponder(nameField)}
    }
  }
  @objc func cancelName() {window?.performClose(nil)}
  func windowShouldClose(_ sender:NSWindow)->Bool {!saving}
  func windowWillClose(_ notification:Notification) {closed?()}
}

@MainActor final class StudioCloseWindowController:NSWindowController,NSWindowDelegate {
  let saveButton=StudioDialogButton(title:"Tümünü Kaydet",target:nil,action:nil)
  let discardButton=StudioDialogButton(title:"Tümünü Kaydetmeden Kapat",target:nil,action:nil)
  let cancelButton=StudioDialogButton(title:"Vazgeç",target:nil,action:nil)
  private let decision:(StudioState.BulkCloseChoice)->Bool
  private var completed=false
  var closed:(()->Void)?
  init(title:String,count:Int,decision:@escaping (StudioState.BulkCloseChoice)->Bool) {
    self.decision=decision
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:540,height:198),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.animationBehavior = .none
    window.framePersistenceRole="bulkClose"
    window.title=title;window.identifier = .init("studio.bulkClose");window.isReleasedWhenClosed=false
    super.init(window:window);window.delegate=self
    let body=NSView();StudioTheme.surface(body,card:true);window.contentView=body
    let title=NSTextField(labelWithString:"Değişiklikler kaydedilsin mi?");title.font = .systemFont(ofSize:17,weight:.semibold);title.textColor=StudioTheme.text
    let detail=NSTextField(wrappingLabelWithString:"\(count) açık sorgu sekmesi\n\nSQL dosyaları kaydedilebilir. Sonuç düzenlemeleri ve uygulanmamış nesne değişiklikleri, dosya kaydıyla veritabanına gönderilmez.");detail.textColor=StudioTheme.muted;detail.font = .systemFont(ofSize:12)
    for (button,action) in [(saveButton,#selector(saveAll)),(discardButton,#selector(discardAll)),(cancelButton,#selector(cancelClose))] {button.target=self;button.action=action;button.bezelStyle = .rounded}
    saveButton.keyEquivalent="\r";cancelButton.keyEquivalent="\u{1b}";discardButton.contentTintColor=StudioTheme.danger
    saveButton.nextKeyView=discardButton;discardButton.nextKeyView=cancelButton;cancelButton.nextKeyView=saveButton
    let actions=NSStackView(views:[cancelButton,discardButton,saveButton]);actions.spacing=8
    let stack=NSStackView(views:[title,detail,actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=20
    body.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),detail.widthAnchor.constraint(equalTo:stack.widthAnchor),actions.trailingAnchor.constraint(equalTo:stack.trailingAnchor)])
    window.focusOrder=[saveButton,discardButton,cancelButton]
    window.initialFirstResponder=saveButton;window.center()
  }
  required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
  private func choose(_ choice:StudioState.BulkCloseChoice) {
    guard !completed else {return}
    guard decision(choice) else {return}
    completed=true;window?.performClose(nil)
  }
  @objc func saveAll() {choose(.save)}
  @objc func discardAll() {choose(.discard)}
  @objc func cancelClose() {choose(.cancel)}
  func windowShouldClose(_ sender:NSWindow)->Bool {completed || decision(.cancel)}
  func windowWillClose(_ notification:Notification) {completed=true;closed?()}
}

@MainActor final class StudioNoticeWindowController:NSWindowController,NSWindowDelegate {
  var closed:(()->Void)?
  init(message:String) {
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:520,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false);window.title="MSSQL Studio";window.framePersistenceRole="notice";window.animationBehavior = .none;window.isReleasedWhenClosed=false
    super.init(window:window);window.delegate=self
    let body=NSView();StudioTheme.surface(body,card:true);window.contentView=body
    let heading=NSTextField(labelWithString:"İşlem tamamlanamadı");heading.font = .systemFont(ofSize:16,weight:.semibold);heading.textColor=StudioTheme.text
    let messageView=StudioTextView();messageView.isEditable=false;messageView.isSelectable=true;messageView.string=String(message.prefix(16_000));messageView.font = .systemFont(ofSize:12);messageView.textColor=StudioTheme.text;messageView.backgroundColor=StudioTheme.canvas;messageView.textContainerInset=NSSize(width:8,height:8);messageView.isVerticallyResizable=true;messageView.autoresizingMask=[.width];messageView.textContainer?.widthTracksTextView=true
    let scroll=NSScrollView();scroll.documentView=messageView;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.borderType = .noBorder
    let done=StudioDialogButton(title:"Tamam",target:self,action:#selector(closeNotice));done.bezelStyle = .rounded;done.keyEquivalent="\r"
    let stack=NSStackView(views:[heading,scroll,done]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
    body.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-16),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:100)])
    window.focusOrder=[done]
    window.initialFirstResponder=done;window.center()
  }
  required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
  @objc func closeNotice() {window?.performClose(nil)}
  func windowWillClose(_ notification:Notification) {closed?()}
}

/// Shared presentation for legacy confirmations; button semantics stay native.
@MainActor final class StudioAlert:NSAlert {
  var framePersistenceRole:String?
  private var desiredModalFrame:NSRect?
  @objc private func restoreModalFrame(_ timer:Timer) {
    if let desiredModalFrame {window.setFrame(desiredModalFrame,display:true)}
  }
  @discardableResult override func runModal()->NSApplication.ModalResponse {
    layout();window.animationBehavior = .none;window.backgroundColor=StudioTheme.canvas
    func style(_ view:NSView) {
      if let label=view as? NSTextField,!label.isEditable {
        label.textColor=label.stringValue==messageText ? StudioTheme.text:StudioTheme.muted
        label.font = .systemFont(ofSize:label.stringValue==messageText ? 15:12,weight:label.stringValue==messageText ? .semibold:.regular)
      }
      for child in view.subviews {style(child)}
    }
    if let content=window.contentView {style(content)}
    let parent=NSApp.keyWindow ?? NSApp.mainWindow
    if let parent,parent !== window {parent.addChildWindow(window,ordered:.above)}
    var placementTimer:Timer?
    if let role=framePersistenceRole {
      StudioWindowPlacement.restore(window,role:role,owner:parent)
      // NSAlert positions itself again before its modal loop. Keep the desired
      // frame before native autosave sees that move, then restore once in that loop.
      desiredModalFrame=window.frame
      let timer=Timer(timeInterval:0,target:self,selector:#selector(restoreModalFrame(_:)),userInfo:nil,repeats:false)
      placementTimer=timer;RunLoop.main.add(timer,forMode:.modalPanel)
    }
    defer {
      placementTimer?.invalidate();desiredModalFrame=nil
      if let role=framePersistenceRole {StudioWindowPlacement.save(window,role:role);window.setFrameAutosaveName("")}
      window.parent?.removeChildWindow(window)
    }
    return super.runModal()
  }
}
